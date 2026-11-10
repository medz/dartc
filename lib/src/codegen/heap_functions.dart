import 'dart:ffi';

import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

/// Generates allocation and copying collection through ordinary typed IR.
final class HeapFunctions() {
  static final _uri = Uri.parse('dartc:heap');
  static final _wordPointer = FfiTypes.resolve(
    NativePointerType(NativeScalarType(Int64)),
  );

  static const start = 0,
      limit = 8,
      top = 16,
      spare = 24,
      copied = 32,
      maps = 40;
  static const contextBytes = 48;

  final map = _target('map', .integer, 1);
  final unmap = _target('unmap', .voidType, 2);
  final invalid = _target('invalid', .voidType, 0);
  final allocate = _target('allocate', .integer, 4);
  final release = _target('release', .voidType, 1);
  final _copy = _target('copy', .integer, 2);
  final _collect = _target('collect', .voidType, 5);

  late final List<IrFunction> functions = [
    _copyBody(),
    _collectBody(),
    _allocateBody(),
    _releaseBody(),
  ];

  static FunctionTarget _target(
    String name,
    ValueType result,
    int parameters,
  ) => FunctionTarget(
    _uri,
    name,
    result,
    List.filled(parameters, ValueType.integer),
  );

  IrFunction _copyBody() {
    final entry = Block(_copy.parameterTypes),
        range = Block(),
        header = Block();
    final unchanged = Block(), forwarded = Block(), fresh = Block();
    final loop = Block([.integer]), word = Block(), done = Block();
    final [context, reference] = entry.parameters;
    _branch(
      entry,
      .lessThan,
      reference,
      _load(entry, context, start),
      unchanged,
      range,
    );
    _branch(
      range,
      .greaterOrEqual,
      reference,
      _load(range, context, top),
      unchanged,
      header,
    );
    unchanged.finish(Return(reference));
    final descriptor = _load(header, reference);
    _equal(
      header,
      _op(header, .bitAnd, descriptor, _int(1)),
      _int(0),
      fresh,
      forwarded,
    );
    forwarded.finish(Return(_op(forwarded, .bitAnd, descriptor, _int(-2))));
    final size = _load(fresh, descriptor),
        destination = _load(fresh, context, copied);
    _store(fresh, context, _op(fresh, .add, destination, size), copied);
    fresh.finish(Jump(loop, [_int(0)]));
    final offset = loop.parameters.single;
    _branch(loop, .lessThan, offset, size, word, done);
    _store(
      word,
      _op(word, .add, destination, offset),
      _load(word, _op(word, .add, reference, offset)),
    );
    word.finish(Jump(loop, [_op(word, .add, offset, _int(8))]));
    _store(done, reference, _op(done, .bitOr, destination, _int(1)));
    done.finish(Return(destination));
    return IrFunction(_copy, [
      entry,
      range,
      header,
      unchanged,
      forwarded,
      fresh,
      loop,
      word,
      done,
    ]);
  }

  IrFunction _collectBody() {
    final entry = Block(_collect.parameterTypes);
    final frame = Block([.integer, .integer]),
        search = Block([.integer, .integer]);
    final candidate = Block(),
        next = Block(),
        found = Block(),
        invalid = Block();
    final roots = Block([.integer]),
        root = Block(),
        linked = Block(),
        caller = Block();
    final scan = Block([.integer]),
        object = Block(),
        fields = Block([.integer]);
    final field = Block(), nextObject = Block(), done = Block();
    final [context, destination, capacity, initialSp, initialPc] =
        entry.parameters;
    _store(entry, context, destination, copied);
    entry.finish(Jump(frame, [initialSp, initialPc]));
    final [sp, pc] = frame.parameters;
    final table = _load(frame, context, maps);
    frame.finish(
      Jump(search, [_op(frame, .add, table, _int(8)), _load(frame, table)]),
    );
    final [record, remaining] = search.parameters;
    _equal(search, remaining, _int(0), invalid, candidate);
    _equal(candidate, _load(candidate, record), pc, found, next);
    final count = _load(next, record, 24);
    next.finish(
      Jump(search, [
        _op(
          next,
          .add,
          _op(next, .add, record, _int(32)),
          _op(next, .multiply, count, _int(8)),
        ),
        _op(next, .subtract, remaining, _int(1)),
      ]),
    );
    invalid.emit(DirectCall(this.invalid, []));
    invalid.finish(const Return());
    final callerOffset = _load(found, record, 8),
        returnOffset = _load(found, record, 16);
    final rootCount = _load(found, record, 24);
    found.finish(Jump(roots, [_int(0)]));
    final index = roots.parameters.single;
    _branch(roots, .lessThan, index, rootCount, root, linked);
    final slot = _op(
      root,
      .add,
      sp,
      _load(
        root,
        _op(root, .add, record, _op(root, .multiply, index, _int(8))),
        32,
      ),
    );
    _store(
      root,
      slot,
      root.emit(DirectCall(_copy, [context, _load(root, slot)])),
    );
    root.finish(Jump(roots, [_op(root, .add, index, _int(1))]));
    linked.finish(
      Branch(
        linked.emit(Equals(callerOffset, _int(0))),
        Jump(scan, [destination]),
        Jump(caller),
      ),
    );
    caller.finish(
      Jump(frame, [
        _op(caller, .add, sp, callerOffset),
        _load(caller, _op(caller, .add, sp, returnOffset)),
      ]),
    );
    final address = scan.parameters.single;
    _branch(
      scan,
      .lessThan,
      address,
      _load(scan, context, copied),
      object,
      done,
    );
    final descriptor = _load(object, address),
        references = _load(object, descriptor, 8);
    object.finish(Jump(fields, [_int(0)]));
    final i = fields.parameters.single;
    _branch(fields, .lessThan, i, references, field, nextObject);
    final location = _op(
      field,
      .add,
      address,
      _load(
        field,
        _op(field, .add, descriptor, _op(field, .multiply, i, _int(8))),
        16,
      ),
    );
    _store(
      field,
      location,
      field.emit(DirectCall(_copy, [context, _load(field, location)])),
    );
    field.finish(Jump(fields, [_op(field, .add, i, _int(1))]));
    nextObject.finish(
      Jump(scan, [
        _op(nextObject, .add, address, _load(nextObject, descriptor)),
      ]),
    );
    _store(done, context, destination, start);
    _store(done, context, _op(done, .add, destination, capacity), limit);
    _store(done, context, _load(done, context, copied), top);
    done.finish(const Return());
    return IrFunction(_collect, [
      entry,
      frame,
      search,
      candidate,
      next,
      found,
      invalid,
      roots,
      root,
      linked,
      caller,
      scan,
      object,
      fields,
      field,
      nextObject,
      done,
    ]);
  }

  IrFunction _allocateBody() {
    final entry = Block(allocate.parameterTypes),
        available = Block(),
        collect = Block();
    final retry = Block(), grow = Block(), sizeLoop = Block([.integer]);
    final enlarge = Block(),
        doubleSize = Block(),
        first = Block(),
        second = Block();
    final discard = Block(),
        migrate = Block(),
        old = Block(),
        ready = Block(),
        failed = Block();
    final fill = Block([.integer]), zero = Block(), done = Block();
    final [context, descriptor, sp, pc] = entry.parameters;
    final size = _load(entry, descriptor);
    _equal(entry, _load(entry, context, start), _int(0), grow, available);
    _branch(
      available,
      .lessOrEqual,
      _op(available, .add, _load(available, context, top), size),
      _load(available, context, limit),
      ready,
      collect,
    );
    final previous = _load(collect, context, start);
    collect.emit(
      DirectCall(_collect, [
        context,
        _load(collect, context, spare),
        _op(collect, .subtract, _load(collect, context, limit), previous),
        sp,
        pc,
      ]),
    );
    _store(collect, context, previous, spare);
    collect.finish(Jump(retry));
    _branch(
      retry,
      .lessOrEqual,
      _op(retry, .add, _load(retry, context, top), size),
      _load(retry, context, limit),
      ready,
      grow,
    );
    final oldStart = _load(grow, context, start),
        oldSpare = _load(grow, context, spare);
    final oldCapacity = _op(
      grow,
      .subtract,
      _load(grow, context, limit),
      oldStart,
    );
    final needed = _op(
      grow,
      .add,
      _op(grow, .subtract, _load(grow, context, top), oldStart),
      size,
    );
    grow.finish(
      Branch(
        grow.emit(Equals(oldCapacity, _int(0))),
        Jump(sizeLoop, [_int(65536)]),
        Jump(sizeLoop, [oldCapacity]),
      ),
    );
    final capacity = sizeLoop.parameters.single;
    _branch(sizeLoop, .lessThan, capacity, needed, enlarge, first);
    _branch(
      enlarge,
      .greaterOrEqual,
      capacity,
      _int(0x2000000000000000),
      failed,
      doubleSize,
    );
    doubleSize.finish(
      Jump(sizeLoop, [_op(doubleSize, .multiply, capacity, _int(2))]),
    );
    final from = first.emit(DirectCall(map, [capacity]));
    _equal(first, from, _int(0), failed, second);
    final to = second.emit(DirectCall(map, [capacity]));
    _equal(second, to, _int(0), discard, migrate);
    discard.emit(DirectCall(unmap, [from, capacity]));
    discard.finish(Jump(failed));
    migrate.emit(DirectCall(_collect, [context, from, capacity, sp, pc]));
    _store(migrate, context, to, spare);
    _equal(migrate, oldStart, _int(0), ready, old);
    old.emit(DirectCall(unmap, [oldStart, oldCapacity]));
    old.emit(DirectCall(unmap, [oldSpare, oldCapacity]));
    old.finish(Jump(ready));
    final address = _load(ready, context, top);
    _store(ready, context, _op(ready, .add, address, size), top);
    ready.finish(Jump(fill, [_int(0)]));
    final offset = fill.parameters.single;
    _branch(fill, .lessThan, offset, size, zero, done);
    _store(zero, _op(zero, .add, address, offset), _int(0));
    zero.finish(Jump(fill, [_op(zero, .add, offset, _int(8))]));
    _store(done, address, descriptor);
    done.finish(Return(address));
    failed.finish(Return(_int(0)));
    return IrFunction(allocate, [
      entry,
      available,
      collect,
      retry,
      grow,
      sizeLoop,
      enlarge,
      doubleSize,
      first,
      second,
      discard,
      migrate,
      old,
      ready,
      failed,
      fill,
      zero,
      done,
    ]);
  }

  IrFunction _releaseBody() {
    final entry = Block(release.parameterTypes), free = Block(), done = Block();
    final context = entry.parameters.single,
        address = _load(entry, context, start);
    _equal(entry, address, _int(0), done, free);
    final capacity = _op(free, .subtract, _load(free, context, limit), address);
    free.emit(DirectCall(unmap, [address, capacity]));
    free.emit(DirectCall(unmap, [_load(free, context, spare), capacity]));
    free.finish(Jump(done));
    done.finish(const Return());
    return IrFunction(release, [entry, free, done]);
  }

  static Constant _int(int value) => Constant.integer(value);
  static Value _op(Block block, IntOperator op, Value a, Value b) =>
      block.emit(IntBinary(op, a, b));
  static Value _load(Block block, Value address, [int offset = 0]) =>
      block.emit(
        LoadNative(
          block.emit(
            PointerFromAddress(
              offset == 0 ? address : _op(block, .add, address, _int(offset)),
              _wordPointer,
            ),
          ),
        ),
      );
  static void _store(
    Block block,
    Value address,
    Value value, [
    int offset = 0,
  ]) => block.emit(
    StoreNative(
      block.emit(
        PointerFromAddress(
          offset == 0 ? address : _op(block, .add, address, _int(offset)),
          _wordPointer,
        ),
      ),
      value,
    ),
  );
  static void _branch(
    Block block,
    IntOperator op,
    Value a,
    Value b,
    Block yes,
    Block no,
  ) => block.finish(Branch(_op(block, op, a, b), Jump(yes), Jump(no)));

  static void _equal(Block block, Value a, Value b, Block yes, Block no) =>
      block.finish(Branch(block.emit(Equals(a, b)), Jump(yes), Jump(no)));
}
