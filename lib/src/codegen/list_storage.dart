import 'dart:ffi' show Uint64;

import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Permitted List changes encoded in the storage flag.
enum ListMutability() {
  immutable,
  fixed,
  growable,
}

/// Owns List storage and generates ordinary Dart member bodies for it.
final class ListStorage({
  final IrCallable? indexError,
  final IrCallable? rangeError,
  final IrCallable? unsupportedError,
  final IrCallable? iteratorConstructor,
  final IrCallable? concurrentModificationError,
  final FunctionTarget Function(ClassType)? allocate,
  final bool hasConstants = false,
}) {
  static final _uri = Uri.parse('dartc:lists');
  final element = TypeParameterType('E')
    ..initializeBound(.object.nullable)
    ..initializeDefaultType(.dynamicType);
  final _spreadElement = TypeParameterType('T')
    ..initializeBound(.object.nullable)
    ..initializeDefaultType(.dynamicType);
  late final _spread = FunctionTarget(
    _uri,
    'spread',
    .voidType,
    [CoreTypes.listOf(_spreadElement), CoreTypes.iterableOf(.object.nullable)],
    typeParameters: [_spreadElement],
  );
  final buffer = ClassType(_uri, '_ListData');
  late final ClassType type;
  late final InstanceField length, data, mutability;
  late final FunctionTarget initializer, empty, filled, reserve;
  final _functions = <(FunctionKind, String), IrFunction>{};
  final entryPoints = <FunctionTarget>{};
  FunctionTarget? _allocation;

  this {
    type = ClassType.declare(_uri, '_List', typeParameters: [element]);
    type.initializeHierarchy(interfaces: [CoreTypes.listOf(element)]);
    length = InstanceField(type, 'length', .integer);
    data = InstanceField(type, 'data', buffer);
    mutability = InstanceField(type, 'mutability', .integer);
    initializer = _target('new', .voidType, [
      .integer,
      buffer,
      .integer,
    ], .initializer);
    empty = _target('empty', type, [.boolean], .factory);
    filled = _target('filled', type, [.integer, element, .boolean], .factory);
    reserve = _target('_reserve', .voidType, [.integer], .method);
  }

  Iterable<IrFunction> get functions => _functions.values;
  Iterable<FunctionTarget> get allocations => [?_allocation];
  bool get isEmpty => _functions.isEmpty && !hasConstants;
  IrClass get declaration => IrClass(
    type,
    [length, data, mutability],
    constructors: functions
        .map((f) => f.target)
        .where((t) => t.kind == .initializer || t.kind == .factory),
    members: functions.map((f) => f.target).where((t) => t.kind.isVirtual),
  );
  Iterable<IrClass> get classes =>
      isEmpty ? [] : [declaration, IrClass(buffer, [])];

  FunctionTarget? callFor(Instruction operation) {
    final target = switch (operation) {
      NewCollection(:final collectionType)
          when collectionType.declaration == CoreTypes.list =>
        empty,
      ListFilled() => filled,
      CollectionSpread(:final collection, isMethodCall: false)
          when CoreTypes.view(collection.type, CoreTypes.list) != null =>
        _spread,
      _ => null,
    };
    if (target != null) {
      _define(
        target,
        () => target == _spread ? _append(false) : _factory(target == filled),
      );
      entryPoints.add(target);
    }
    return target;
  }

  FunctionTarget _target(
    String name,
    ValueType result,
    List<ValueType> parameters,
    FunctionKind kind,
  ) => FunctionTarget(_uri, name, result, parameters, owner: type, kind: kind);
  Constant _int(int value) => Constant.integer(value);
  Value _op(Block block, IntOperator op, Value left, Value right) =>
      block.emit(IntBinary(op, left, right));
  Value _offset(Block block, Value index) => _op(
    block,
    .add,
    _int(ObjectLayout.fieldsOffset),
    _op(block, .multiply, index, _int(8)),
  );
  Value _get(Block block, Value buffer, Value index) =>
      block.emit(LoadObjectReference(buffer, _offset(block, index)));
  void _set(Block block, Value buffer, Value index, Value value) =>
      block.emit(StoreObjectReference(buffer, _offset(block, index), value));

  Value _error(
    Block block,
    IrCallable? constructor,
    List<Value> arguments, [
    Map<String, Value> named = const {},
  ]) {
    if (constructor == null) {
      throw UnsupportedError(
        'List operations require the SDK error constructors.',
      );
    }
    return block.emit(
      Construct(
        constructor.target,
        constructor.target.signature.bind<Value>(
          arguments,
          named,
          (i) => constructor.defaults[i]!,
        ),
      ),
    );
  }

  IrFunction _define(FunctionTarget target, IrFunction Function() build) =>
      _functions.putIfAbsent((target.kind, target.name), build);

  /// Defines requested construction, members and their generated dependencies.
  void prepare(Iterable<IrCallable> roots) {
    final pending = <IrCallable>[...roots];
    for (final body in pending.whereType<IrFunction>()) {
      for (final block in body.blocks) {
        for (final operation in block.instructions) {
          callFor(operation);
        }
        if (block.end case Invoke(:final operation)) callFor(operation);
      }
    }
    if (isEmpty) return;
    pending.addAll(functions);
    for (var i = 0; i < pending.length; i++) {
      final body = pending[i], previous = _functions.length;
      for (final member in [
        for (final target in body.virtualMembers)
          (receiver: target.owner!, selector: target.selector),
        ...body.implicitMembers,
      ]) {
        if (member.receiver.nonNullable case final ClassType owner
            when type.asInstanceOf(owner.declaration) == null) {
          continue;
        }
        _member(member.selector);
      }
      pending.addAll(functions.skip(previous));
    }
  }

  IrFunction? _member(MemberSelector selector) {
    if (selector.privateLibrary != null && selector.privateLibrary != _uri) {
      return null;
    }
    final key = (selector.kind, selector.name);
    if (_functions[key] case final known?) return known;
    final build = switch (key) {
      (FunctionKind.getter, 'length') => _length,
      (FunctionKind.setter, 'length') => _resize,
      (FunctionKind.method, '[]') => () => _access(false),
      (FunctionKind.method, '[]=') => () => _access(true),
      (FunctionKind.method, 'add') => _add,
      (FunctionKind.method, 'addAll') => () => _append(true),
      (FunctionKind.method, 'elementAt') => _elementAt,
      (FunctionKind.getter, 'iterator') => _iterator,
      _ => null,
    };
    return build == null ? null : _functions.putIfAbsent(key, build);
  }

  IrFunction _initialize() {
    final init = Block(initializer.parameterTypes);
    for (final (i, field) in [length, data, mutability].indexed) {
      init.emit(
        StoreField(field, init.parameters.first, init.parameters[i + 1]),
      );
    }
    init.finish(const Return());
    return IrFunction(initializer, [init]);
  }

  IrFunction _length() {
    final getter = _target('length', .integer, [], .getter);
    final entry = Block(getter.parameterTypes);
    entry.finish(
      Return(entry.emit(LoadField(length, entry.parameters.single))),
    );
    return IrFunction(getter, [entry]);
  }

  IrFunction _elementAt() {
    final read = _member((kind: .method, name: '[]', privateLibrary: null))!;
    final elementAt = _target('elementAt', element, [.integer], .method);
    final at = Block(elementAt.parameterTypes);
    at.finish(Return(at.emit(DirectCall(read.target, at.parameters))));
    return IrFunction(elementAt, [at]);
  }

  IrFunction _iterator() {
    final target = _target(
      'iterator',
      CoreTypes.iteratorOf(element),
      [],
      .getter,
    );
    final entry = Block(target.parameterTypes);
    final constructor =
        iteratorConstructor?.target ??
        (throw UnsupportedError(
          'List iteration requires the SDK ListIterator constructor.',
        ));
    entry.finish(
      Return(
        entry.emit(
          Construct(
            constructor,
            entry.parameters,
            instantiatedType: constructor.owner!.instantiate([element]),
          ),
        ),
      ),
    );
    return IrFunction(target, [entry]);
  }

  late final _newBuffer = FunctionTarget(_uri, 'buffer', buffer, [.integer]);
  IrFunction _bufferBody() {
    _allocation =
        allocate?.call(buffer) ??
        (throw UnsupportedError('List storage requires managed allocation.'));
    final entry = Block(_newBuffer.parameterTypes),
        valid = Block(),
        overflow = Block();
    final count = entry.parameters.single;
    // The allocator reports OOM before an oversized element count can wrap to bytes.
    const maximum = (0x1ffffffffffffff8 - ObjectLayout.fieldsOffset) ~/ 8;
    entry.finish(
      Branch(
        _op(entry, .greaterThan, count, _int(maximum)),
        Jump(overflow),
        Jump(valid),
      ),
    );
    overflow.finish(
      Return(overflow.emit(DirectCall(_allocation!, [_int(-1)]))),
    );
    valid.finish(
      Return(
        valid.emit(
          DirectCall(_allocation!, [_op(valid, .multiply, count, _int(8))]),
        ),
      ),
    );
    return IrFunction(_newBuffer, [entry, overflow, valid]);
  }

  IrFunction _factory(bool fill) {
    _define(initializer, _initialize);
    _define(_newBuffer, _bufferBody);
    final target = fill ? filled : empty;
    final entry = Block(target.parameterTypes);
    final count = fill ? entry.parameters[0] : _int(0);
    final blocks = [entry];
    var current = entry;
    if (fill) {
      final valid = Block(), invalid = Block();
      blocks.addAll([valid, invalid]);
      entry.finish(
        Branch(
          _op(entry, .lessThan, count, _int(0)),
          Jump(invalid),
          Jump(valid),
        ),
      );
      invalid.finish(
        Throw(
          _error(invalid, rangeError, [
            count,
            _int(0),
            const Constant.nullValue(),
          ]),
        ),
      );
      current = valid;
    }
    final create = Block([.integer]);
    blocks.add(create);
    current.finish(
      Branch(
        entry.parameters.last,
        Jump(create, [_int(ListMutability.growable.index)]),
        Jump(create, [_int(ListMutability.fixed.index)]),
      ),
    );
    final storage = create.emit(DirectCall(_newBuffer, [count]));
    final list = create.emit(
      Construct(initializer, [count, storage, create.parameters.single]),
    );
    if (fill) {
      final loop = Block([.integer]), write = Block(), done = Block();
      blocks.addAll([loop, write, done]);
      create.finish(Jump(loop, [_int(0)]));
      final index = loop.parameters.single;
      loop.finish(
        Branch(_op(loop, .lessThan, index, count), Jump(write), Jump(done)),
      );
      _set(write, storage, index, entry.parameters[1]);
      write.finish(Jump(loop, [_op(write, .add, index, _int(1))]));
      done.finish(Return(list));
    } else {
      create.finish(Return(list));
    }
    return IrFunction(target, blocks);
  }

  IrFunction _access(bool write) {
    final target = _target(write ? '[]=' : '[]', write ? .voidType : element, [
      .integer,
      if (write) element,
    ], .method);
    final entry = Block(target.parameterTypes),
        upper = Block(),
        access = Block(),
        failed = Block();
    final list = entry.parameters[0], index = entry.parameters[1];
    final blocks = [entry, upper, access, failed];
    final check = write ? _modifiable(entry, list, blocks) : entry;
    final count = check.emit(LoadField(length, list));
    check.finish(
      Branch(_op(check, .lessThan, index, _int(0)), Jump(failed), Jump(upper)),
    );
    upper.finish(
      Branch(_op(upper, .lessThan, index, count), Jump(access), Jump(failed)),
    );
    final storage = access.emit(LoadField(data, list));
    if (write) {
      _set(access, storage, index, entry.parameters[2]);
      access.finish(const Return());
    } else {
      access.finish(
        Return(access.emit(TypeCast(_get(access, storage, index), element))),
      );
    }
    failed.finish(
      Throw(
        _error(
          failed,
          indexError,
          [index, count],
          {'indexable': list, 'name': const Constant.string('index')},
        ),
      ),
    );
    return IrFunction(target, blocks);
  }

  Block _modifiable(
    Block entry,
    Value list,
    List<Block> blocks, {
    bool resizing = false,
  }) {
    final valid = Block(), failed = Block();
    blocks.addAll([valid, failed]);
    entry.finish(
      Branch(
        _op(
          entry,
          .greaterOrEqual,
          entry.emit(LoadField(mutability, list)),
          _int(
            (resizing ? ListMutability.growable : ListMutability.fixed).index,
          ),
        ),
        Jump(valid),
        Jump(failed),
      ),
    );
    failed.finish(
      Throw(
        _error(failed, unsupportedError, [
          Constant.string(
            resizing
                ? 'Cannot change the length of a fixed-length list'
                : 'Cannot modify an unmodifiable list',
          ),
        ]),
      ),
    );
    return valid;
  }

  IrFunction _reserve() {
    _define(_newBuffer, _bufferBody);
    final entry = Block(reserve.parameterTypes),
        grow = Block(),
        smaller = Block(),
        larger = Block();
    final allocate = Block([.integer]),
        loop = Block([.integer]),
        copy = Block(),
        done = Block();
    final [list, required] = entry.parameters;
    final storage = entry.emit(LoadField(data, list));
    final bytes = entry.emit(
      LoadObjectData(storage, _int(ObjectLayout.sizeOffset), .new(Uint64)),
    );
    final capacity = _op(
      entry,
      .shiftRight,
      _op(entry, .subtract, bytes, _int(ObjectLayout.fieldsOffset)),
      _int(3),
    );
    entry.finish(
      Branch(
        _op(entry, .greaterThan, required, capacity),
        Jump(grow),
        Jump(done),
      ),
    );
    final doubled = _op(
      grow,
      .add,
      _op(grow, .multiply, capacity, _int(2)),
      _int(4),
    );
    grow.finish(
      Branch(
        _op(grow, .lessThan, doubled, required),
        Jump(smaller),
        Jump(larger),
      ),
    );
    smaller.finish(Jump(allocate, [required]));
    larger.finish(Jump(allocate, [doubled]));
    final next = allocate.emit(DirectCall(_newBuffer, allocate.parameters));
    final count = allocate.emit(LoadField(length, list));
    allocate.finish(Jump(loop, [_int(0)]));
    final index = loop.parameters.single;
    final replace = Block();
    loop.finish(
      Branch(_op(loop, .lessThan, index, count), Jump(copy), Jump(replace)),
    );
    _set(copy, next, index, _get(copy, storage, index));
    copy.finish(Jump(loop, [_op(copy, .add, index, _int(1))]));
    replace.emit(StoreField(data, list, next));
    replace.finish(Jump(done));
    done.finish(const Return());
    return IrFunction(reserve, [
      entry,
      grow,
      smaller,
      larger,
      allocate,
      loop,
      copy,
      replace,
      done,
    ]);
  }

  IrFunction _add() {
    _define(reserve, _reserve);
    final target = _target('add', .voidType, [element], .method);
    final entry = Block(target.parameterTypes), blocks = [entry];
    final [list, value] = entry.parameters;
    final write = _modifiable(entry, list, blocks, resizing: true);
    final count = write.emit(LoadField(length, list));
    final next = _op(write, .add, count, _int(1));
    write.emit(DirectCall(reserve, [list, next]));
    _set(write, write.emit(LoadField(data, list)), count, value);
    write.emit(StoreField(length, list, next));
    write.finish(const Return());
    return IrFunction(target, blocks);
  }

  IrFunction _append(bool method) {
    final elementType = method ? element : _spreadElement;
    final target = method
        ? _target('addAll', .voidType, [CoreTypes.iterableOf(element)], .method)
        : _spread;
    final entry = Block(target.parameterTypes), blocks = [entry];
    final [list, source] = entry.parameters;
    final start = method
        ? _modifiable(entry, list, blocks, resizing: true)
        : entry;
    final done = Block(),
        loop = Block([if (method) ValueType.integer]),
        write = Block();
    blocks.addAll([loop, write, done]);
    Block current = start;
    Block? failed;
    Value? count;
    if (method) {
      count = start.emit(LoadField(length, list));
      final same = Block(), iterate = Block();
      failed = Block();
      blocks.addAll([same, iterate, failed]);
      start.finish(
        Branch(start.emit(Identical(list, source)), Jump(same), Jump(iterate)),
      );
      same.finish(
        Branch(same.emit(Equals(count, _int(0))), Jump(done), Jump(failed)),
      );
      failed.finish(Throw(_error(failed, concurrentModificationError, [list])));
      current = iterate;
    }
    final iterator = current.emit(GetIterator(source));
    current.finish(Jump(loop, [?count]));
    loop.finish(
      Branch(loop.emit(IteratorMoveNext(iterator)), Jump(write), Jump(done)),
    );
    final value = write.emit(
      TypeCast(write.emit(IteratorCurrent(iterator)), elementType),
    );
    current = write;
    if (method) {
      final append = Block();
      blocks.add(append);
      write.finish(
        Branch(
          write.emit(
            Equals(write.emit(LoadField(length, list)), loop.parameters.single),
          ),
          Jump(append),
          Jump(failed!),
        ),
      );
      current = append;
    }
    current.emit(CollectionAdd(list, value));
    current.finish(
      Jump(loop, [
        if (method) _op(current, .add, loop.parameters.single, _int(1)),
      ]),
    );
    done.finish(const Return());
    return IrFunction(target, blocks);
  }

  IrFunction _resize() {
    _define(reserve, _reserve);
    final target = _target('length', .voidType, [.integer], .setter);
    final entry = Block(target.parameterTypes), blocks = [entry];
    final [list, count] = entry.parameters;
    final check = _modifiable(entry, list, blocks, resizing: true),
        valid = Block(),
        failed = Block();
    check.finish(
      Branch(_op(check, .lessThan, count, _int(0)), Jump(failed), Jump(valid)),
    );
    failed.finish(
      Throw(
        _error(failed, rangeError, [
          count,
          _int(0),
          const Constant.nullValue(),
        ]),
      ),
    );
    final old = valid.emit(LoadField(length, list));
    final grow = Block(),
        shrink = Block(),
        loop = Block([.integer]),
        clear = Block(),
        done = Block();
    blocks.addAll([valid, failed, grow, shrink, loop, clear, done]);
    valid.finish(
      Branch(_op(valid, .greaterThan, count, old), Jump(grow), Jump(shrink)),
    );
    grow.emit(TypeCast(const Constant.nullValue(), element));
    grow.emit(DirectCall(reserve, [list, count]));
    grow.finish(Jump(done));
    final storage = shrink.emit(LoadField(data, list));
    shrink.finish(Jump(loop, [count]));
    final index = loop.parameters.single;
    loop.finish(
      Branch(_op(loop, .lessThan, index, old), Jump(clear), Jump(done)),
    );
    _set(clear, storage, index, const Constant.nullValue());
    clear.finish(Jump(loop, [_op(clear, .add, index, _int(1))]));
    done.emit(StoreField(length, list, count));
    done.finish(const Return());
    return IrFunction(target, blocks);
  }
}
