import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart';

import 'type_runtime.dart';

/// Materializes static type descriptions and templates using checked Dart entries.
final class TypeValues([final TypeRuntime? runtime]) {
  TypeRuntime get _runtime =>
      runtime ?? (throw UnsupportedError('Type runtime unavailable.'));
  FunctionTarget get _init => _runtime.initializer(TypeMetadata.type);
  FunctionTarget get listInit => _runtime.initializer(TypeMetadata.list);
  FunctionTarget entry(RuntimeRole role) => _runtime.entry(role);

  final _shapes = <Object, int>{};
  final _templates =
      <
        ValueType,
        ({FunctionTarget target, List<TypeParameterType> parameters})
      >{};
  final _functions = <FunctionTarget, IrFunction>{};

  List<IrClass> get classes => [
    for (final entry in TypeMetadata.fields.entries)
      runtime?.program.classes.where((c) => c.type == entry.key).firstOrNull ??
          IrClass(entry.key, entry.value),
  ];

  Iterable<IrFunction> get functions => _functions.values;

  /// Reads the built-in runtime type without invoking user overrides.
  Value runtimeTypeOf(Value receiver, List<Value> into) {
    if (receiver.type == ValueType.integer ||
        receiver.type == ValueType.floating ||
        receiver.type == ValueType.boolean ||
        receiver.type == ValueType.nullType) {
      return constant(receiver.type);
    }
    final actual = ObjectRuntimeType(receiver, direct: true);
    final concrete = TypeReference(actual);
    into.addAll([actual, concrete]);
    return concrete;
  }

  FunctionTarget get equality => entry(.typeEquals);
  FunctionTarget get argumentEquality => entry(.typeArgumentsEqual);
  FunctionTarget get hash => entry(.typeHash);
  FunctionTarget get argumentHash => entry(.typeArgumentsHash);

  Constant argumentConstants(Iterable<ValueType> arguments) =>
      arguments.toList().reversed.fold<Constant>(
        const Constant.nullValue(),
        (next, value) => ObjectConstant(TypeMetadata.list, {
          TypeMetadata.head: constant(value),
          TypeMetadata.tail: next,
        }),
      );

  ObjectConstant constant(ValueType value) =>
      _constant(value.normalize(), const []);

  ObjectConstant _constant(
    ValueType value,
    List<List<TypeParameterType>> scopes,
  ) {
    final (kind, shape, children, nested) = _describe(value, scopes);
    final parts = children.map((t) => _constant(t, nested)).toList();
    return _node(
      kind,
      shape,
      parts,
      function: value is FunctionType ? value : null,
      record: value is RecordType ? value : null,
    );
  }

  ObjectConstant _node(
    TypeKind kind,
    int shape,
    List<ObjectConstant> children, {
    FunctionType? function,
    RecordType? record,
  }) {
    Constant parts = const Constant.nullValue();
    for (final child in children.reversed) {
      parts = ObjectConstant(TypeMetadata.list, {
        TypeMetadata.head: child,
        TypeMetadata.tail: parts,
      });
    }
    return ObjectConstant(TypeMetadata.type, {
      TypeMetadata.className: Constant.string(_label(kind, shape)),
      TypeMetadata.kind: Constant.integer(kind.index),
      TypeMetadata.shape: Constant.integer(shape),
      TypeMetadata.allowsNull: Constant.boolean(
        kind == .nullable ||
            kind == .nullType ||
            kind == .dynamicType ||
            kind == .voidType ||
            kind == .futureOr &&
                (children.single.fields[TypeMetadata.allowsNull]!
                            as ScalarConstant)
                        .value ==
                    true,
      ),
      TypeMetadata.parts: parts,
      TypeMetadata.signature: record != null
          ? _recordSignature(record)
          : function == null
          ? const Constant.nullValue()
          : _signature(function),
    });
  }

  ObjectConstant _signature(FunctionType value) {
    final names = value.named.keys.toList()..sort();
    Constant entries = const Constant.nullValue();
    for (final (index, key) in names.indexed.toList().reversed) {
      entries = ObjectConstant(TypeMetadata.namedParameter, {
        TypeMetadata.name: Constant.integer(id(key)),
        TypeMetadata.nameText: Constant.string(key),
        TypeMetadata.nameSlot: Constant.integer(
          value.typeParameters.length + 1 + value.positionalCount + index,
        ),
        TypeMetadata.requiredName: Constant.boolean(value.named[key]!.required),
        TypeMetadata.nextName: entries,
      });
    }
    return ObjectConstant(TypeMetadata.functionShape, {
      TypeMetadata.binderCount: Constant.integer(value.typeParameters.length),
      TypeMetadata.positionalCount: Constant.integer(value.positionalCount),
      TypeMetadata.requiredCount: Constant.integer(value.requiredPositional),
      TypeMetadata.named: entries,
    });
  }

  ObjectConstant _recordSignature(RecordType value) {
    Constant entries = const Constant.nullValue();
    for (final entry
        in value.slots.entries.skip(value.positionalCount).toList().reversed) {
      entries = ObjectConstant(TypeMetadata.namedParameter, {
        TypeMetadata.name: Constant.integer(id(entry.key)),
        TypeMetadata.nameText: Constant.string(entry.key),
        TypeMetadata.nameSlot: Constant.integer(entry.value),
        TypeMetadata.requiredName: const Constant.boolean(false),
        TypeMetadata.nextName: entries,
      });
    }
    return ObjectConstant(TypeMetadata.functionShape, {
      TypeMetadata.binderCount: const Constant.integer(0),
      TypeMetadata.positionalCount: Constant.integer(value.positionalCount),
      TypeMetadata.requiredCount: Constant.integer(value.positionalCount),
      TypeMetadata.named: entries,
    });
  }

  int id(Object key) => _shapes.putIfAbsent(key, () => _shapes.length);

  String _label(TypeKind kind, int shape) => kind == .nominal
      ? (_shapes.keys.elementAt(shape) as ClassType).name
      : kind == .function
      ? 'Closure'
      : kind.name;

  ValueType _bound(
    TypeParameterType parameter,
    Iterable<TypeParameterType> arguments,
  ) {
    final seen = <TypeParameterType>{};
    ValueType bound = parameter;
    while (bound is TypeParameterType &&
        !arguments.contains(bound) &&
        seen.add(bound)) {
      bound = bound.bound;
    }
    return bound;
  }

  (TypeKind, int, List<ValueType>, List<List<TypeParameterType>>) _describe(
    ValueType value,
    List<List<TypeParameterType>> scopes,
  ) {
    if (value is TypeParameterType) {
      if (_bound(value, const []) == .never) return (.never, 0, [], scopes);
      var offset = 0;
      for (final scope in scopes) {
        final index = scope.indexOf(value);
        if (index >= 0) return (.parameter, offset + index, [], scopes);
        offset += scope.length;
      }
      throw UnsupportedError('Native type needs a lexical environment: $value');
    }
    if (value == .nullType) return (.nullType, 0, [], scopes);
    if (value.nullableBase case final base?) {
      return (.nullable, 0, [base], scopes);
    }
    if (value == .dynamicType) return (.dynamicType, 0, [], scopes);
    if (value == .voidType) return (.voidType, 0, [], scopes);
    if (value == .never) return (.never, 0, [], scopes);
    if (value case FutureOrType(:final argument)) {
      return (.futureOr, 0, [argument], scopes);
    }
    if (value is ClassType) {
      return (.nominal, id(value.declaration), value.typeArguments, scopes);
    }
    if (value is RecordType) {
      final names = value.slots.keys
          .skip(value.positionalCount)
          .fold<Object?>(null, (key, name) => (key, name));
      return (
        .record,
        id((value.positionalCount, names)),
        value.fields,
        scopes,
      );
    }
    if (value is FunctionType) {
      final names = value.named.keys.toList()..sort();
      final shape = (
        value.typeParameters.length,
        value.positionalCount,
        value.requiredPositional,
        names.fold<Object?>(
          null,
          (key, name) => (key, name, value.named[name]!.required),
        ),
      );
      return (
        .function,
        id(shape),
        [
          for (final parameter in value.typeParameters) parameter.bound,
          value.result,
          ...value.parameters.take(value.positionalCount),
          for (final name in names) value.parameters[value.named[name]!.slot],
        ],
        [if (value.typeParameters.isNotEmpty) value.typeParameters, ...scopes],
      );
    }
    throw UnsupportedError('Native type structure: $value');
  }

  List<TypeParameterType> _variablesIn(ValueType template) {
    final variables = <TypeParameterType>{};
    void collect(ValueType value, List<List<TypeParameterType>> scopes) {
      if (value is TypeParameterType &&
          !scopes.any((scope) => scope.contains(value))) {
        variables.add(value);
        return;
      }
      final (_, _, children, nested) = _describe(value, scopes);
      for (final child in children) {
        collect(child, nested);
      }
    }

    collect(template, const []);
    return variables.toList();
  }

  ({FunctionTarget target, List<TypeParameterType> parameters}) instantiate(
    ValueType template,
  ) => _templates.putIfAbsent(template, () {
    final parameters = _variablesIn(template);
    final target = FunctionTarget(
      null,
      'reify${_templates.length}',
      TypeMetadata.type,
      [for (final _ in parameters) TypeMetadata.type],
    );
    final entry = Block(target.parameterTypes);
    final environment = {
      for (final (i, parameter) in parameters.indexed)
        parameter: entry.parameters[i],
    };
    entry.finish(Return(build(entry, template, environment)));
    _functions[target] = IrFunction(target, [entry]);
    return (target: target, parameters: parameters);
  });

  Value build(
    Block block,
    ValueType template,
    Map<TypeParameterType, Value> environment, {
    Value Function(Value, int)? shift,
  }) {
    Value visit(ValueType value, List<List<TypeParameterType>> scopes) {
      if (environment[value] case final argument?) {
        final count = scopes.fold(0, (count, scope) => count + scope.length);
        return count == 0 || shift == null ? argument : shift(argument, count);
      }
      if (value.freeTypeParameters.isEmpty) return constant(value);
      final (kind, shape, children, nested) = _describe(value, scopes);
      if (kind == .parameter || kind == .never) {
        final node = _node(kind, shape, []);
        if (kind == .parameter && value is TypeParameterType) {
          if (environment[_bound(value, environment.keys)] case final bound?) {
            return block.emit(DirectCall(entry(.typeParameter), [node, bound]));
          }
        }
        return node;
      }
      final parts = children.map((t) => visit(t, nested)).toList();
      if (kind == .nullable) {
        return block.emit(DirectCall(entry(.typeNullable), parts));
      }
      if (kind == .futureOr) {
        return block.emit(DirectCall(entry(.typeFutureOr), parts));
      }
      return construct(
        block,
        kind,
        shape,
        parts,
        signature: value is FunctionType
            ? _signature(value)
            : value is RecordType
            ? _recordSignature(value)
            : null,
      );
    }

    return visit(template, const []);
  }

  Value construct(
    Block block,
    TypeKind kind,
    int shape,
    List<Value> children, {
    Value? signature,
  }) {
    Value childrenList = const Constant.nullValue();
    for (final child in children.reversed) {
      childrenList = block.emit(cons(child, childrenList));
    }
    return block.emit(
      Construct(_init, [
        Constant.integer(kind.index),
        Constant.integer(shape),
        const Constant.boolean(false),
        childrenList,
        signature ?? const Constant.nullValue(),
        Constant.string(_label(kind, shape)),
      ]),
    );
  }

  Construct cons(Value value, Value next) => Construct(listInit, [value, next]);
}

/// The concrete metadata representation produced by a built-in runtimeType read.
final class TypeReference(final ObjectRuntimeType operand) extends Value {
  this : super(TypeMetadata.type) {
    if (!operand.direct) {
      throw ArgumentError('A built-in type read is required.');
    }
  }
}
