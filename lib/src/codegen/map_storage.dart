import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Generates ordered hash storage; ordinary Map algorithms belong to MapBase.
final class MapStorage({
  ClassType? mapBase,
  ClassType? linkedHashMap,
  final IrCallable? concurrentModificationError,
  final FunctionTarget Function(ClassType)? allocate,
}) {
  final key = TypeParameterType('K')
    ..initializeBound(.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final value = TypeParameterType('V')
    ..initializeBound(.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final buffer = ClassType(null, '_Buckets');
  final node = ClassType(null, '_Entry');
  late final ClassType type, view, iterator;
  late final InstanceField buckets, capacity, length, version, first, last;
  late final InstanceField hash, storedKey, storedValue, chain, next, previous;
  late final InstanceField viewedMap,
      iteratedMap,
      expected,
      cursor,
      current,
      done;
  late final FunctionTarget empty, initializer, nodeInitializer;
  late final FunctionTarget viewInitializer, iteratorInitializer, find, grow;
  final _functions = <(ClassType, FunctionKind, String), IrFunction>{};
  final entryPoints = <FunctionTarget>{};
  FunctionTarget? _allocation;

  this {
    type = ClassType.declare(null, '_Map', typeParameters: [key, value]);
    type.initializeHierarchy(
      superclass: mapBase?.instantiate([key, value]) ?? ValueType.object,
      interfaces: [
        linkedHashMap?.instantiate([key, value]) ?? CoreTypes.mapOf(key, value),
      ],
    );
    view = ClassType.declare(null, '_Keys', typeParameters: [key, value]);
    view.initializeHierarchy(superclass: CoreTypes.iterableOf(key));
    iterator = ClassType.declare(
      null,
      '_Iterator',
      typeParameters: [key, value],
    );
    iterator.initializeHierarchy(interfaces: [CoreTypes.iteratorOf(key)]);
    buckets = InstanceField(type, 'buckets', buffer);
    capacity = InstanceField(type, 'capacity', .integer);
    length = InstanceField(type, 'length', .integer);
    version = InstanceField(type, 'version', .integer);
    first = InstanceField(type, 'first', node.nullable);
    last = InstanceField(type, 'last', node.nullable);
    hash = InstanceField(node, 'hash', .integer);
    storedKey = InstanceField(node, 'key', .object.nullable);
    storedValue = InstanceField(node, 'value', .object.nullable);
    chain = InstanceField(node, 'chain', node.nullable);
    next = InstanceField(node, 'next', node.nullable);
    previous = InstanceField(node, 'previous', node.nullable);
    viewedMap = InstanceField(view, 'map', type);
    iteratedMap = InstanceField(iterator, 'map', type);
    expected = InstanceField(iterator, 'expected', .integer);
    cursor = InstanceField(iterator, 'cursor', node.nullable);
    current = InstanceField(iterator, 'current', .object.nullable);
    done = InstanceField(iterator, 'done', .boolean);
    empty = _target(type, 'empty', type, [], .factory);
    initializer = _target(type, 'new', .voidType, [buffer], .initializer);
    nodeInitializer = _target(node, 'new', .voidType, [
      .integer,
      .object.nullable,
      .object.nullable,
      node.nullable,
      node.nullable,
    ], .initializer);
    viewInitializer = _target(view, 'new', .voidType, [type], .initializer);
    iteratorInitializer = _target(iterator, 'new', .voidType, [
      type,
    ], .initializer);
    find = _target(type, '_find', node.nullable, [.object.nullable, .integer]);
    grow = _target(type, '_grow', .voidType, []);
  }

  bool get isEmpty => _functions.isEmpty;
  Iterable<IrFunction> get functions => _functions.values;
  Iterable<FunctionTarget> get allocations => [?_allocation];
  Iterable<IrClass> get classes => isEmpty
      ? []
      : [
          for (final (owner, fields) in [
            (type, [buckets, capacity, length, version, first, last]),
            (node, [hash, storedKey, storedValue, chain, next, previous]),
            (view, [viewedMap]),
            (iterator, [iteratedMap, expected, cursor, current, done]),
            (buffer, <InstanceField>[]),
          ])
            IrClass(
              owner,
              fields,
              constructors: functions
                  .map((f) => f.target)
                  .where(
                    (t) =>
                        t.owner == owner &&
                        (t.kind == .initializer || t.kind == .factory),
                  ),
              members: functions
                  .map((f) => f.target)
                  .where((t) => t.owner == owner && t.kind.isVirtual),
            ),
        ];

  FunctionTarget? callFor(Instruction operation) {
    if (operation is! NewCollection ||
        operation.collectionType.declaration != CoreTypes.map) {
      return null;
    }
    _define(empty, _factory);
    entryPoints.add(empty);
    return empty;
  }

  void prepare(Iterable<IrCallable> roots) {
    final pending = [...roots];
    for (final body in pending.whereType<IrFunction>()) {
      for (final block in body.blocks) {
        for (final op in block.instructions) {
          callFor(op);
        }
        if (block.end case Invoke(:final operation)) callFor(operation);
      }
    }
    if (isEmpty) return;
    pending.addAll(functions);
    for (var i = 0; i < pending.length; i++) {
      final body = pending[i], before = _functions.length;
      for (final member in [
        for (final target in body.virtualMembers)
          (receiver: target.owner!, selector: target.selector),
        ...body.implicitMembers,
      ]) {
        for (final owner in [type, view, iterator]) {
          if (member.receiver.nonNullable case final ClassType receiver
              when owner.asInstanceOf(receiver.declaration) == null) {
            continue;
          }
          _member(owner, member.selector);
        }
      }
      pending.addAll(functions.skip(before));
    }
  }

  FunctionTarget _target(
    ClassType owner,
    String name,
    ValueType result,
    List<ValueType> arguments, [
    FunctionKind kind = FunctionKind.method,
  ]) => FunctionTarget(null, name, result, arguments, owner: owner, kind: kind);
  IrFunction _define(FunctionTarget target, IrFunction Function() build) =>
      _functions.putIfAbsent((target.owner!, target.kind, target.name), build);
  Constant _int(int n) => Constant.integer(n);
  Value _op(Block b, IntOperator op, Value a, Value c) =>
      b.emit(IntBinary(op, a, c));
  Value _load(Block b, InstanceField field, Value receiver) =>
      b.emit(LoadField(field, receiver));
  void _store(Block b, InstanceField field, Value receiver, Value v) =>
      b.emit(StoreField(field, receiver, v));
  Value _offset(Block b, Value index) => _op(
    b,
    .add,
    _int(ObjectHeader.fieldsOffset),
    _op(b, .multiply, index, _int(8)),
  );
  Value _bucket(Block b, Value data, Value index) => b.emit(
    TypeCast(
      b.emit(LoadObjectReference(data, _offset(b, index))),
      node.nullable,
    ),
  );
  void _setBucket(Block b, Value data, Value index, Value v) =>
      b.emit(StoreObjectReference(data, _offset(b, index), v));
  Value _slot(Block b, Value map, Value h) =>
      _op(b, .bitAnd, h, _op(b, .subtract, _load(b, capacity, map), _int(1)));
  void _changed(Block b, Value map) =>
      _store(b, version, map, _op(b, .add, _load(b, version, map), _int(1)));

  void _member(ClassType owner, MemberSelector selector) {
    if (selector.privateScope != null && selector.privateScope != owner) {
      return;
    }
    if (_functions.containsKey((owner, selector.kind, selector.name))) return;
    IrFunction? body;
    if (owner == type) {
      body = switch ((selector.kind, selector.name)) {
        (FunctionKind.getter, 'length') => _getter(
          type,
          'length',
          .integer,
          length,
        ),
        (FunctionKind.getter, 'keys') => _keys(),
        (FunctionKind.method, '[]') => _lookup(false),
        (FunctionKind.method, 'containsKey') => _lookup(true),
        (FunctionKind.method, '[]=') => _put(),
        (FunctionKind.method, 'remove') => _remove(),
        (FunctionKind.method, 'clear') => _clear(),
        _ => null,
      };
    } else if (owner == view) {
      body = switch ((selector.kind, selector.name)) {
        (FunctionKind.getter, 'length') => _viewLength(),
        (FunctionKind.getter, 'iterator') => _iterator(),
        (FunctionKind.method, 'contains') => _contains(),
        _ => null,
      };
    } else {
      body = switch ((selector.kind, selector.name)) {
        (FunctionKind.getter, 'current') => _getter(
          iterator,
          'current',
          key,
          current,
        ),
        (FunctionKind.method, 'moveNext') => _moveNext(),
        _ => null,
      };
    }
    if (body != null) _functions[(owner, selector.kind, selector.name)] = body;
  }

  IrFunction _factory() {
    _allocation =
        allocate?.call(buffer) ??
        (throw UnsupportedError('Map storage requires managed allocation.'));
    _define(initializer, () {
      final b = Block(initializer.parameterTypes), map = b.parameters[0];
      for (final (field, v) in [
        (buckets, b.parameters[1]),
        (capacity, _int(8)),
        (length, _int(0)),
        (version, _int(0)),
        (first, const Constant.nullValue()),
        (last, const Constant.nullValue()),
      ]) {
        _store(b, field, map, v);
      }
      b.finish(const Return());
      return IrFunction(initializer, [b]);
    });
    final b = Block(empty.parameterTypes);
    final data = b.emit(DirectCall(_allocation!, [_int(64)]));
    b.finish(
      Return(b.emit(Construct(initializer, [data], instantiatedType: type))),
    );
    return IrFunction(empty, [b]);
  }

  IrFunction _getter(
    ClassType owner,
    String name,
    ValueType result,
    InstanceField field,
  ) {
    final target = _target(owner, name, result, [], .getter);
    final b = Block(target.parameterTypes);
    final read = _load(b, field, b.parameters.single);
    b.finish(
      Return(result.accepts(read.type) ? read : b.emit(TypeCast(read, result))),
    );
    return IrFunction(target, [b]);
  }

  IrFunction _find() {
    final entry = Block(find.parameterTypes),
        loop = Block([node.nullable]),
        check = Block(),
        equals = Block(),
        advance = Block(),
        found = Block(),
        missing = Block();
    final [map, key, code] = entry.parameters;
    final data = _load(entry, buckets, map);
    entry.finish(Jump(loop, [_bucket(entry, data, _slot(entry, map, code))]));
    final candidate = loop.parameters.single;
    loop.finish(
      Branch(
        loop.emit(TypeTest(candidate, .nullType)),
        Jump(missing),
        Jump(check),
      ),
    );
    final item = check.emit(NullCheck(candidate));
    check.finish(
      Branch(
        check.emit(Equals(_load(check, hash, item), code)),
        Jump(equals),
        Jump(advance),
      ),
    );
    equals.finish(
      Branch(
        equals.emit(Equals(_load(equals, storedKey, item), key)),
        Jump(found),
        Jump(advance),
      ),
    );
    advance.finish(Jump(loop, [_load(advance, chain, item)]));
    found.finish(Return(item));
    missing.finish(const Return(Constant.nullValue()));
    return IrFunction(find, [
      entry,
      loop,
      check,
      equals,
      advance,
      found,
      missing,
    ]);
  }

  IrFunction _lookup(bool contains) {
    _define(find, _find);
    final target = _target(
      type,
      contains ? 'containsKey' : '[]',
      contains ? ValueType.boolean : value.nullable,
      [.object.nullable],
    );
    final b = Block(target.parameterTypes), missing = Block(), found = Block();
    final [map, key] = b.parameters;
    final item = b.emit(
      DirectCall(find, [map, key, b.emit(ObjectHashCode(key))]),
    );
    b.finish(
      Branch(b.emit(TypeTest(item, .nullType)), Jump(missing), Jump(found)),
    );
    missing.finish(
      Return(
        contains ? const Constant.boolean(false) : const Constant.nullValue(),
      ),
    );
    found.finish(
      Return(
        contains
            ? const Constant.boolean(true)
            : found.emit(
                TypeCast(
                  _load(found, storedValue, found.emit(NullCheck(item))),
                  value.nullable,
                ),
              ),
      ),
    );
    return IrFunction(target, [b, missing, found]);
  }

  IrFunction _grow() {
    final entry = Block(grow.parameterTypes),
        loop = Block([node.nullable]),
        copy = Block(),
        finish = Block();
    final map = entry.parameters.single;
    final count = _op(entry, .multiply, _load(entry, capacity, map), _int(2));
    // Doubling an allocated capacity fits in int before the heap's size check.
    final data = entry.emit(
      DirectCall(_allocation!, [_op(entry, .multiply, count, _int(8))]),
    );
    entry.finish(Jump(loop, [_load(entry, first, map)]));
    final candidate = loop.parameters.single;
    loop.finish(
      Branch(
        loop.emit(TypeTest(candidate, .nullType)),
        Jump(finish),
        Jump(copy),
      ),
    );
    final item = copy.emit(NullCheck(candidate));
    final slot = _op(
      copy,
      .bitAnd,
      _load(copy, hash, item),
      _op(copy, .subtract, count, _int(1)),
    );
    _store(copy, chain, item, _bucket(copy, data, slot));
    _setBucket(copy, data, slot, item);
    copy.finish(Jump(loop, [_load(copy, next, item)]));
    _store(finish, buckets, map, data);
    _store(finish, capacity, map, count);
    finish.finish(const Return());
    return IrFunction(grow, [entry, loop, copy, finish]);
  }

  IrFunction _put() {
    _define(find, _find);
    _define(grow, _grow);
    _define(nodeInitializer, () {
      final b = Block(nodeInitializer.parameterTypes);
      for (final (i, field) in [
        hash,
        storedKey,
        storedValue,
        chain,
        previous,
      ].indexed) {
        _store(b, field, b.parameters[0], b.parameters[i + 1]);
      }
      _store(b, next, b.parameters[0], const Constant.nullValue());
      b.finish(const Return());
      return IrFunction(nodeInitializer, [b]);
    });
    final target = _target(type, '[]=', .voidType, [key, value]);
    final entry = Block(target.parameterTypes),
        update = Block(),
        insert = Block(),
        resize = Block(),
        append = Block(),
        initial = Block(),
        link = Block(),
        finish = Block();
    final [map, k, v] = entry.parameters;
    final code = entry.emit(ObjectHashCode(k));
    final found = entry.emit(DirectCall(find, [map, k, code]));
    entry.finish(
      Branch(
        entry.emit(TypeTest(found, .nullType)),
        Jump(insert),
        Jump(update),
      ),
    );
    _store(update, storedValue, update.emit(NullCheck(found)), v);
    update.finish(const Return());
    insert.finish(
      Branch(
        _op(
          insert,
          .greaterOrEqual,
          _load(insert, length, map),
          _load(insert, capacity, map),
        ),
        Jump(resize),
        Jump(append),
      ),
    );
    resize.emit(DirectCall(grow, [map]));
    resize.finish(Jump(append));
    final data = _load(append, buckets, map),
        slot = _slot(append, map, code),
        tail = _load(append, last, map);
    final item = append.emit(
      Construct(nodeInitializer, [
        code,
        k,
        v,
        _bucket(append, data, slot),
        tail,
      ]),
    );
    _setBucket(append, data, slot, item);
    append.finish(
      Branch(append.emit(TypeTest(tail, .nullType)), Jump(initial), Jump(link)),
    );
    _store(initial, first, map, item);
    initial.finish(Jump(finish));
    _store(link, next, link.emit(NullCheck(tail)), item);
    link.finish(Jump(finish));
    _store(finish, last, map, item);
    _store(
      finish,
      length,
      map,
      _op(finish, .add, _load(finish, length, map), _int(1)),
    );
    _changed(finish, map);
    finish.finish(const Return());
    return IrFunction(target, [
      entry,
      update,
      insert,
      resize,
      append,
      initial,
      link,
      finish,
    ]);
  }

  IrFunction _remove() {
    _define(find, _find);
    final target = _target(type, 'remove', value.nullable, [.object.nullable]);
    final entry = Block(target.parameterTypes),
        missing = Block(),
        found = Block(),
        head = Block(),
        loop = Block([node.nullable]),
        unlink = Block(),
        order = Block(),
        fromFirst = Block(),
        fromPrevious = Block(),
        toLast = Block(),
        toNext = Block(),
        afterPrevious = Block(),
        finish = Block();
    final [map, k] = entry.parameters;
    final code = entry.emit(ObjectHashCode(k));
    final result = entry.emit(DirectCall(find, [map, k, code]));
    entry.finish(
      Branch(
        entry.emit(TypeTest(result, .nullType)),
        Jump(missing),
        Jump(found),
      ),
    );
    missing.finish(const Return(Constant.nullValue()));
    final item = found.emit(NullCheck(result)),
        data = _load(found, buckets, map),
        slot = _slot(found, map, code);
    final bucketHead = _bucket(found, data, slot);
    found.finish(
      Branch(
        found.emit(Identical(bucketHead, item)),
        Jump(head),
        Jump(loop, [bucketHead]),
      ),
    );
    _setBucket(head, data, slot, _load(head, chain, item));
    head.finish(Jump(order));
    final predecessor = loop.emit(NullCheck(loop.parameters.single));
    final successor = _load(loop, chain, predecessor);
    loop.finish(
      Branch(
        loop.emit(Identical(successor, item)),
        Jump(unlink),
        Jump(loop, [successor]),
      ),
    );
    _store(unlink, chain, predecessor, _load(unlink, chain, item));
    unlink.finish(Jump(order));
    final before = _load(order, previous, item),
        after = _load(order, next, item);
    order.finish(
      Branch(
        order.emit(TypeTest(before, .nullType)),
        Jump(fromFirst),
        Jump(fromPrevious),
      ),
    );
    _store(fromFirst, first, map, after);
    fromFirst.finish(Jump(afterPrevious));
    _store(fromPrevious, next, fromPrevious.emit(NullCheck(before)), after);
    fromPrevious.finish(Jump(afterPrevious));
    afterPrevious.finish(
      Branch(
        afterPrevious.emit(TypeTest(after, .nullType)),
        Jump(toLast),
        Jump(toNext),
      ),
    );
    _store(toLast, last, map, before);
    toLast.finish(Jump(finish));
    _store(toNext, previous, toNext.emit(NullCheck(after)), before);
    toNext.finish(Jump(finish));
    _store(
      finish,
      length,
      map,
      _op(finish, .subtract, _load(finish, length, map), _int(1)),
    );
    _changed(finish, map);
    finish.finish(
      Return(
        finish.emit(TypeCast(_load(finish, storedValue, item), value.nullable)),
      ),
    );
    return IrFunction(target, [
      entry,
      missing,
      found,
      head,
      loop,
      unlink,
      order,
      fromFirst,
      fromPrevious,
      afterPrevious,
      toLast,
      toNext,
      finish,
    ]);
  }

  IrFunction _clear() {
    final target = _target(type, 'clear', .voidType, []);
    final entry = Block(target.parameterTypes),
        reset = Block(),
        loop = Block([.integer]),
        erase = Block(),
        finish = Block();
    final map = entry.parameters.single;
    entry.finish(
      Branch(
        entry.emit(Equals(_load(entry, length, map), _int(0))),
        Jump(finish),
        Jump(reset),
      ),
    );
    final data = _load(reset, buckets, map),
        count = _load(reset, capacity, map);
    _store(reset, length, map, _int(0));
    _store(reset, first, map, const Constant.nullValue());
    _store(reset, last, map, const Constant.nullValue());
    _changed(reset, map);
    reset.finish(Jump(loop, [_int(0)]));
    final index = loop.parameters.single;
    loop.finish(
      Branch(_op(loop, .lessThan, index, count), Jump(erase), Jump(finish)),
    );
    _setBucket(erase, data, index, const Constant.nullValue());
    erase.finish(Jump(loop, [_op(erase, .add, index, _int(1))]));
    finish.finish(const Return());
    return IrFunction(target, [entry, reset, loop, erase, finish]);
  }

  IrFunction _keys() {
    _define(viewInitializer, () {
      final b = Block(viewInitializer.parameterTypes);
      _store(b, viewedMap, b.parameters[0], b.parameters[1]);
      b.finish(const Return());
      return IrFunction(viewInitializer, [b]);
    });
    final target = _target(
          type,
          'keys',
          CoreTypes.iterableOf(key),
          [],
          .getter,
        ),
        b = Block([type]);
    b.finish(
      Return(
        b.emit(
          Construct(viewInitializer, b.parameters, instantiatedType: view),
        ),
      ),
    );
    return IrFunction(target, [b]);
  }

  IrFunction _viewLength() {
    final target = _target(view, 'length', .integer, [], .getter),
        b = Block([view]);
    b.finish(
      Return(_load(b, length, _load(b, viewedMap, b.parameters.single))),
    );
    return IrFunction(target, [b]);
  }

  IrFunction _contains() {
    final target = _target(view, 'contains', .boolean, [.object.nullable]),
        b = Block([view, .object.nullable]);
    b.finish(
      Return(
        b.emit(
          MapContainsKey(_load(b, viewedMap, b.parameters[0]), b.parameters[1]),
        ),
      ),
    );
    return IrFunction(target, [b]);
  }

  IrFunction _iterator() {
    _define(iteratorInitializer, () {
      final b = Block(iteratorInitializer.parameterTypes),
          instance = b.parameters[0],
          map = b.parameters[1];
      _store(b, iteratedMap, instance, map);
      _store(b, expected, instance, _load(b, version, map));
      _store(b, cursor, instance, _load(b, first, map));
      _store(b, current, instance, const Constant.nullValue());
      _store(b, done, instance, const Constant.boolean(false));
      b.finish(const Return());
      return IrFunction(iteratorInitializer, [b]);
    });
    final target = _target(
          view,
          'iterator',
          CoreTypes.iteratorOf(key),
          [],
          .getter,
        ),
        b = Block([view]);
    b.finish(
      Return(
        b.emit(
          Construct(iteratorInitializer, [
            _load(b, viewedMap, b.parameters.single),
          ], instantiatedType: iterator),
        ),
      ),
    );
    return IrFunction(target, [b]);
  }

  IrFunction _moveNext() {
    final target = _target(iterator, 'moveNext', .boolean, []);
    final entry = Block([iterator]),
        check = Block(),
        inspect = Block(),
        failed = Block(),
        exhausted = Block(),
        advance = Block(),
        finish = Block();
    final instance = entry.parameters.single;
    entry.finish(
      Branch(_load(entry, done, instance), Jump(finish), Jump(check)),
    );
    final map = _load(check, iteratedMap, instance);
    check.finish(
      Branch(
        check.emit(
          Equals(_load(check, expected, instance), _load(check, version, map)),
        ),
        Jump(inspect),
        Jump(failed),
      ),
    );
    final candidate = _load(inspect, cursor, instance);
    inspect.finish(
      Branch(
        inspect.emit(TypeTest(candidate, .nullType)),
        Jump(exhausted),
        Jump(advance),
      ),
    );
    final item = advance.emit(NullCheck(candidate));
    _store(advance, current, instance, _load(advance, storedKey, item));
    _store(advance, cursor, instance, _load(advance, next, item));
    advance.finish(const Return(Constant.boolean(true)));
    _store(exhausted, done, instance, const Constant.boolean(true));
    _store(exhausted, current, instance, const Constant.nullValue());
    exhausted.finish(Jump(finish));
    finish.finish(const Return(Constant.boolean(false)));
    final error =
        concurrentModificationError ??
        (throw UnsupportedError(
          'Map iteration requires ConcurrentModificationError.',
        ));
    failed.finish(Throw(failed.emit(Construct(error.target, [map]))));
    return IrFunction(target, [
      entry,
      check,
      inspect,
      failed,
      exhausted,
      advance,
      finish,
    ]);
  }
}
