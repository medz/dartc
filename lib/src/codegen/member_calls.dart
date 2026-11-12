import 'package:dartc/ir.dart';

/// Resolves native member entries for the concrete classes in a compilation.
final class MemberCalls(
  final IrProgram program,
  final Set<FunctionTarget> definitions, {
  Iterable<ClassType> instantiatedTypes = const [],
}) {
  final _instances = {
    ...instantiatedTypes,
    for (final target in definitions)
      ...?program.implementationOf(target)?.instantiatedClasses,
  };
  final _helpers = <Object, IrFunction>{};
  final _builtins = <(ValueType, bool), IrFunction>{};

  Iterable<IrFunction> get functions => [
    ..._builtins.values,
    ..._helpers.values,
  ];

  FunctionTarget builtin(
    ValueType type, {
    required bool hash,
  }) => _builtins.putIfAbsent((type, hash), () {
    final target = FunctionTarget(
      null,
      '${type.dartName}.${hash ? 'hash' : 'equals'}',
      hash ? .integer : .boolean,
      [type, if (!hash) .object.nullable],
    );
    final entry = Block(target.parameterTypes);
    if (hash) {
      entry.finish(Return(entry.emit(ObjectHashCode(entry.parameters.first))));
      return IrFunction(target, [entry]);
    }
    final blocks = [entry];
    var current = entry;
    for (final other
        in type == .boolean
            ? [ValueType.boolean]
            : FfiTypes.isPointer(type)
            ? [FfiTypes.pointerRuntimeType]
            : [ValueType.integer, ValueType.floating]) {
      final yes = Block([other]), no = Block();
      blocks.addAll([yes, no]);
      final test = current.emit(TypeTest(entry.parameters[1], other));
      current.finish(
        Branch(test, Jump(yes, [test.refinement(true)!]), Jump(no)),
      );
      yes.finish(
        Return(yes.emit(Equals(entry.parameters.first, yes.parameters.single))),
      );
      current = no;
    }
    current.finish(const Return(Constant.boolean(false)));
    return IrFunction(target, blocks);
  }).target;

  Iterable<DynamicDispatch> get dynamicCalls sync* {
    for (final target in definitions) {
      final body = program.implementationOf(target);
      if (body is! IrFunction) continue;
      for (final block in body.blocks) {
        yield* block.instructions.whereType<DynamicDispatch>();
        if (block.end case Invoke(operation: final DynamicDispatch call)) {
          yield call;
        }
      }
    }
  }

  Map<ClassType, FunctionTarget> dynamicTargets(DynamicDispatch call) => {
    for (final type in _receivers(call.receiver.unviewedType))
      if (program.classes.any((declaration) => declaration.type == type))
        type:
            ?program.lookupMember(type, call.selector).target ??
            (call.selector.kind == .setter
                ? null
                : program.lookupMember(type, (
                    kind: call.selector.kind == .getter
                        ? FunctionKind.method
                        : FunctionKind.getter,
                    name: call.selector.name,
                    privateScope: call.selector.privateScope,
                  )).target),
  };

  Set<FunctionTarget> get tearOffTargets => {
    for (final call in dynamicCalls)
      if (call.selector.kind == .getter)
        for (final target in dynamicTargets(call).values)
          if (target.kind == .method) target,

    for (final target in definitions)
      for (final tearOff
          in program.implementationOf(target)?.methodTearOffs ??
              const <
                ({ValueType receiver, FunctionTarget method, bool direct})
              >{})
        if (tearOff.direct)
          tearOff.method
        else
          ...targetsFor(tearOff.receiver, tearOff.method.selector).values,
  };

  FunctionTarget invocationFor(
    MakeInvocation operation,
    FunctionTarget factory,
  ) => _helpers.putIfAbsent(
    (
      operation.selector,
      operation.positional.length,
      operation.named.keys.join(','),
      operation.typeArguments.length,
    ),
    () {
      final target = FunctionTarget(
        null,
        'invocation${_helpers.length}',
        CoreTypes.invocation,
        [
          for (final _ in operation.inputs) ValueType.dynamicType,
          for (final _ in operation.typeArguments) ValueType.typeType,
        ],
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
      for (final (index, name) in operation.named.keys.indexed) {
        block.emit(
          MapPut(
            named,
            symbol(name),
            block.parameters[operation.positional.length + index],
          ),
        );
      }
      final selector = operation.selector;
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
          list(.typeType, block.parameters.skip(operation.inputs.length)),
          list(
            .object.nullable,
            block.parameters.take(operation.positional.length),
          ),
          named,
        ]),
      );
      block.finish(Return(result));
      return IrFunction(target, [block]);
    },
  ).target;

  FunctionTarget getterCall(FunctionTarget getter, DynamicDispatch operation) =>
      _helpers.putIfAbsent(
        (
          getter,
          operation.positional.length,
          operation.named.keys.join(','),
          operation.typeArguments.length,
        ),
        () {
          final types = [
            for (var i = 0; i < operation.typeArguments.length; i++)
              TypeParameterType('T$i')
                ..initializeBound(.object.nullable)
                ..initializeDefaultType(.dynamicType),
          ];
          final target = FunctionTarget(
            null,
            'getterCall${_helpers.length}',
            .dynamicType,
            [for (final _ in operation.inputs) ValueType.dynamicType],
            typeParameters: types,
          );
          final block = Block(target.parameterTypes);
          final owner = getter.owner!.instantiate([
            for (final _ in getter.owner!.typeParameters) ValueType.dynamicType,
          ]);
          final receiver = block.emit(TypeCast(block.parameters.first, owner));
          final value = block.emit(
            DirectCall(getter, [receiver], ownerType: owner),
          );
          final result = block.emit(
            DynamicDispatch(
              value,
              (kind: .method, name: 'call', privateScope: null),
              block.parameters.skip(1).take(operation.positional.length),
              {
                for (final (i, name) in operation.named.keys.indexed)
                  name: block.parameters[1 + operation.positional.length + i],
              },
              types,
            ),
          );
          block.finish(Return(result));
          return IrFunction(target, [block]);
        },
      ).target;

  Iterable<ClassType> _receivers(ValueType receiver) sync* {
    for (final type in _instances) {
      if (type == ValueType.nullClass) {
        if (receiver.accepts(.nullType)) {
          yield type;
        }
        continue;
      }
      if (receiver.classBound case final owner?
          when type.asInstanceOf(owner.declaration) == null) {
        continue;
      }
      if (receiver.freeTypeParameters.isEmpty &&
          type.freeTypeParameters.isEmpty &&
          !receiver.accepts(type)) {
        continue;
      }
      yield type;
    }
  }

  Map<ClassType, FunctionTarget> targetsFor(
    ValueType receiver,
    MemberSelector selector, {
    bool hasBuiltin = false,
  }) {
    final targets = <ClassType, FunctionTarget>{};
    for (final type in _receivers(receiver)) {
      if (hasBuiltin &&
          (type == FfiTypes.pointer ||
              type == ValueType.string ||
              type == ValueType.integer ||
              type == ValueType.floating ||
              type == ValueType.boolean)) {
        continue;
      }
      final lookup = program.lookupMember(type, selector);
      if (lookup.target case final target?) {
        if (hasBuiltin && target.owner == ValueType.object) continue;
        if (!definitions.contains(target)) {
          throw ArgumentError('Missing member definition: ${target.name}');
        }
        targets[type] = target;
      } else if (!hasBuiltin ||
          lookup.unmodeledBoundary != null ||
          lookup.unsupportedForwarder) {
        throw UnsupportedError(
          'Native member unavailable: ${type.dartName}.${selector.name}',
        );
      }
    }
    // No constructed receiver means this call cannot execute in the closed program.
    return targets;
  }
}
