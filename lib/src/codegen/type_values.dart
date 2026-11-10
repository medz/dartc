import 'package:dartc/ir.dart';

enum TypeKind() {
  nominal,
  nullable,
  futureOr,
  function,
  record,
  parameter,
  dynamicType,
  voidType,
  never,
  nullType,
}

/// Generates reified type structures and their normalization through ordinary IR.
final class TypeValues() {
  static final _uri = Uri.parse('dartc:types');
  static final type = ClassType(
    _uri,
    '_Type',
    interfaces: [ValueType.typeType],
  );
  static final list = ClassType(_uri, '_TypeArguments');
  static final functionShape = ClassType(_uri, '_FunctionShape');
  static final namedParameter = ClassType(_uri, '_NamedParameter');
  static final signature = InstanceField(
    type,
    'signature',
    functionShape.nullable,
    isFinal: true,
  );
  static final binderCount = InstanceField(
    functionShape,
    'binders',
    .integer,
    isFinal: true,
  );
  static final positionalCount = InstanceField(
    functionShape,
    'positional',
    .integer,
    isFinal: true,
  );
  static final requiredCount = InstanceField(
    functionShape,
    'required',
    .integer,
    isFinal: true,
  );
  static final named = InstanceField(
    functionShape,
    'named',
    namedParameter.nullable,
    isFinal: true,
  );
  static final name = InstanceField(
    namedParameter,
    'name',
    .integer,
    isFinal: true,
  );
  static final nameSlot = InstanceField(
    namedParameter,
    'slot',
    .integer,
    isFinal: true,
  );
  static final requiredName = InstanceField(
    namedParameter,
    'required',
    .boolean,
    isFinal: true,
  );
  static final nextName = InstanceField(
    namedParameter,
    'next',
    namedParameter.nullable,
    isFinal: true,
  );
  static final kind = InstanceField(type, 'kind', .integer, isFinal: true);
  static final shape = InstanceField(type, 'shape', .integer, isFinal: true);
  static final allowsNull = InstanceField(
    type,
    'allowsNull',
    .boolean,
    isFinal: true,
  );
  static final parts = InstanceField(
    type,
    'parts',
    list.nullable,
    isFinal: true,
  );
  static final head = InstanceField(list, 'head', type, isFinal: true);
  static final tail = InstanceField(list, 'tail', list.nullable, isFinal: true);
  static final _init = FunctionTarget(
    _uri,
    '_Type',
    .voidType,
    [.integer, .integer, .boolean, list.nullable, functionShape.nullable],
    owner: type,
    kind: .initializer,
  );
  static final listInit = FunctionTarget(
    _uri,
    '_TypeArguments',
    .voidType,
    [type, list.nullable],
    owner: list,
    kind: .initializer,
  );
  final _nullable = FunctionTarget(_uri, 'nullableType', type, [type]);
  final _futureOr = FunctionTarget(_uri, 'futureOrType', type, [type]);
  final _parameter = FunctionTarget(_uri, 'boundParameter', type, [type, type]);
  final _equal = FunctionTarget(_uri, 'typeEquals', .boolean, [
    type,
    .object.nullable,
  ]);
  final _equalArguments = FunctionTarget(_uri, 'typeArgumentsEqual', .boolean, [
    list.nullable,
    list.nullable,
  ]);
  final _shapes = <Object, int>{};
  final _templates =
      <
        ValueType,
        ({FunctionTarget target, List<TypeParameterType> parameters})
      >{};
  final _functions = <FunctionTarget, IrFunction>{};

  List<IrClass> get classes => [
    IrClass(functionShape, [
      binderCount,
      positionalCount,
      requiredCount,
      named,
    ]),
    IrClass(namedParameter, [name, nameSlot, requiredName, nextName]),
    IrClass(
      type,
      [kind, shape, allowsNull, parts, signature],
      constructors: [if (_functions.containsKey(_init)) _init],
    ),
    IrClass(
      list,
      [head, tail],
      constructors: [if (_functions.containsKey(listInit)) listInit],
    ),
  ];

  Iterable<IrFunction> get functions => _functions.values;

  FunctionTarget get equality {
    _includeEquality();
    return _equal;
  }

  FunctionTarget get argumentEquality {
    _includeEquality();
    return _equalArguments;
  }

  void _includeEquality() {
    _functions.putIfAbsent(_equal, _equalityBody);
    _functions.putIfAbsent(_equalArguments, _argumentEqualityBody);
  }

  Constant argumentConstants(Iterable<ValueType> arguments) =>
      arguments.toList().reversed.fold<Constant>(
        const Constant.nullValue(),
        (next, value) =>
            ObjectConstant(list, {head: constant(value), tail: next}),
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
    );
  }

  ObjectConstant _node(
    TypeKind kind,
    int shape,
    List<ObjectConstant> children, {
    FunctionType? function,
  }) {
    Constant parts = const Constant.nullValue();
    for (final child in children.reversed) {
      parts = ObjectConstant(list, {head: child, tail: parts});
    }
    return ObjectConstant(type, {
      TypeValues.kind: Constant.integer(kind.index),
      TypeValues.shape: Constant.integer(shape),
      allowsNull: Constant.boolean(
        kind == .nullable ||
            kind == .nullType ||
            kind == .dynamicType ||
            kind == .voidType ||
            kind == .futureOr &&
                (children.single.fields[allowsNull]! as ScalarConstant).value ==
                    true,
      ),
      TypeValues.parts: parts,
      signature: function == null
          ? const Constant.nullValue()
          : _signature(function),
    });
  }

  ObjectConstant _signature(FunctionType value) {
    final names = value.named.keys.toList()..sort();
    Constant entries = const Constant.nullValue();
    for (final (index, key) in names.indexed.toList().reversed) {
      entries = ObjectConstant(namedParameter, {
        name: Constant.integer(id(key)),
        nameSlot: Constant.integer(
          value.typeParameters.length + 1 + value.positionalCount + index,
        ),
        requiredName: Constant.boolean(value.named[key]!.required),
        nextName: entries,
      });
    }
    return ObjectConstant(functionShape, {
      binderCount: Constant.integer(value.typeParameters.length),
      positionalCount: Constant.integer(value.positionalCount),
      requiredCount: Constant.integer(value.requiredPositional),
      named: entries,
    });
  }

  int id(Object key) => _shapes.putIfAbsent(key, () => _shapes.length);

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
    final target = FunctionTarget(_uri, 'reify${_templates.length}', type, [
      for (final _ in parameters) type,
    ]);
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
        signature: value is FunctionType ? _signature(value) : null,
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
            entry.emit(LoadField(TypeValues.kind, bound)),
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
    );
  }

  Construct cons(Value value, Value next) {
    _functions.putIfAbsent(
      listInit,
      () => _initializer(listInit, [head, tail]),
    );
    return Construct(listInit, [value, next]);
  }

  Value node(
    Block block,
    Value kind,
    Value shape,
    Value allowsNull,
    Value parts,
    Value signature,
  ) {
    _functions.putIfAbsent(
      _init,
      () => _initializer(_init, [
        TypeValues.kind,
        TypeValues.shape,
        TypeValues.allowsNull,
        TypeValues.parts,
        TypeValues.signature,
      ]),
    );
    return block.emit(
      Construct(_init, [kind, shape, allowsNull, parts, signature]),
    );
  }

  Value first(Block block, Value value) => block.emit(
    LoadField(
      head,
      block.emit(NullCheck(block.emit(LoadField(TypeValues.parts, value)))),
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
        entry.emit(LoadField(allowsNull, value)),
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
            bottom.emit(LoadField(TypeValues.kind, value)),
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
        nominal = Block([type]),
        object = Block(),
        bottom = Block(),
        nullType = Block();
    final future = Block(),
        optionalFuture = Block(),
        make = Block(),
        done = Block();
    final value = entry.parameters.single;
    final kind = entry.emit(LoadField(TypeValues.kind, value));
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
      nominal.emit(LoadField(TypeValues.kind, base)),
      TypeKind.nominal.index,
      object,
      bottom,
    );
    check(
      object,
      object.emit(LoadField(TypeValues.shape, base)),
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
        ], allowsNull: make.emit(LoadField(allowsNull, value))),
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

  IrFunction _equalityBody() {
    final entry = Block(_equal.parameterTypes),
        kind = Block([type]),
        shape = Block(),
        parts = Block();
    final no = Block();
    final [left, other] = entry.parameters;
    final test = entry.emit(TypeTest(other, type));
    entry.finish(Branch(test, Jump(kind, [test.refinement(true)!]), Jump(no)));
    final right = kind.parameters.single;
    kind.finish(
      Branch(
        kind.emit(
          Equals(
            kind.emit(LoadField(TypeValues.kind, left)),
            kind.emit(LoadField(TypeValues.kind, right)),
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
            shape.emit(LoadField(TypeValues.shape, left)),
            shape.emit(LoadField(TypeValues.shape, right)),
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
            parts.emit(LoadField(TypeValues.parts, left)),
            parts.emit(LoadField(TypeValues.parts, right)),
          ]),
        ),
      ),
    );
    no.finish(Return(const Constant.boolean(false)));
    return IrFunction(_equal, [entry, kind, shape, parts, no]);
  }

  IrFunction _argumentEqualityBody() {
    final entry = Block(_equalArguments.parameterTypes);
    final loop = Block(_equalArguments.parameterTypes), second = Block([list]);
    entry.finish(Jump(loop, entry.parameters));
    final compare = Block([list]),
        next = Block(),
        end = Block(),
        yes = Block(),
        no = Block();
    final [a, b] = loop.parameters;
    final first = loop.emit(TypeTest(a, list));
    loop.finish(
      Branch(first, Jump(second, [first.refinement(true)!]), Jump(end)),
    );
    final exists = second.emit(TypeTest(b, list));
    second.finish(
      Branch(exists, Jump(compare, [exists.refinement(true)!]), Jump(no)),
    );
    final aPart = second.parameters.single, bPart = compare.parameters.single;
    final equal = compare.emit(
      DirectCall(_equal, [
        compare.emit(LoadField(head, aPart)),
        compare.emit(LoadField(head, bPart)),
      ]),
    );
    compare.finish(Branch(equal, Jump(next), Jump(no)));
    next.finish(
      Jump(loop, [
        next.emit(LoadField(tail, aPart)),
        next.emit(LoadField(tail, bPart)),
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
