import 'package:dartc/ir.dart';
import 'package:dartc/runtime/contracts.dart' show TypeKind;

/// Generates reified type structures and their normalization through ordinary IR.
final class TypeValues() {
  static final _init = FunctionTarget(
    null,
    '_Type',
    .voidType,
    [
      .integer,
      .integer,
      .boolean,
      TypeMetadata.list.nullable,
      TypeMetadata.functionShape.nullable,
      .string,
    ],
    owner: TypeMetadata.type,
    kind: .initializer,
  );
  static final listInit = FunctionTarget(
    null,
    '_TypeArguments',
    .voidType,
    [TypeMetadata.type, TypeMetadata.list.nullable],
    owner: TypeMetadata.list,
    kind: .initializer,
  );
  final _nullable = FunctionTarget(null, 'nullableType', TypeMetadata.type, [
    TypeMetadata.type,
  ]);
  final _futureOr = FunctionTarget(null, 'futureOrType', TypeMetadata.type, [
    TypeMetadata.type,
  ]);
  final _parameter = FunctionTarget(null, 'boundParameter', TypeMetadata.type, [
    TypeMetadata.type,
    TypeMetadata.type,
  ]);
  final _equal = FunctionTarget(null, 'typeEquals', .boolean, [
    TypeMetadata.type,
    .object.nullable,
  ]);
  final _equalArguments = FunctionTarget(null, 'typeArgumentsEqual', .boolean, [
    TypeMetadata.list.nullable,
    TypeMetadata.list.nullable,
  ]);
  final _hash = FunctionTarget(null, 'typeHash', .integer, [TypeMetadata.type]);
  final _hashArguments = FunctionTarget(null, 'typeArgumentsHash', .integer, [
    TypeMetadata.list.nullable,
  ]);
  final _shapes = <Object, int>{};
  final _templates =
      <
        ValueType,
        ({FunctionTarget target, List<TypeParameterType> parameters})
      >{};
  final _functions = <FunctionTarget, IrFunction>{};

  List<IrClass> get classes => [
    IrClass(TypeMetadata.functionShape, [
      TypeMetadata.binderCount,
      TypeMetadata.positionalCount,
      TypeMetadata.requiredCount,
      TypeMetadata.named,
    ]),
    IrClass(TypeMetadata.namedParameter, [
      TypeMetadata.name,
      TypeMetadata.nameSlot,
      TypeMetadata.requiredName,
      TypeMetadata.nextName,
      TypeMetadata.nameText,
    ]),
    IrClass(
      TypeMetadata.type,
      [
        TypeMetadata.kind,
        TypeMetadata.shape,
        TypeMetadata.allowsNull,
        TypeMetadata.parts,
        TypeMetadata.signature,
        TypeMetadata.className,
      ],
      constructors: [if (_functions.containsKey(_init)) _init],
    ),
    IrClass(
      TypeMetadata.list,
      [TypeMetadata.head, TypeMetadata.tail],
      constructors: [if (_functions.containsKey(listInit)) listInit],
    ),
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

  FunctionTarget get equality {
    _includeEquality();
    return _equal;
  }

  FunctionTarget get argumentEquality {
    _includeEquality();
    return _equalArguments;
  }

  FunctionTarget get hash {
    _includeHash();
    return _hash;
  }

  FunctionTarget get argumentHash {
    _includeHash();
    return _hashArguments;
  }

  void _includeHash() {
    _functions.putIfAbsent(_hash, _hashBody);
    _functions.putIfAbsent(_hashArguments, _argumentHashBody);
  }

  void _includeEquality() {
    _functions.putIfAbsent(_equal, _equalityBody);
    _functions.putIfAbsent(_equalArguments, _argumentEqualityBody);
  }

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
            _functions.putIfAbsent(_parameter, _parameterBody);
            return block.emit(DirectCall(_parameter, [node, bound]));
          }
        }
        return node;
      }
      final parts = children.map((t) => visit(t, nested)).toList();
      if (kind == .nullable) {
        _functions.putIfAbsent(_nullable, _nullableBody);
        return block.emit(DirectCall(_nullable, parts));
      }
      if (kind == .futureOr) {
        _functions.putIfAbsent(_futureOr, _futureOrBody);
        return block.emit(DirectCall(_futureOr, parts));
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

  IrFunction _parameterBody() {
    final entry = Block(_parameter.parameterTypes),
        bottom = Block(),
        unchanged = Block();
    final [parameter, bound] = entry.parameters;
    entry.finish(
      Branch(
        entry.emit(
          Equals(
            entry.emit(LoadField(TypeMetadata.kind, bound)),
            Constant.integer(TypeKind.never.index),
          ),
        ),
        Jump(bottom),
        Jump(unchanged),
      ),
    );
    bottom.finish(Return(bound));
    unchanged.finish(Return(parameter));
    return IrFunction(_parameter, [entry, bottom, unchanged]);
  }

  IrFunction _initializer(FunctionTarget target, List<InstanceField> fields) {
    final entry = Block(target.parameterTypes);
    for (final (i, field) in fields.indexed) {
      entry.emit(
        StoreField(field, entry.parameters.first, entry.parameters[i + 1]),
      );
    }
    entry.finish(const Return());
    return IrFunction(target, [entry]);
  }

  Value construct(
    Block block,
    TypeKind kind,
    int shape,
    List<Value> children, {
    Value? allowsNull,
    Value? signature,
  }) {
    Value childrenList = const Constant.nullValue();
    for (final child in children.reversed) {
      childrenList = block.emit(cons(child, childrenList));
    }
    return node(
      block,
      Constant.integer(kind.index),
      Constant.integer(shape),
      allowsNull ?? Constant.boolean(kind == .nullable),
      childrenList,
      signature ?? const Constant.nullValue(),
      label: Constant.string(_label(kind, shape)),
    );
  }

  Construct cons(Value value, Value next) {
    _functions.putIfAbsent(
      listInit,
      () => _initializer(listInit, [TypeMetadata.head, TypeMetadata.tail]),
    );
    return Construct(listInit, [value, next]);
  }

  Value node(
    Block block,
    Value kind,
    Value shape,
    Value allowsNull,
    Value parts,
    Value signature, {
    Value? label,
  }) {
    _functions.putIfAbsent(
      _init,
      () => _initializer(_init, [
        TypeMetadata.kind,
        TypeMetadata.shape,
        TypeMetadata.allowsNull,
        TypeMetadata.parts,
        TypeMetadata.signature,
        TypeMetadata.className,
      ]),
    );
    return block.emit(
      Construct(_init, [
        kind,
        shape,
        allowsNull,
        parts,
        signature,
        label ?? Constant.string('Type'),
      ]),
    );
  }

  Value first(Block block, Value value) => block.emit(
    LoadField(
      TypeMetadata.head,
      block.emit(NullCheck(block.emit(LoadField(TypeMetadata.parts, value)))),
    ),
  );

  IrFunction _nullableBody() {
    final entry = Block(_nullable.parameterTypes),
        bottom = Block(),
        make = Block(),
        done = Block();
    final value = entry.parameters.single;
    entry.finish(
      Branch(
        entry.emit(LoadField(TypeMetadata.allowsNull, value)),
        Jump(done),
        Jump(bottom),
      ),
    );
    done.finish(Return(value));
    final nullValue = Block()..finish(Return(constant(.nullType)));
    bottom.finish(
      Branch(
        bottom.emit(
          Equals(
            bottom.emit(LoadField(TypeMetadata.kind, value)),
            Constant.integer(TypeKind.never.index),
          ),
        ),
        Jump(nullValue),
        Jump(make),
      ),
    );
    make.finish(Return(construct(make, .nullable, 0, [value])));
    return IrFunction(_nullable, [entry, bottom, make, done, nullValue]);
  }

  IrFunction _futureOrBody() {
    final entry = Block(_futureOr.parameterTypes),
        voidType = Block(),
        nullable = Block();
    final unwrap = Block(),
        nominal = Block([TypeMetadata.type]),
        object = Block(),
        bottom = Block(),
        nullType = Block();
    final future = Block(),
        optionalFuture = Block(),
        make = Block(),
        done = Block();
    final value = entry.parameters.single;
    final kind = entry.emit(LoadField(TypeMetadata.kind, value));
    void check(Block b, Value a, int tag, Block yes, Block no) => b.finish(
      Branch(b.emit(Equals(a, Constant.integer(tag))), Jump(yes), Jump(no)),
    );
    check(entry, kind, TypeKind.dynamicType.index, done, voidType);
    check(voidType, kind, TypeKind.voidType.index, done, nullable);
    nullable.finish(
      Branch(
        nullable.emit(Equals(kind, Constant.integer(TypeKind.nullable.index))),
        Jump(unwrap),
        Jump(nominal, [value]),
      ),
    );
    unwrap.finish(Jump(nominal, [first(unwrap, value)]));
    final base = nominal.parameters.single;
    check(
      nominal,
      nominal.emit(LoadField(TypeMetadata.kind, base)),
      TypeKind.nominal.index,
      object,
      bottom,
    );
    check(
      object,
      object.emit(LoadField(TypeMetadata.shape, base)),
      id(ValueType.object),
      done,
      bottom,
    );
    check(bottom, kind, TypeKind.never.index, future, nullType);
    check(nullType, kind, TypeKind.nullType.index, optionalFuture, make);
    future.finish(
      Return(construct(future, .nominal, id(ValueType.future), [value])),
    );
    final futureValue = construct(
      optionalFuture,
      .nominal,
      id(ValueType.future),
      [value],
    );
    optionalFuture.finish(
      Return(construct(optionalFuture, .nullable, 0, [futureValue])),
    );
    make.finish(
      Return(
        construct(make, .futureOr, 0, [
          value,
        ], allowsNull: make.emit(LoadField(TypeMetadata.allowsNull, value))),
      ),
    );
    done.finish(Return(value));
    return IrFunction(_futureOr, [
      entry,
      voidType,
      nullable,
      unwrap,
      nominal,
      object,
      bottom,
      nullType,
      future,
      optionalFuture,
      make,
      done,
    ]);
  }

  Value _mixHash(Block block, Value seed, Value value) => block.emit(
    IntBinary(
      .bitAnd,
      block.emit(
        IntBinary(
          .add,
          block.emit(IntBinary(.multiply, seed, const Constant.integer(31))),
          value,
        ),
      ),
      const Constant.integer(0x3fffffff),
    ),
  );

  IrFunction _hashBody() {
    final entry = Block(_hash.parameterTypes);
    final value = entry.parameters.single;
    final seed = _mixHash(
      entry,
      entry.emit(LoadField(TypeMetadata.kind, value)),
      entry.emit(LoadField(TypeMetadata.shape, value)),
    );
    final partsHash = entry.emit(
      DirectCall(_hashArguments, [
        entry.emit(LoadField(TypeMetadata.parts, value)),
      ]),
    );
    entry.finish(Return(_mixHash(entry, seed, partsHash)));
    return IrFunction(_hash, [entry]);
  }

  IrFunction _argumentHashBody() {
    final entry = Block(_hashArguments.parameterTypes);
    final loop = Block([TypeMetadata.list.nullable, .integer]),
        step = Block([TypeMetadata.list]),
        done = Block();
    entry.finish(
      Jump(loop, [entry.parameters.single, const Constant.integer(0)]),
    );
    final [values, seed] = loop.parameters;
    final test = loop.emit(TypeTest(values, TypeMetadata.list));
    loop.finish(Branch(test, Jump(step, [test.refinement(true)!]), Jump(done)));
    final node = step.parameters.single;
    final value = step.emit(
      DirectCall(_hash, [step.emit(LoadField(TypeMetadata.head, node))]),
    );
    final hash = _mixHash(step, seed, value);
    step.finish(
      Jump(loop, [step.emit(LoadField(TypeMetadata.tail, node)), hash]),
    );
    done.finish(Return(seed));
    return IrFunction(_hashArguments, [entry, loop, step, done]);
  }

  IrFunction _equalityBody() {
    final entry = Block(_equal.parameterTypes),
        kind = Block([TypeMetadata.type]),
        shape = Block(),
        parts = Block();
    final no = Block();
    final [left, other] = entry.parameters;
    final test = entry.emit(TypeTest(other, TypeMetadata.type));
    entry.finish(Branch(test, Jump(kind, [test.refinement(true)!]), Jump(no)));
    final right = kind.parameters.single;
    kind.finish(
      Branch(
        kind.emit(
          Equals(
            kind.emit(LoadField(TypeMetadata.kind, left)),
            kind.emit(LoadField(TypeMetadata.kind, right)),
          ),
        ),
        Jump(shape),
        Jump(no),
      ),
    );
    shape.finish(
      Branch(
        shape.emit(
          Equals(
            shape.emit(LoadField(TypeMetadata.shape, left)),
            shape.emit(LoadField(TypeMetadata.shape, right)),
          ),
        ),
        Jump(parts),
        Jump(no),
      ),
    );
    parts.finish(
      Return(
        parts.emit(
          DirectCall(_equalArguments, [
            parts.emit(LoadField(TypeMetadata.parts, left)),
            parts.emit(LoadField(TypeMetadata.parts, right)),
          ]),
        ),
      ),
    );
    no.finish(Return(const Constant.boolean(false)));
    return IrFunction(_equal, [entry, kind, shape, parts, no]);
  }

  IrFunction _argumentEqualityBody() {
    final entry = Block(_equalArguments.parameterTypes);
    final loop = Block(_equalArguments.parameterTypes),
        second = Block([TypeMetadata.list]);
    entry.finish(Jump(loop, entry.parameters));
    final compare = Block([TypeMetadata.list]),
        next = Block(),
        end = Block(),
        yes = Block(),
        no = Block();
    final [a, b] = loop.parameters;
    final first = loop.emit(TypeTest(a, TypeMetadata.list));
    loop.finish(
      Branch(first, Jump(second, [first.refinement(true)!]), Jump(end)),
    );
    final exists = second.emit(TypeTest(b, TypeMetadata.list));
    second.finish(
      Branch(exists, Jump(compare, [exists.refinement(true)!]), Jump(no)),
    );
    final aPart = second.parameters.single, bPart = compare.parameters.single;
    final equal = compare.emit(
      DirectCall(_equal, [
        compare.emit(LoadField(TypeMetadata.head, aPart)),
        compare.emit(LoadField(TypeMetadata.head, bPart)),
      ]),
    );
    compare.finish(Branch(equal, Jump(next), Jump(no)));
    next.finish(
      Jump(loop, [
        next.emit(LoadField(TypeMetadata.tail, aPart)),
        next.emit(LoadField(TypeMetadata.tail, bPart)),
      ]),
    );
    end.finish(
      Branch(
        end.emit(Equals(b, const Constant.nullValue())),
        Jump(yes),
        Jump(no),
      ),
    );
    yes.finish(Return(const Constant.boolean(true)));
    no.finish(Return(const Constant.boolean(false)));
    return IrFunction(_equalArguments, [
      entry,
      loop,
      second,
      compare,
      next,
      end,
      yes,
      no,
    ]);
  }
}

/// The concrete metadata representation produced by a built-in runtimeType read.
final class TypeReference(final ObjectRuntimeType operand) extends Value {
  this : super(TypeMetadata.type) {
    if (!operand.direct) {
      throw ArgumentError('A built-in type read is required.');
    }
  }
}
