import 'dart:ffi';

import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'frame_lookup.dart';

/// Generates allocation and copying collection through ordinary typed IR.
final class HeapFunctions(final FrameLookup frames) {
  static final _uri = Uri.parse('dartc:heap');
  static const start = 0,
      limit = 8,
      top = 16,
      spare = 24,
      copied = 32,
      maps = 40,
      globalRoots = 48,
      active = 56,
      identityHash = 64;
  static const contextBytes = 72;
  static const previousEntry = 0, suspendedSp = 8, suspendedPc = 16;
  static const entryBytes = 24;

  final map = _target('map', .integer, 1);
  final unmap = _target('unmap', .voidType, 2);
  final invalid = _target('invalid', .never, 0);
  final allocate = _target('allocate', .integer, 5);
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
    final size = _load(fresh, reference, ObjectLayout.sizeOffset),
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
    final holder = Block(), holderFields = Block([.integer]);
    final holderField = Block(), currentFrame = Block();
    final frame = Block([.integer, .integer, .integer]);
    final found = Block(), invalid = Block();
    final roots = Block([.integer]),
        root = Block(),
        linked = Block(),
        caller = Block();
    final segmentEnd = Block(), previousSegment = Block();
    final parked = Block(), parkedPc = Block(), resume = Block();
    final scan = Block([.integer]),
        object = Block(),
        fields = Block([.integer]);
    final field = Block(), payload = Block(), elements = Block([.integer]);
    final element = Block(), nextObject = Block(), done = Block();
    final [context, destination, capacity, initialSp, initialPc] =
        entry.parameters;
    _store(entry, context, destination, copied);
    final rootHolder = _load(entry, context, globalRoots);
    _equal(entry, rootHolder, _int(0), currentFrame, holder);
    // The stable holder is outside from-space, so _copy cannot trace it.
    final holderDescriptor = _load(holder, rootHolder),
        holderReferences = _load(holder, holderDescriptor, 8);
    holder.finish(Jump(holderFields, [_int(0)]));
    final holderIndex = holderFields.parameters.single;
    _branch(
      holderFields,
      .lessThan,
      holderIndex,
      holderReferences,
      holderField,
      currentFrame,
    );
    final holderSlot = _op(
      holderField,
      .add,
      rootHolder,
      _load(
        holderField,
        _op(
          holderField,
          .add,
          holderDescriptor,
          _op(holderField, .multiply, holderIndex, _int(8)),
        ),
        16,
      ),
    );
    _store(
      holderField,
      holderSlot,
      holderField.emit(
        DirectCall(_copy, [context, _load(holderField, holderSlot)]),
      ),
    );
    holderField.finish(
      Jump(holderFields, [_op(holderField, .add, holderIndex, _int(1))]),
    );
    currentFrame.finish(
      Jump(frame, [initialSp, initialPc, _load(currentFrame, context, active)]),
    );
    final [sp, pc, segment] = frame.parameters;
    final table = _load(frame, context, maps);
    final record = frame.emit(DirectCall(frames.target, [table, pc]));
    _equal(frame, record, _int(0), invalid, found);
    invalid.finish(Unreachable(invalid.emit(DirectCall(this.invalid, []))));
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
        Jump(segmentEnd),
        Jump(caller),
      ),
    );
    caller.finish(
      Jump(frame, [
        _op(caller, .add, sp, callerOffset),
        _load(caller, _op(caller, .add, sp, returnOffset)),
        segment,
      ]),
    );
    segmentEnd.finish(
      Branch(
        segmentEnd.emit(Equals(segment, _int(0))),
        Jump(scan, [destination]),
        Jump(previousSegment),
      ),
    );
    final previous = _load(previousSegment, segment, previousEntry);
    previousSegment.finish(
      Branch(
        previousSegment.emit(Equals(previous, _int(0))),
        Jump(scan, [destination]),
        Jump(parked),
      ),
    );
    final parentSp = _load(parked, previous, suspendedSp);
    _equal(parked, parentSp, _int(0), invalid, parkedPc);
    final parentPc = _load(parkedPc, previous, suspendedPc);
    _equal(parkedPc, parentPc, _int(0), invalid, resume);
    resume.finish(Jump(frame, [parentSp, parentPc, previous]));
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
    _branch(fields, .lessThan, i, references, field, payload);
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
    final payloadOffset = _load(
      payload,
      _op(
        payload,
        .add,
        descriptor,
        _op(payload, .multiply, references, _int(8)),
      ),
      24,
    );
    payload.finish(
      Branch(
        payload.emit(Equals(payloadOffset, _int(0))),
        Jump(nextObject),
        Jump(elements, [payloadOffset]),
      ),
    );
    final offset = elements.parameters.single;
    _branch(
      elements,
      .lessThan,
      offset,
      _load(elements, address, ObjectLayout.sizeOffset),
      element,
      nextObject,
    );
    final elementSlot = _op(element, .add, address, offset);
    _store(
      element,
      elementSlot,
      element.emit(DirectCall(_copy, [context, _load(element, elementSlot)])),
    );
    element.finish(Jump(elements, [_op(element, .add, offset, _int(8))]));
    nextObject.finish(
      Jump(scan, [
        _op(
          nextObject,
          .add,
          address,
          _load(nextObject, address, ObjectLayout.sizeOffset),
        ),
      ]),
    );
    _store(done, context, destination, start);
    _store(done, context, _op(done, .add, destination, capacity), limit);
    _store(done, context, _load(done, context, copied), top);
    done.finish(const Return());
    return IrFunction(_collect, [
      entry,
      holder,
      holderFields,
      holderField,
      currentFrame,
      frame,
      found,
      invalid,
      roots,
      root,
      linked,
      caller,
      segmentEnd,
      previousSegment,
      parked,
      parkedPc,
      resume,
      scan,
      object,
      fields,
      field,
      payload,
      elements,
      element,
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
    final [context, descriptor, sp, pc, payloadBytes] = entry.parameters;
    final sized = Block(), aligned = Block();
    _branch(entry, .lessThan, payloadBytes, _int(0), failed, sized);
    final prefix = _load(sized, descriptor);
    _branch(
      sized,
      .greaterThan,
      payloadBytes,
      _op(sized, .subtract, _int(0x1ffffffffffffff8), prefix),
      failed,
      aligned,
    );
    final size = _op(
      aligned,
      .bitAnd,
      _op(aligned, .add, _op(aligned, .add, prefix, payloadBytes), _int(7)),
      _int(-8),
    );
    _equal(aligned, _load(aligned, context, start), _int(0), grow, available);
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
    _store(done, address, size, ObjectLayout.sizeOffset);
    // An odd step visits every 30-bit hash without depending on object addresses.
    final hash = _op(
      done,
      .bitAnd,
      _op(done, .add, _load(done, context, identityHash), _int(0x9e3779b9)),
      _int(0x3fffffff),
    );
    _store(done, context, hash, identityHash);
    _store(done, address, hash, ObjectLayout.identityHashOffset);
    done.finish(Return(address));
    failed.finish(Return(_int(0)));
    return IrFunction(allocate, [
      entry,
      sized,
      aligned,
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
    for (final offset in [start, limit, top, spare, copied]) {
      _store(free, context, _int(0), offset);
    }
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
          offset == 0 ? address : _op(block, .add, address, _int(offset)),
          .new(Int64),
        ),
      );
  static void _store(
    Block block,
    Value address,
    Value value, [
    int offset = 0,
  ]) => block.emit(
    StoreNative(
      offset == 0 ? address : _op(block, .add, address, _int(offset)),
      .new(Int64),
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
