import 'package:dartc/ir.dart';

enum _Kind() {
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
  static final _list = ClassType(_uri, '_TypeArguments');
  static final _kind = InstanceField(type, 'kind', .integer, isFinal: true);
  static final _shape = InstanceField(type, 'shape', .integer, isFinal: true);
  static final _allowsNull = InstanceField(
    type,
    'allowsNull',
    .boolean,
    isFinal: true,
  );
  static final _parts = InstanceField(
    type,
    'parts',
    _list.nullable,
    isFinal: true,
  );
  static final _head = InstanceField(_list, 'head', type, isFinal: true);
  static final _tail = InstanceField(
    _list,
    'tail',
    _list.nullable,
    isFinal: true,
  );
  static final _init = FunctionTarget(
    _uri,
    '_Type',
    .voidType,
    [.integer, .integer, .boolean, _list.nullable],
    owner: type,
    kind: .initializer,
  );
  static final _listInit = FunctionTarget(
    _uri,
    '_TypeArguments',
    .voidType,
    [type, _list.nullable],
    owner: _list,
    kind: .initializer,
  );
  final _nullable = FunctionTarget(_uri, 'nullableType', type, [type]);
  final _futureOr = FunctionTarget(_uri, 'futureOrType', type, [type]);
  final _parameter = FunctionTarget(_uri, 'boundParameter', type, [type, type]);
  final _equal = FunctionTarget(_uri, 'typeEquals', .boolean, [
    type,
    .object.nullable,
  ]);
  final _shapes = <Object, int>{};
  final _templates =
      <
        ValueType,
        ({FunctionTarget target, List<TypeParameterType> parameters})
      >{};
  final _functions = <FunctionTarget, IrFunction>{};

  List<IrClass> get classes => [
    IrClass(
      type,
      [_kind, _shape, _allowsNull, _parts],
      constructors: [if (_functions.containsKey(_init)) _init],
    ),
    IrClass(
      _list,
      [_head, _tail],
      constructors: [if (_functions.containsKey(_listInit)) _listInit],
    ),
  ];

  Iterable<IrFunction> get functions => _functions.values;

  FunctionTarget get equality {
    _functions.putIfAbsent(_equal, _equalityBody);
    return _equal;
  }

  ObjectConstant constant(ValueType value) => _constant(value, const []);

  ObjectConstant _constant(
    ValueType value,
    List<List<TypeParameterType>> scopes,
  ) {
    final (kind, shape, children, nested) = _describe(value, scopes);
    final parts = children.map((t) => _constant(t, nested)).toList();
    if (kind == .nullable) {
      final child = parts.single;
      if (_tag(child) == .never) return constant(.nullType);
      if ((child.fields[_allowsNull]! as ScalarConstant).value == true) {
        return child;
      }
    }
    if (kind == .futureOr) {
      final child = parts.single, tag = _tag(child);
      if (_top(child)) return child;
      if (tag == .never || tag == .nullType) {
        final future = _node(.nominal, _id(ValueType.future), [child]);
        return tag == .never ? future : _node(.nullable, 0, [future]);
      }
    }
    return _node(kind, shape, parts);
  }

  ObjectConstant _node(_Kind kind, int shape, List<ObjectConstant> children) {
    Constant parts = const Constant.nullValue();
    for (final child in children.reversed) {
      parts = ObjectConstant(_list, {_head: child, _tail: parts});
    }
    return ObjectConstant(type, {
      _kind: Constant.integer(kind.index),
      _shape: Constant.integer(shape),
      _allowsNull: Constant.boolean(
        kind == .nullable ||
            kind == .nullType ||
            kind == .dynamicType ||
            kind == .voidType ||
            kind == .futureOr &&
                (children.single.fields[_allowsNull]! as ScalarConstant)
                        .value ==
                    true,
      ),
      _parts: parts,
    });
  }

  _Kind _tag(ObjectConstant value) =>
      _Kind.values[(value.fields[_kind]! as ScalarConstant).value as int];

  bool _top(ObjectConstant value) {
    final tag = _tag(value);
    if (tag == .dynamicType || tag == .voidType) return true;
    if (tag == .nullable) {
      value =
          (value.fields[_parts]! as ObjectConstant).fields[_head]!
              as ObjectConstant;
    }
    return _tag(value) == .nominal &&
        (value.fields[_shape]! as ScalarConstant).value ==
            _id(ValueType.object);
  }

  int _id(Object key) => _shapes.putIfAbsent(key, () => _shapes.length);

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

  (_Kind, int, List<ValueType>, List<List<TypeParameterType>>) _describe(
    ValueType value,
    List<List<TypeParameterType>> scopes,
  ) {
    if (value is TypeParameterType) {
      if (_bound(value, const []) == .never) return (.never, 0, [], scopes);
      for (final (depth, scope) in scopes.indexed) {
        final index = scope.indexOf(value);
        if (index >= 0) return (.parameter, _id((depth, index)), [], scopes);
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
      return (.nominal, _id(value.declaration), value.typeArguments, scopes);
    }
    if (value is RecordType) {
      final names = value.slots.keys
          .skip(value.positionalCount)
          .fold<Object?>(null, (key, name) => (key, name));
      return (
        .record,
        _id((value.positionalCount, names)),
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
        _id(shape),
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
    Value build(ValueType value, List<List<TypeParameterType>> scopes) {
      if (environment[value] case final argument?) return argument;
      if (value.freeTypeParameters.isEmpty) return constant(value);
      final (kind, shape, children, nested) = _describe(value, scopes);
      if (kind == .parameter || kind == .never) {
        final node = _node(kind, shape, []);
        if (kind == .parameter && value is TypeParameterType) {
          if (environment[_bound(value, environment.keys)] case final bound?) {
            _functions.putIfAbsent(_parameter, _parameterBody);
            return entry.emit(DirectCall(_parameter, [node, bound]));
          }
        }
        return node;
      }
      final parts = children.map((t) => build(t, nested)).toList();
      if (kind == .nullable) {
        _functions.putIfAbsent(_nullable, _nullableBody);
        return entry.emit(DirectCall(_nullable, parts));
      }
      if (kind == .futureOr) {
        _functions.putIfAbsent(_futureOr, _futureOrBody);
        return entry.emit(DirectCall(_futureOr, parts));
      }
      return _construct(entry, kind, shape, parts);
    }

    entry.finish(Return(build(template, const [])));
    _functions[target] = IrFunction(target, [entry]);
    return (target: target, parameters: parameters);
  });

  IrFunction _parameterBody() {
    final entry = Block(_parameter.parameterTypes),
        bottom = Block(),
        unchanged = Block();
    final [parameter, bound] = entry.parameters;
    entry.finish(
      Branch(
        entry.emit(
          Equals(
            entry.emit(LoadField(_kind, bound)),
            Constant.integer(_Kind.never.index),
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

  Value _construct(
    Block block,
    _Kind kind,
    int shape,
    List<Value> children, {
    Value? allowsNull,
  }) {
    _functions.putIfAbsent(
      _init,
      () => _initializer(_init, [_kind, _shape, _allowsNull, _parts]),
    );
    Value parts = const Constant.nullValue();
    for (final child in children.reversed) {
      _functions.putIfAbsent(
        _listInit,
        () => _initializer(_listInit, [_head, _tail]),
      );
      parts = block.emit(Construct(_listInit, [child, parts]));
    }
    return block.emit(
      Construct(_init, [
        Constant.integer(kind.index),
        Constant.integer(shape),
        allowsNull ?? Constant.boolean(kind == .nullable),
        parts,
      ]),
    );
  }

  Value _first(Block block, Value value) => block.emit(
    LoadField(
      _head,
      block.emit(NullCheck(block.emit(LoadField(_parts, value)))),
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
        entry.emit(LoadField(_allowsNull, value)),
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
            bottom.emit(LoadField(_kind, value)),
            Constant.integer(_Kind.never.index),
          ),
        ),
        Jump(nullValue),
        Jump(make),
      ),
    );
    make.finish(Return(_construct(make, .nullable, 0, [value])));
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
    final kind = entry.emit(LoadField(_kind, value));
    void check(Block b, Value a, int tag, Block yes, Block no) => b.finish(
      Branch(b.emit(Equals(a, Constant.integer(tag))), Jump(yes), Jump(no)),
    );
    check(entry, kind, _Kind.dynamicType.index, done, voidType);
    check(voidType, kind, _Kind.voidType.index, done, nullable);
    nullable.finish(
      Branch(
        nullable.emit(Equals(kind, Constant.integer(_Kind.nullable.index))),
        Jump(unwrap),
        Jump(nominal, [value]),
      ),
    );
    unwrap.finish(Jump(nominal, [_first(unwrap, value)]));
    final base = nominal.parameters.single;
    check(
      nominal,
      nominal.emit(LoadField(_kind, base)),
      _Kind.nominal.index,
      object,
      bottom,
    );
    check(
      object,
      object.emit(LoadField(_shape, base)),
      _id(ValueType.object),
      done,
      bottom,
    );
    check(bottom, kind, _Kind.never.index, future, nullType);
    check(nullType, kind, _Kind.nullType.index, optionalFuture, make);
    future.finish(
      Return(_construct(future, .nominal, _id(ValueType.future), [value])),
    );
    final futureValue = _construct(
      optionalFuture,
      .nominal,
      _id(ValueType.future),
      [value],
    );
    optionalFuture.finish(
      Return(_construct(optionalFuture, .nullable, 0, [futureValue])),
    );
    make.finish(
      Return(
        _construct(make, .futureOr, 0, [
          value,
        ], allowsNull: make.emit(LoadField(_allowsNull, value))),
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
    final loop = Block([_list.nullable, _list.nullable]),
        second = Block([_list]);
    final compare = Block([_list]),
        next = Block(),
        end = Block(),
        yes = Block(),
        no = Block();
    final [left, other] = entry.parameters;
    final test = entry.emit(TypeTest(other, type));
    entry.finish(Branch(test, Jump(kind, [test.refinement(true)!]), Jump(no)));
    final right = kind.parameters.single;
    kind.finish(
      Branch(
        kind.emit(
          Equals(
            kind.emit(LoadField(_kind, left)),
            kind.emit(LoadField(_kind, right)),
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
            shape.emit(LoadField(_shape, left)),
            shape.emit(LoadField(_shape, right)),
          ),
        ),
        Jump(parts),
        Jump(no),
      ),
    );
    parts.finish(
      Jump(loop, [
        parts.emit(LoadField(_parts, left)),
        parts.emit(LoadField(_parts, right)),
      ]),
    );
    final [a, b] = loop.parameters;
    final first = loop.emit(TypeTest(a, _list));
    loop.finish(
      Branch(first, Jump(second, [first.refinement(true)!]), Jump(end)),
    );
    final exists = second.emit(TypeTest(b, _list));
    second.finish(
      Branch(exists, Jump(compare, [exists.refinement(true)!]), Jump(no)),
    );
    final aPart = second.parameters.single, bPart = compare.parameters.single;
    final equal = compare.emit(
      DirectCall(_equal, [
        compare.emit(LoadField(_head, aPart)),
        compare.emit(LoadField(_head, bPart)),
      ]),
    );
    compare.finish(Branch(equal, Jump(next), Jump(no)));
    next.finish(
      Jump(loop, [
        next.emit(LoadField(_tail, aPart)),
        next.emit(LoadField(_tail, bPart)),
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
    return IrFunction(_equal, [
      entry,
      kind,
      shape,
      parts,
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
