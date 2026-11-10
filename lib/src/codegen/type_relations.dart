import 'package:dartc/ir.dart';

import 'type_values.dart';

/// Generates subtype checks over reified types, retaining lexical binder scopes.
final class TypeRelations(
  final TypeValues values,
  Iterable<ClassType> declarations,
) {
  static final _uri = Uri.parse('dartc:type-relations');
  static final _scope = ClassType(_uri, '_TypeScope');
  static final _scopeId = InstanceField(_scope, 'id', .integer, isFinal: true);
  static final _count = InstanceField(_scope, 'count', .integer, isFinal: true);
  static final _total = InstanceField(_scope, 'total', .integer, isFinal: true);
  static final _bounds = InstanceField(
    _scope,
    'bounds',
    TypeValues.list.nullable,
    isFinal: true,
  );
  static final _outer = InstanceField(
    _scope,
    'outer',
    _scope.nullable,
    isFinal: true,
  );
  static final _canonical = InstanceField(
    _scope,
    'canonical',
    _scope.nullable,
    isFinal: true,
  );
  static final _active = ClassType(_uri, '_BoundCheck');
  static final _owner = InstanceField(
    _active,
    'owner',
    .integer,
    isFinal: true,
  );
  static final _slot = InstanceField(_active, 'slot', .integer, isFinal: true);
  static final _target = InstanceField(
    _active,
    'target',
    TypeValues.type,
    isFinal: true,
  );
  static final _targetScope = InstanceField(
    _active,
    'scope',
    .integer,
    isFinal: true,
  );
  static final _next = InstanceField(
    _active,
    'next',
    _active.nullable,
    isFinal: true,
  );
  static final _scopeInit = FunctionTarget(
    _uri,
    '_TypeScope',
    .voidType,
    [
      .integer,
      .integer,
      .integer,
      TypeValues.list.nullable,
      _scope.nullable,
      _scope.nullable,
    ],
    owner: _scope,
    kind: .initializer,
  );
  static final _activeInit = FunctionTarget(
    _uri,
    '_BoundCheck',
    .voidType,
    [.integer, .integer, TypeValues.type, .integer, _active.nullable],
    owner: _active,
    kind: .initializer,
  );
  static final _contextTypes = <ValueType>[
    _scope.nullable,
    _scope.nullable,
    _active.nullable,
    .integer,
  ];
  final _entry = FunctionTarget(_uri, 'isSubtype', .boolean, [
    TypeValues.type,
    TypeValues.type,
  ]);
  final _subtype = FunctionTarget(_uri, 'subtype', .boolean, [
    TypeValues.type,
    TypeValues.type,
    ..._contextTypes,
  ]);
  final _arguments = FunctionTarget(_uri, 'typeArguments', .boolean, [
    TypeValues.list.nullable,
    TypeValues.list.nullable,
    ..._contextTypes,
  ]);
  final _nominal = FunctionTarget(_uri, 'supertype', .boolean, [
    TypeValues.type,
    TypeValues.type,
    ..._contextTypes,
  ]);
  final _function = FunctionTarget(_uri, 'functionSubtype', .boolean, [
    TypeValues.type,
    TypeValues.type,
    ..._contextTypes,
  ]);
  final _bound = FunctionTarget(_uri, 'parameterBound', .boolean, [
    TypeValues.type,
    TypeValues.type,
    ..._contextTypes,
  ]);
  final _findScope = FunctionTarget(_uri, 'parameterScope', _scope, [
    _scope.nullable,
    .integer,
  ]);
  final _bindingOwner = FunctionTarget(_uri, 'bindingOwner', _scope, [_scope]);
  final _scopeValue = FunctionTarget(_uri, 'scopeId', .integer, [
    _scope.nullable,
  ]);
  final _scopeSize = FunctionTarget(_uri, 'scopeSize', .integer, [
    _scope.nullable,
  ]);
  final _at = FunctionTarget(_uri, 'typeAt', TypeValues.type, [
    TypeValues.list.nullable,
    .integer,
  ]);
  final _findName = FunctionTarget(
    _uri,
    'parameterNamed',
    TypeValues.namedParameter.nullable,
    [TypeValues.namedParameter.nullable, .integer],
  );
  final _shift = FunctionTarget(_uri, 'shiftType', TypeValues.type, [
    TypeValues.type,
    .integer,
    .integer,
  ]);
  final _shiftParts = FunctionTarget(
    _uri,
    'shiftParts',
    TypeValues.list.nullable,
    [TypeValues.list.nullable, .integer, .integer],
  );
  final _declarations = <ClassType>{};
  bool _used = false;

  this {
    void add(ClassType value) {
      if (!_declarations.add(value.declaration)) return;
      values.id(value.declaration);
      if (value.declaration.superclass case final parent?) add(parent);
      value.declaration.interfaces.forEach(add);
    }

    [
      ...declarations,
      ...values.classes.map((c) => c.type),
      ...classes.map((c) => c.type),
      ValueType.future,
      ValueType.function,
      ValueType.record,
      ValueType.integer,
      ValueType.floating,
      ValueType.boolean,
      FfiTypes.pointer,
    ].forEach(add);
  }

  List<IrClass> get classes => [
    IrClass(
      _scope,
      [_scopeId, _count, _total, _bounds, _outer, _canonical],
      constructors: [if (_used) _scopeInit],
    ),
    IrClass(
      _active,
      [_owner, _slot, _target, _targetScope, _next],
      constructors: [if (_used) _activeInit],
    ),
  ];

  FunctionTarget get test {
    _used = true;
    return _entry;
  }

  Iterable<IrFunction> get functions => _used ? _bodies : const [];

  late final _bodies = [
    _initializer(_scopeInit, [
      _scopeId,
      _count,
      _total,
      _bounds,
      _outer,
      _canonical,
    ]),
    _initializer(_activeInit, [_owner, _slot, _target, _targetScope, _next]),
    _entryBody(),
    _subtypeBody(),
    _argumentsBody(),
    _nominalBody(),
    _functionBody(),
    _boundBody(),
    _findScopeBody(),
    _bindingOwnerBody(),
    _scopeFieldBody(_scopeValue, _scopeId),
    _scopeFieldBody(_scopeSize, _total),
    _atBody(),
    _findNameBody(),
    _shiftBody(),
    _shiftPartsBody(),
  ];

  static Constant _int(int value) => Constant.integer(value);
  static Value _load(Block block, InstanceField field, Value value) =>
      block.emit(LoadField(field, value));
  static Value _op(Block block, IntOperator op, Value a, Value b) =>
      block.emit(IntBinary(op, a, b));
  static Value _call(
    Block block,
    FunctionTarget target,
    List<Value> arguments,
  ) => block.emit(DirectCall(target, arguments));
  static void _branch(Block block, Value condition, Block yes, Block no) =>
      block.finish(Branch(condition, Jump(yes), Jump(no)));
  static void _equal(Block block, Value a, Value b, Block yes, Block no) =>
      _branch(block, block.emit(Equals(a, b)), yes, no);
  static Value _present(Block block, Value value) =>
      block.emit(NullCheck(value));
  Value _relate(Block block, Value left, Value right, List<Value> context) =>
      _call(block, _subtype, [left, right, ...context]);
  Value _part(Block block, Value value, Value index) =>
      _call(block, _at, [_load(block, TypeValues.parts, value), index]);
  Value _future(Block block, Value argument) => values.construct(
    block,
    .nominal,
    values.id(ValueType.future),
    [argument],
  );

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

  IrFunction _entryBody() {
    final entry = Block(_entry.parameterTypes);
    entry.finish(
      Return(
        _relate(entry, entry.parameters[0], entry.parameters[1], [
          const Constant.nullValue(),
          const Constant.nullValue(),
          const Constant.nullValue(),
          _int(0),
        ]),
      ),
    );
    return IrFunction(_entry, [entry]);
  }

  IrFunction _subtypeBody() {
    final entry = Block(_subtype.parameterTypes);
    final yes = Block()..finish(Return(const Constant.boolean(true)));
    final no = Block()..finish(Return(const Constant.boolean(false)));
    final blocks = [entry, yes, no];
    Block block() {
      final b = Block();
      blocks.add(b);
      return b;
    }

    final [left, right, ...context] = entry.parameters;
    final a = _load(entry, TypeValues.kind, left),
        b = _load(entry, TypeValues.kind, right);
    var current = entry;
    for (final top in [TypeKind.dynamicType, TypeKind.voidType]) {
      final next = block();
      _equal(current, b, _int(top.index), yes, next);
      current = next;
    }
    final optionalTop = block(), optionalShape = block(), source = block();
    _equal(current, b, _int(TypeKind.nullable.index), optionalTop, source);
    final base = values.first(optionalTop, right);
    _equal(
      optionalTop,
      _load(optionalTop, TypeValues.kind, base),
      _int(TypeKind.nominal.index),
      optionalShape,
      source,
    );
    _equal(
      optionalShape,
      _load(optionalShape, TypeValues.shape, base),
      _int(values.id(ValueType.object)),
      yes,
      source,
    );
    current = source;
    final afterBottom = block();
    _equal(current, a, _int(TypeKind.never.index), yes, afterBottom);
    current = afterBottom;
    for (final top in [TypeKind.dynamicType, TypeKind.voidType]) {
      final next = block();
      _equal(current, a, _int(top.index), no, next);
      current = next;
    }
    final nullSource = block(), sourceUnion = block();
    _equal(current, a, _int(TypeKind.nullType.index), nullSource, sourceUnion);
    nullSource.finish(Return(_load(nullSource, TypeValues.allowsNull, right)));
    current = sourceUnion;
    for (final kind in [TypeKind.nullable, TypeKind.futureOr]) {
      final split = block(), second = block(), next = block();
      _equal(current, a, _int(kind.index), split, next);
      final child = values.first(split, left);
      _branch(split, _relate(split, child, right, context), second, no);
      final arm = kind == .nullable
          ? values.constant(.nullType)
          : _future(second, child);
      second.finish(Return(_relate(second, arm, right, context)));
      current = next;
    }
    final fallback = block(), boundFallback = block();
    _equal(fallback, a, _int(TypeKind.parameter.index), boundFallback, no);
    boundFallback.finish(
      Return(_call(boundFallback, _bound, [left, right, ...context])),
    );
    for (final kind in [TypeKind.nullable, TypeKind.futureOr]) {
      final split = block(), next = block();
      _equal(current, b, _int(kind.index), split, next);
      final child = values.first(split, right);
      if (kind == .nullable) {
        _branch(split, _relate(split, left, child, context), yes, fallback);
      } else {
        final future = block();
        _branch(split, _relate(split, left, child, context), yes, future);
        _branch(
          future,
          _relate(future, left, _future(future, child), context),
          yes,
          fallback,
        );
      }
      current = next;
    }
    final variable = block(), nonVariable = block();
    _equal(current, a, _int(TypeKind.parameter.index), variable, nonVariable);
    final otherVariable = block(), expand = block();
    _equal(variable, b, _int(TypeKind.parameter.index), otherVariable, expand);
    final leftScope = _call(otherVariable, _findScope, [
      context[0],
      _load(otherVariable, TypeValues.shape, left),
    ]);
    final rightScope = _call(otherVariable, _findScope, [
      context[1],
      _load(otherVariable, TypeValues.shape, right),
    ]);
    final leftSlot = _parameterSlot(otherVariable, left, context[0], leftScope);
    final rightSlot = _parameterSlot(
      otherVariable,
      right,
      context[1],
      rightScope,
    );
    final sameScope = block();
    _equal(
      otherVariable,
      _load(
        otherVariable,
        _scopeId,
        _call(otherVariable, _bindingOwner, [leftScope]),
      ),
      _load(
        otherVariable,
        _scopeId,
        _call(otherVariable, _bindingOwner, [rightScope]),
      ),
      sameScope,
      expand,
    );
    _equal(sameScope, leftSlot, rightSlot, yes, expand);
    expand.finish(Return(_call(expand, _bound, [left, right, ...context])));
    final targetConcrete = block();
    _equal(nonVariable, b, _int(TypeKind.parameter.index), no, targetConcrete);
    final targetNominal = block(), structural = block();
    _equal(
      targetConcrete,
      b,
      _int(TypeKind.nominal.index),
      targetNominal,
      structural,
    );
    _equal(
      targetNominal,
      _load(targetNominal, TypeValues.shape, right),
      _int(values.id(ValueType.object)),
      yes,
      structural,
    );
    current = structural;
    for (final (kind, parent) in [
      (TypeKind.function, ValueType.function),
      (TypeKind.record, ValueType.record),
    ]) {
      final shaped = block(),
          next = block(),
          sameKind = block(),
          parentKind = block(),
          parentShape = block();
      _equal(current, a, _int(kind.index), shaped, next);
      _equal(shaped, b, _int(kind.index), sameKind, parentKind);
      _equal(parentKind, b, _int(TypeKind.nominal.index), parentShape, no);
      _equal(
        parentShape,
        _load(parentShape, TypeValues.shape, right),
        _int(values.id(parent)),
        yes,
        no,
      );
      if (kind == .function) {
        sameKind.finish(
          Return(_call(sameKind, _function, [left, right, ...context])),
        );
      } else {
        final fields = block();
        _equal(
          sameKind,
          _load(sameKind, TypeValues.shape, left),
          _load(sameKind, TypeValues.shape, right),
          fields,
          no,
        );
        fields.finish(
          Return(
            _call(fields, _arguments, [
              _load(fields, TypeValues.parts, left),
              _load(fields, TypeValues.parts, right),
              ...context,
            ]),
          ),
        );
      }
      current = next;
    }
    final nominalRight = block(),
        shapes = block(),
        sameClass = block(),
        inherited = block();
    _equal(current, a, _int(TypeKind.nominal.index), nominalRight, no);
    _equal(nominalRight, b, _int(TypeKind.nominal.index), shapes, no);
    _equal(
      shapes,
      _load(shapes, TypeValues.shape, left),
      _load(shapes, TypeValues.shape, right),
      sameClass,
      inherited,
    );
    sameClass.finish(
      Return(
        _call(sameClass, _arguments, [
          _load(sameClass, TypeValues.parts, left),
          _load(sameClass, TypeValues.parts, right),
          ...context,
        ]),
      ),
    );
    inherited.finish(
      Return(_call(inherited, _nominal, [left, right, ...context])),
    );
    return IrFunction(_subtype, blocks);
  }

  IrFunction _argumentsBody() {
    final entry = Block(_arguments.parameterTypes),
        loop = Block([TypeValues.list.nullable, TypeValues.list.nullable]);
    final leftPart = Block(), compare = Block(), next = Block(), end = Block();
    final no = Block()..finish(Return(const Constant.boolean(false)));
    final [left, right, ...context] = entry.parameters;
    entry.finish(Jump(loop, [left, right]));
    final [a, b] = loop.parameters;
    _equal(loop, a, const Constant.nullValue(), end, leftPart);
    _equal(leftPart, b, const Constant.nullValue(), no, compare);
    final first = _present(compare, a), second = _present(compare, b);
    _branch(
      compare,
      _relate(
        compare,
        _load(compare, TypeValues.head, first),
        _load(compare, TypeValues.head, second),
        context,
      ),
      next,
      no,
    );
    next.finish(
      Jump(loop, [
        _load(next, TypeValues.tail, first),
        _load(next, TypeValues.tail, second),
      ]),
    );
    end.finish(Return(end.emit(Equals(b, const Constant.nullValue()))));
    return IrFunction(_arguments, [
      entry,
      loop,
      leftPart,
      compare,
      next,
      end,
      no,
    ]);
  }

  IrFunction _nominalBody() {
    final entry = Block(_nominal.parameterTypes),
        no = Block()..finish(Return(const Constant.boolean(false)));
    final yes = Block()..finish(Return(const Constant.boolean(true)));
    final [left, right, ...context] = entry.parameters;
    final shape = _load(entry, TypeValues.shape, left),
        blocks = [entry, yes, no];
    var current = entry;
    for (final declaration in _declarations) {
      final parents = [?declaration.superclass, ...declaration.interfaces];
      if (parents.isEmpty) continue;
      final selected = Block(), next = Block();
      blocks.addAll([selected, next]);
      _equal(current, shape, _int(values.id(declaration)), selected, next);
      final environment = {
        for (final (i, parameter) in declaration.typeParameters.indexed)
          parameter: _part(selected, left, _int(i)),
      };
      var check = selected;
      for (final parent in parents) {
        final rest = Block();
        blocks.add(rest);
        final value = values.build(
          check,
          parent,
          environment,
          shift: (value, count) =>
              _call(check, _shift, [value, _int(count), _int(0)]),
        );
        _branch(check, _relate(check, value, right, context), yes, rest);
        check = rest;
      }
      check.finish(Jump(no));
      current = next;
    }
    current.finish(Jump(no));
    return IrFunction(_nominal, blocks);
  }

  Value _parameterSlot(
    Block block,
    Value parameter,
    Value context,
    Value owner,
  ) {
    final total = _call(block, _scopeSize, [context]);
    return _op(
      block,
      .subtract,
      _load(block, TypeValues.shape, parameter),
      _op(block, .subtract, total, _load(block, _total, owner)),
    );
  }

  IrFunction _scopeFieldBody(FunctionTarget target, InstanceField field) {
    final entry = Block(target.parameterTypes), empty = Block(), read = Block();
    final scope = entry.parameters.single;
    _equal(entry, scope, const Constant.nullValue(), empty, read);
    empty.finish(Return(_int(0)));
    read.finish(Return(_load(read, field, _present(read, scope))));
    return IrFunction(target, [entry, empty, read]);
  }

  IrFunction _findScopeBody() {
    final entry = Block(_findScope.parameterTypes),
        loop = Block([_scope.nullable, .integer]),
        outer = Block(),
        done = Block();
    entry.finish(Jump(loop, entry.parameters));
    final [candidate, index] = loop.parameters;
    final scope = _present(loop, candidate), count = _load(loop, _count, scope);
    _branch(loop, _op(loop, .lessThan, index, count), done, outer);
    done.finish(Return(scope));
    outer.finish(
      Jump(loop, [
        _load(outer, _outer, scope),
        _op(outer, .subtract, index, count),
      ]),
    );
    return IrFunction(_findScope, [entry, loop, outer, done]);
  }

  IrFunction _atBody() {
    final entry = Block(_at.parameterTypes),
        loop = Block([TypeValues.list.nullable, .integer]),
        next = Block(),
        done = Block();
    entry.finish(Jump(loop, entry.parameters));
    final [values, index] = loop.parameters;
    final item = _present(loop, values);
    _equal(loop, index, _int(0), done, next);
    done.finish(Return(_load(done, TypeValues.head, item)));
    next.finish(
      Jump(loop, [
        _load(next, TypeValues.tail, item),
        _op(next, .subtract, index, _int(1)),
      ]),
    );
    return IrFunction(_at, [entry, loop, next, done]);
  }

  IrFunction _findNameBody() {
    final entry = Block(_findName.parameterTypes),
        loop = Block([TypeValues.namedParameter.nullable]);
    final test = Block(), next = Block(), done = Block();
    final [names, name] = entry.parameters;
    entry.finish(Jump(loop, [names]));
    final candidate = loop.parameters.single;
    _equal(loop, candidate, const Constant.nullValue(), done, test);
    final item = _present(test, candidate);
    _equal(test, _load(test, TypeValues.name, item), name, done, next);
    next.finish(Jump(loop, [_load(next, TypeValues.nextName, item)]));
    done.finish(Return(candidate));
    return IrFunction(_findName, [entry, loop, test, next, done]);
  }

  IrFunction _bindingOwnerBody() {
    final entry = Block(_bindingOwner.parameterTypes),
        own = Block(),
        paired = Block();
    final scope = entry.parameters.single,
        canonical = _load(entry, _canonical, scope);
    _equal(entry, canonical, const Constant.nullValue(), own, paired);
    own.finish(Return(scope));
    paired.finish(Return(_present(paired, canonical)));
    return IrFunction(_bindingOwner, [entry, own, paired]);
  }

  IrFunction _boundBody() {
    final entry = Block(_bound.parameterTypes),
        loop = Block([_active.nullable]);
    final ownerCheck = Block(),
        slotCheck = Block(),
        scopeCheck = Block(),
        typeCheck = Block();
    final next = Block(), expand = Block();
    final no = Block()..finish(Return(const Constant.boolean(false)));
    final [left, right, sourceScope, targetScope, active, level] =
        entry.parameters;
    final scope = _call(entry, _findScope, [
      sourceScope,
      _load(entry, TypeValues.shape, left),
    ]);
    final slot = _parameterSlot(entry, left, sourceScope, scope);
    final canonical = _call(entry, _bindingOwner, [scope]);
    final ownerId = _load(entry, _scopeId, canonical);
    final targetId = _call(entry, _scopeValue, [targetScope]);
    entry.finish(Jump(loop, [active]));
    final candidate = loop.parameters.single;
    _equal(loop, candidate, const Constant.nullValue(), expand, ownerCheck);
    final checked = _present(ownerCheck, candidate);
    _equal(
      ownerCheck,
      _load(ownerCheck, _owner, checked),
      ownerId,
      slotCheck,
      next,
    );
    _equal(slotCheck, _load(slotCheck, _slot, checked), slot, scopeCheck, next);
    _equal(
      scopeCheck,
      _load(scopeCheck, _targetScope, checked),
      targetId,
      typeCheck,
      next,
    );
    _branch(
      typeCheck,
      _call(typeCheck, values.equality, [
        _load(typeCheck, _target, checked),
        right,
      ]),
      no,
      next,
    );
    next.finish(Jump(loop, [_load(next, _next, checked)]));
    final guard = expand.emit(
      Construct(_activeInit, [ownerId, slot, right, targetId, active]),
    );
    final bound = _call(expand, _at, [_load(expand, _bounds, canonical), slot]);
    expand.finish(
      Return(
        _relate(expand, bound, right, [canonical, targetScope, guard, level]),
      ),
    );
    return IrFunction(_bound, [
      entry,
      loop,
      ownerCheck,
      slotCheck,
      scopeCheck,
      typeCheck,
      next,
      expand,
      no,
    ]);
  }

  IrFunction _functionBody() {
    final entry = Block(_function.parameterTypes);
    final no = Block()..finish(Return(const Constant.boolean(false)));
    final yes = Block()..finish(Return(const Constant.boolean(true)));
    final [left, right, sourceScope, targetScope, active, level] =
        entry.parameters;
    final a = _present(entry, _load(entry, TypeValues.signature, left));
    final b = _present(entry, _load(entry, TypeValues.signature, right));
    final count = _load(entry, TypeValues.binderCount, a);
    final required = Block(),
        positional = Block(),
        scopes = Block(),
        bind = Block();
    final check = Block([_scope.nullable, _scope.nullable, .integer]);
    final bounds = Block([.integer]),
        forward = Block(),
        backward = Block(),
        nextBound = Block();
    final result = Block(),
        arguments = Block([.integer]),
        argument = Block(),
        nextArgument = Block();
    final named = Block(),
        names = Block([TypeValues.namedParameter.nullable]),
        find = Block(),
        compare = Block(),
        nextName = Block();
    final mandatory = Block(),
        mandatoryNames = Block([TypeValues.namedParameter.nullable]),
        mandatoryTest = Block();
    final mandatoryFind = Block(),
        mandatoryCheck = Block(),
        mandatoryNext = Block();
    _equal(entry, count, _load(entry, TypeValues.binderCount, b), required, no);
    _branch(
      required,
      _op(
        required,
        .lessOrEqual,
        _load(required, TypeValues.requiredCount, a),
        _load(required, TypeValues.requiredCount, b),
      ),
      positional,
      no,
    );
    final supplied = _load(positional, TypeValues.positionalCount, b);
    _branch(
      positional,
      _op(
        positional,
        .greaterOrEqual,
        _load(positional, TypeValues.positionalCount, a),
        supplied,
      ),
      scopes,
      no,
    );
    scopes.finish(
      Branch(
        scopes.emit(Equals(count, _int(0))),
        Jump(check, [sourceScope, targetScope, level]),
        Jump(bind),
      ),
    );
    final nestedLevel = _op(bind, .add, level, _int(1));
    final identifier = _op(bind, .multiply, nestedLevel, _int(2));
    final leftScope = bind.emit(
      Construct(_scopeInit, [
        identifier,
        count,
        _op(bind, .add, _call(bind, _scopeSize, [sourceScope]), count),
        _load(bind, TypeValues.parts, left),
        sourceScope,
        const Constant.nullValue(),
      ]),
    );
    // Both signatures bind the same fresh variables, with the source's bounds.
    final rightScope = bind.emit(
      Construct(_scopeInit, [
        _op(bind, .add, identifier, _int(1)),
        count,
        _op(bind, .add, _call(bind, _scopeSize, [targetScope]), count),
        const Constant.nullValue(),
        targetScope,
        leftScope,
      ]),
    );
    bind.finish(Jump(check, [leftScope, rightScope, nestedLevel]));
    final [leftEnvironment, rightEnvironment, depth] = check.parameters;
    final context = <Value>[leftEnvironment, rightEnvironment, active, depth];
    final reversed = <Value>[rightEnvironment, leftEnvironment, active, depth];
    check.finish(Jump(bounds, [_int(0)]));
    final index = bounds.parameters.single;
    _branch(bounds, _op(bounds, .lessThan, index, count), forward, result);
    final leftBound = _part(forward, left, index),
        rightBound = _part(forward, right, index);
    _branch(
      forward,
      _relate(forward, leftBound, rightBound, context),
      backward,
      no,
    );
    _branch(
      backward,
      _relate(backward, rightBound, leftBound, reversed),
      nextBound,
      no,
    );
    nextBound.finish(Jump(bounds, [_op(nextBound, .add, index, _int(1))]));
    _branch(
      result,
      _relate(
        result,
        _part(result, left, count),
        _part(result, right, count),
        context,
      ),
      named,
      no,
    );
    named.finish(Jump(arguments, [_int(0)]));
    final argumentIndex = arguments.parameters.single;
    _branch(
      arguments,
      _op(arguments, .lessThan, argumentIndex, supplied),
      argument,
      mandatory,
    );
    final slot = _op(
      argument,
      .add,
      _op(argument, .add, count, _int(1)),
      argumentIndex,
    );
    _branch(
      argument,
      _relate(
        argument,
        _part(argument, right, slot),
        _part(argument, left, slot),
        reversed,
      ),
      nextArgument,
      no,
    );
    nextArgument.finish(
      Jump(arguments, [_op(nextArgument, .add, argumentIndex, _int(1))]),
    );
    mandatory.finish(Jump(names, [_load(mandatory, TypeValues.named, b)]));
    final targetName = names.parameters.single;
    _equal(names, targetName, const Constant.nullValue(), mandatoryNext, find);
    final name = _present(find, targetName);
    final found = _call(find, _findName, [
      _load(find, TypeValues.named, a),
      _load(find, TypeValues.name, name),
    ]);
    _equal(find, found, const Constant.nullValue(), no, compare);
    final sourceName = _present(compare, found);
    _branch(
      compare,
      _relate(
        compare,
        _part(compare, right, _load(compare, TypeValues.nameSlot, name)),
        _part(compare, left, _load(compare, TypeValues.nameSlot, sourceName)),
        reversed,
      ),
      nextName,
      no,
    );
    nextName.finish(Jump(names, [_load(nextName, TypeValues.nextName, name)]));
    mandatoryNext.finish(
      Jump(mandatoryNames, [_load(mandatoryNext, TypeValues.named, a)]),
    );
    final candidate = mandatoryNames.parameters.single;
    _equal(
      mandatoryNames,
      candidate,
      const Constant.nullValue(),
      yes,
      mandatoryTest,
    );
    final requiredName = _present(mandatoryTest, candidate);
    final advance = Block();
    _branch(
      mandatoryTest,
      _load(mandatoryTest, TypeValues.requiredName, requiredName),
      mandatoryFind,
      advance,
    );
    final requiredTarget = _call(mandatoryFind, _findName, [
      _load(mandatoryFind, TypeValues.named, b),
      _load(mandatoryFind, TypeValues.name, requiredName),
    ]);
    _equal(
      mandatoryFind,
      requiredTarget,
      const Constant.nullValue(),
      no,
      mandatoryCheck,
    );
    _branch(
      mandatoryCheck,
      _load(
        mandatoryCheck,
        TypeValues.requiredName,
        _present(mandatoryCheck, requiredTarget),
      ),
      advance,
      no,
    );
    advance.finish(
      Jump(mandatoryNames, [_load(advance, TypeValues.nextName, requiredName)]),
    );
    return IrFunction(_function, [
      entry,
      no,
      yes,
      required,
      positional,
      scopes,
      bind,
      check,
      bounds,
      forward,
      backward,
      nextBound,
      result,
      arguments,
      argument,
      nextArgument,
      named,
      names,
      find,
      compare,
      nextName,
      mandatory,
      mandatoryNames,
      mandatoryTest,
      mandatoryFind,
      mandatoryCheck,
      mandatoryNext,
      advance,
    ]);
  }

  IrFunction _shiftBody() {
    final entry = Block(_shift.parameterTypes),
        parameter = Block(),
        changed = Block(),
        unchanged = Block();
    final shape = Block(), function = Block(), children = Block([.integer]);
    final [value, amount, cutoff] = entry.parameters;
    final kind = _load(entry, TypeValues.kind, value),
        index = _load(entry, TypeValues.shape, value);
    _equal(entry, kind, _int(TypeKind.parameter.index), parameter, shape);
    _branch(
      parameter,
      _op(parameter, .lessThan, index, cutoff),
      unchanged,
      changed,
    );
    unchanged.finish(Return(value));
    changed.finish(
      Return(
        values.node(
          changed,
          kind,
          _op(changed, .add, index, amount),
          const Constant.boolean(false),
          const Constant.nullValue(),
          const Constant.nullValue(),
        ),
      ),
    );
    shape.finish(
      Branch(
        shape.emit(Equals(kind, _int(TypeKind.function.index))),
        Jump(function),
        Jump(children, [cutoff]),
      ),
    );
    final signature = _present(
      function,
      _load(function, TypeValues.signature, value),
    );
    function.finish(
      Jump(children, [
        _op(
          function,
          .add,
          cutoff,
          _load(function, TypeValues.binderCount, signature),
        ),
      ]),
    );
    final parts = _call(children, _shiftParts, [
      _load(children, TypeValues.parts, value),
      amount,
      children.parameters.single,
    ]);
    children.finish(
      Return(
        values.node(
          children,
          kind,
          index,
          _load(children, TypeValues.allowsNull, value),
          parts,
          _load(children, TypeValues.signature, value),
        ),
      ),
    );
    return IrFunction(_shift, [
      entry,
      parameter,
      changed,
      unchanged,
      shape,
      function,
      children,
    ]);
  }

  IrFunction _shiftPartsBody() {
    final entry = Block(_shiftParts.parameterTypes),
        empty = Block(),
        copy = Block();
    final [list, amount, cutoff] = entry.parameters;
    _equal(entry, list, const Constant.nullValue(), empty, copy);
    empty.finish(Return(const Constant.nullValue()));
    final item = _present(copy, list);
    final head = _call(copy, _shift, [
      _load(copy, TypeValues.head, item),
      amount,
      cutoff,
    ]);
    final tail = _call(copy, _shiftParts, [
      _load(copy, TypeValues.tail, item),
      amount,
      cutoff,
    ]);
    copy.finish(Return(values.cons(copy, head, tail)));
    return IrFunction(_shiftParts, [entry, empty, copy]);
  }
}
