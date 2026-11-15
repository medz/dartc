import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'heap_runtime.dart';
import 'list_storage.dart';
import 'numeric_normalization.dart';
import 'suspension_normalization.dart';

/// Resolves semantic operations to their checked implementation before analysis.
///
/// Generated support bodies use the same normalization as source bodies.
/// Physical storage, calling conventions and machine operands are chosen later.
final class ProgramNormalization(
  final IrProgram program, {
  final HeapRuntime? runtime,
}) {
  final _helpers = <Object, IrFunction>{};
  late final _lists = ListStorage(program.classes);
  late final _numeric = NumericNormalization(
    _helpers,
    argumentError: _constructor(ValueType.argumentError),
    unsupportedError: _constructor(ValueType.unsupportedError),
    floatingRemainder: runtime?.floatingRemainder,
    floatingModulo: runtime?.floatingModulo,
  );
  final _classes = {
    for (final declaration in program.classes) declaration.type: declaration,
  };

  /// Returns the original program when no operation needs lowering.
  IrProgram run() {
    var changed = false;
    final functions = <IrFunction>[];
    for (final source in program.functions) {
      final result = _function(source);
      changed |= !identical(result, source);
      functions.add(result);
    }
    for (var index = 0; index < _helpers.length; index++) {
      functions.add(_function(_helpers.values.elementAt(index)));
      changed = true;
    }
    final externals = <IrExternal>[];
    for (final external in program.externals) {
      final defaults = {
        for (final entry in external.defaults.entries)
          entry.key: _constant(entry.value),
      };
      final updated = defaults.entries.any(
        (entry) => !identical(entry.value, external.defaults[entry.key]),
      );
      changed |= updated;
      externals.add(
        updated
            ? IrExternal(
                external.target,
                defaults: defaults,
                effects: external.effects,
              )
            : external,
      );
    }
    final normalized = changed
        ? IrProgram(
            [
              ...program.classes,
              for (final declaration in _numeric.classes)
                if (!_classes.containsKey(declaration.type)) declaration,
            ],
            functions,
            globals: program.globals,
            externals: externals,
          )
        : program;
    if (normalized.functions.every((body) => body.bodyKind == .synchronous)) {
      return normalized;
    }
    return SuspensionNormalization(
      normalized,
      runtime ??
          (throw StateError('Suspension normalization requires runtime.')),
    ).run();
  }

  IrCallable? _constructor(ClassType type) {
    final target = _classes[type]?.constructors['new'];
    return target == null ? null : program.implementationOf(target);
  }

  IrFunction _function(IrFunction source) {
    final operations = <Instruction, Instruction>{};
    for (final block in source.blocks) {
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        final replacement = switch (operation) {
          MakeInvocation(
            :final selector,
            :final positional,
            :final named,
            :final typeArguments,
          ) =>
            DirectCall(
              _invocation(
                selector,
                positional.length,
                named.keys.toList(),
                typeArguments.length,
              ),
              operation.inputs,
              typeArguments: typeArguments,
            ),
          final DynamicDispatch call when call.failure == null => _dispatch(
            call,
          ),
          NewCollection(:final collectionType, :final growable) => _construct(
            collectionType,
            collectionType.declaration == CoreTypes.list ? 'empty' : 'new',
            const [],
            collectionType.declaration == CoreTypes.list
                ? {'growable': growable ?? const Constant.boolean(true)}
                : const {},
          ),
          ListFilled(
            :final type,
            :final length,
            :final fill,
            :final growable,
          ) =>
            _construct(
              type as ClassType,
              'filled',
              [length, fill],
              {'growable': growable},
            ),
          ListFrom(:final type, :final elements, :final growable) => _construct(
            type as ClassType,
            'from',
            [elements],
            {'growable': growable},
          ),
          CollectionSpread(
            isMethodCall: false,
            :final collection,
            :final source,
          )
              when CoreTypes.view(collection.type, CoreTypes.list) != null =>
            DirectCall(
              program.classes
                  .singleWhere((c) => c.listStorage != null)
                  .listStorage!
                  .spread,
              [collection, source],
              typeArguments: [
                CoreTypes.view(
                  collection.type,
                  CoreTypes.list,
                )!.typeArguments.single,
              ],
            ),
          _ => _numeric.normalize(operation),
        };
        if (replacement != null) operations[operation] = replacement;
      }
    }
    return operations.isEmpty && source.sequenceConstants.isEmpty
        ? source
        : FunctionRewrite(
            source,
            operations: operations,
            constants: _constant,
          ).run();
  }

  Constant _constant(Constant value) {
    var changed = false;
    Constant child(Constant value) {
      final result = _constant(value);
      changed |= !identical(result, value);
      return result;
    }

    switch (value) {
      case SequenceConstant(:final type, :final elements):
        final values = elements.map(child).toList();
        if ((type as ClassType).declaration == CoreTypes.list) {
          return ObjectConstant(_lists.type.instantiate(type.typeArguments), {
            _lists.length: Constant.integer(values.length),
            _lists.data: ObjectConstant(_lists.buffer, {}, payload: values),
          });
        }
        return changed ? SequenceConstant(type, values) : value;
      case ObjectConstant(:final type, :final fields, :final payload):
        final values = {
          for (final entry in fields.entries) entry.key: child(entry.value),
        };
        final references = payload.map(child).toList();
        return changed
            ? ObjectConstant(type as ClassType, values, payload: references)
            : value;
      case RecordConstant(:final type, :final fields):
        final values = fields.map(child).toList();
        return changed ? RecordConstant(type as RecordType, values) : value;
      case MapConstant(:final type, :final entries):
        final values = [
          for (final (key, value) in entries) (child(key), child(value)),
        ];
        return changed ? MapConstant(type as ClassType, values) : value;
      default:
        return value;
    }
  }

  DynamicDispatch _dispatch(DynamicDispatch operation) {
    final selector = operation.selector;
    final getter = (
      kind: FunctionKind.getter,
      name: selector.name,
      privateScope: selector.privateScope,
    );
    return DynamicDispatch(
      operation.receiver,
      selector,
      operation.positional,
      operation.named,
      operation.typeArguments,
      _failure(
        selector,
        operation.positional.length,
        operation.named.keys.toList(),
        operation.typeArguments.length,
      ),
      {
        if (selector.kind == .method)
          for (final target in {
            for (final declaration in program.classes)
              ?program.lookupMember(declaration.type, getter).target,
          })
            if (program.implementationOf(target) != null)
              target: _getterCall(target, operation),
      },
    );
  }

  FunctionTarget _getterCall(
    FunctionTarget getter,
    DynamicDispatch operation,
  ) => _helpers.putIfAbsent(
    (
      getter,
      operation.positional.length,
      operation.named.keys.fold<Object?>(null, (key, name) => (key, name)),
      operation.typeArguments.length,
    ),
    () {
      final types = _typeParameters(operation.typeArguments.length);
      final target = FunctionTarget(
        null,
        'getterCall${_helpers.length}',
        .dynamicType,
        [for (final _ in operation.inputs) ValueType.dynamicType],
        typeParameters: types,
      );
      final block = Block(target.parameterTypes);
      final value = block.emit(
        DynamicDispatch(block.parameters.first, getter.selector, []),
      );
      final result = block.emit(
        DynamicDispatch(
          value,
          (kind: .method, name: 'call', privateScope: null),
          block.parameters.skip(1).take(operation.positional.length),
          {
            for (final (index, name) in operation.named.keys.indexed)
              name: block.parameters[1 + operation.positional.length + index],
          },
          types,
        ),
      );
      block.finish(Return(result));
      return IrFunction(target, [block]);
    },
  ).target;

  FunctionTarget _invocation(
    MemberSelector selector,
    int positional,
    List<String> names,
    int typeCount,
  ) => _helpers.putIfAbsent(
    (
      selector,
      positional,
      names.fold<Object?>(null, (key, name) => (key, name)),
      typeCount,
      false,
    ),
    () {
      final factory =
          runtime?.invocation ??
          (throw StateError('Invocation normalization requires runtime.'));
      final types = _typeParameters(typeCount);
      final target = FunctionTarget(
        null,
        'invocation${_helpers.length}',
        CoreTypes.invocation,
        [
          for (var i = 0; i < positional + names.length; i++)
            ValueType.dynamicType,
        ],
        typeParameters: types,
      );
      final block = Block(target.parameterTypes);
      Value list(ValueType element, Iterable<Value> values) {
        final result = block.emit(NewCollection(CoreTypes.listOf(element)));
        for (final value in values) {
          block.emit(CollectionAdd(result, value));
        }
        return result;
      }

      ObjectConstant symbol(String name, [Object? library]) =>
          ObjectConstant(CoreTypes.symbolStorage, {
            CoreTypes.symbolName: Constant.string(name),
            CoreTypes.symbolPrivateLibrary: library == null
                ? const Constant.nullValue()
                : Constant.string(library.toString()),
          });
      final named = block.emit(
        NewCollection(CoreTypes.mapOf(CoreTypes.symbol, .object.nullable)),
      );
      for (final (index, name) in names.indexed) {
        block.emit(
          MapPut(named, symbol(name), block.parameters[positional + index]),
        );
      }
      final result = block.emit(
        DirectCall(factory, [
          symbol(
            selector.kind == .setter ? '${selector.name}=' : selector.name,
            selector.privateScope,
          ),
          Constant.integer(
            selector.kind == .getter
                ? 1
                : selector.kind == .setter
                ? 2
                : 0,
          ),
          list(.typeType, [
            for (final type in types) block.emit(ReifyType(type)),
          ]),
          list(.object.nullable, block.parameters.take(positional)),
          named,
        ]),
      );
      block.finish(Return(result));
      return IrFunction(target, [block]);
    },
  ).target;

  FunctionTarget _failure(
    MemberSelector selector,
    int positional,
    List<String> names,
    int typeCount,
  ) {
    final ordered = names.toList()..sort();
    final invocation = _invocation(selector, positional, ordered, typeCount);
    return _helpers.putIfAbsent(
      (invocation, names.fold<Object?>(null, (key, name) => (key, name)), true),
      () {
        final dispatch =
            runtime?.dispatchFailure ??
            (throw StateError(
              'Dynamic dispatch normalization requires runtime.',
            ));
        final types = _typeParameters(typeCount);
        final target = FunctionTarget(
          null,
          'missing${_helpers.length}',
          .dynamicType,
          [
            for (var i = 0; i <= positional + names.length; i++)
              ValueType.dynamicType,
          ],
          typeParameters: types,
        );
        final block = Block(target.parameterTypes);
        final mirror = block.emit(
          DirectCall(invocation, [
            ...block.parameters.skip(1).take(positional),
            for (final name in ordered)
              block.parameters[1 + positional + names.indexOf(name)],
          ], typeArguments: types),
        );
        block.finish(
          Return(
            block.emit(DirectCall(dispatch, [block.parameters.first, mirror])),
          ),
        );
        return IrFunction(target, [block]);
      },
    ).target;
  }

  List<TypeParameterType> _typeParameters(int count) => [
    for (var index = 0; index < count; index++)
      TypeParameterType('T$index')
        ..initializeBound(.object.nullable)
        ..initializeDefaultType(.dynamicType),
  ];

  Instruction _construct(
    ClassType type,
    String name,
    List<Value> positional,
    Map<String, Value> named,
  ) {
    final constructor =
        _classes[type.declaration]?.constructors[name] ??
        (throw ArgumentError(
          'Missing checked collection constructor: ${type.dartName}.$name',
        ));
    final (:target, :ownerType) = constructor.resolveConstruction(type);
    final body =
        program.implementationOf(target) ??
        (throw ArgumentError('Missing constructor body: ${target.name}'));
    final arguments = target.signature.bind<Value>(
      positional,
      named,
      (index) => body.defaults[index]!,
    );
    return target.kind == .initializer
        ? Construct(target, arguments, instantiatedType: ownerType)
        : DirectCall(target, arguments, ownerType: ownerType);
  }
}
