import 'dart:ffi' show Uint16;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

/// Owns inline UTF-16 storage, construction and value operations.
final class StringStorage({
  IrClass? source,
  final IrCallable? indexError,
  final IrCallable? rangeError,
  final IrCallable? argumentError,
  final FunctionTarget Function(ClassType)? allocate,
}) {
  static const dataOffset = ObjectLayout.fieldsOffset + ObjectLayout.alignment;
  static final _unit = NativeScalarType(Uint16);
  final length = InstanceField(ValueType.string, 'length', .integer);
  late final IrClass declaration;
  this {
    declaration = IrClass(
      ValueType.string,
      [length],
      members: source?.members.values ?? const [],
      implementations: source?.implementations.values ?? const [],
      constructors: source?.constructors.values ?? const [],
      unsupportedForwarders: source?.unsupportedForwarders ?? const {},
    );
  }
  IrFunction? _read, _fromCode, _fromCodes, _concat, _equal, _hash;
  FunctionTarget? _allocation;

  Iterable<IrFunction> get functions => [
    ?_read,
    ?_fromCode,
    ?_fromCodes,
    ?_concat,
    ?_equal,
    ?_hash,
  ];
  Iterable<FunctionTarget> get allocations => [?_allocation];

  FunctionTarget? callFor(Instruction operation) => switch (operation) {
    StringCodeUnitAt() => (_read ??= _codeUnitAt()).target,
    StringFromCharCode() => (_fromCode ??= _fromCharCode()).target,
    StringFromCharCodes() => (_fromCodes ??= _fromCharCodes()).target,
    StringConcat() => (_concat ??= _concatenate()).target,
    _ => null,
  };

  FunctionTarget get equality => (_equal ??= _equals()).target;
  FunctionTarget get hash => (_hash ??= _hashCode()).target;

  FunctionTarget _target(
    String name,
    ValueType result,
    List<ValueType> parameters,
  ) => FunctionTarget(Uri.parse('dartc:strings'), name, result, parameters);
  Constant _int(int value) => Constant.integer(value);
  Value _op(Block block, IntOperator op, Value left, Value right) =>
      block.emit(IntBinary(op, left, right));
  Value _offset(Block block, Value index) =>
      _op(block, .add, _int(dataOffset), _op(block, .multiply, index, _int(2)));
  Value _get(Block block, Value string, Value index) =>
      block.emit(LoadObjectData(string, _offset(block, index), _unit));
  void _set(Block block, Value string, Value index, Value value) =>
      block.emit(StoreObjectData(string, _offset(block, index), _unit, value));

  Value _create(Block block, Value count) {
    final factory = _allocation ??=
        allocate?.call(ValueType.string) ??
        (throw UnsupportedError(
          'String construction requires managed allocation.',
        ));
    final string = block.emit(
      DirectCall(factory, [_op(block, .multiply, count, _int(2))]),
    );
    block.emit(StoreField(length, string, count));
    return string;
  }

  Value _error(
    Block block,
    IrCallable? constructor,
    List<Value> arguments, [
    Map<String, Value> named = const {},
  ]) {
    if (constructor == null) {
      throw UnsupportedError(
        'String bounds require the SDK error constructor.',
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

  IrFunction _codeUnitAt() {
    final target = _target('codeUnitAt', .integer, [.string, .integer]);
    final entry = Block(target.parameterTypes),
        upper = Block(),
        read = Block(),
        failed = Block();
    final [string, index] = entry.parameters;
    final count = entry.emit(LoadField(length, string));
    entry.finish(
      Branch(_op(entry, .lessThan, index, _int(0)), Jump(failed), Jump(upper)),
    );
    upper.finish(
      Branch(_op(upper, .lessThan, index, count), Jump(read), Jump(failed)),
    );
    read.finish(Return(_get(read, string, index)));
    failed.finish(
      Throw(
        _error(
          failed,
          indexError,
          [index, count],
          {'indexable': string, 'name': const Constant.string('index')},
        ),
      ),
    );
    return IrFunction(target, [entry, upper, read, failed]);
  }

  IrFunction _fromCharCode() {
    final target = _target('fromCharCode', .string, [.integer]);
    final entry = Block(target.parameterTypes),
        upper = Block(),
        valid = Block(),
        single = Block(),
        pair = Block(),
        failed = Block();
    final code = entry.parameters.single;
    entry.finish(
      Branch(_op(entry, .lessThan, code, _int(0)), Jump(failed), Jump(upper)),
    );
    upper.finish(
      Branch(
        _op(upper, .greaterThan, code, _int(0x10ffff)),
        Jump(failed),
        Jump(valid),
      ),
    );
    valid.finish(
      Branch(
        _op(valid, .lessOrEqual, code, _int(0xffff)),
        Jump(single),
        Jump(pair),
      ),
    );
    final one = _create(single, _int(1));
    _set(single, one, _int(0), code);
    single.finish(Return(one));
    final two = _create(pair, _int(2));
    _set(
      pair,
      two,
      _int(0),
      _op(
        pair,
        .bitOr,
        _int(0xd800),
        _op(
          pair,
          .shiftRight,
          _op(pair, .subtract, code, _int(0x10000)),
          _int(10),
        ),
      ),
    );
    _set(
      pair,
      two,
      _int(1),
      _op(pair, .bitOr, _int(0xdc00), _op(pair, .bitAnd, code, _int(0x3ff))),
    );
    pair.finish(Return(two));
    failed.finish(
      Throw(_error(failed, rangeError, [code, _int(0), _int(0x10ffff)])),
    );
    return IrFunction(target, [entry, upper, valid, single, pair, failed]);
  }

  IrFunction _fromCharCodes() {
    final target = _target('fromCharCodes', .string, [
      CoreTypes.iterableOf(.integer),
      .integer,
      ValueType.integer.nullable,
    ]);
    final entry = Block(target.parameterTypes),
        checkEnd = Block(),
        bound = Block(),
        validEnd = Block(),
        badStart = Block(),
        badEnd = Block(),
        empty = Block(),
        ready = Block([.integer]),
        skip = Block([.integer]),
        skipNext = Block(),
        skipped = Block(),
        loop = Block([.integer, .integer]),
        move = Block(),
        read = Block(),
        single = Block(),
        pair = Block(),
        validate = Block([.integer]),
        upper = Block(),
        badCode = Block(),
        create = Block(),
        allocate = Block(),
        copy = Block([.integer]),
        write = Block(),
        done = Block();
    final [codes, start, end] = entry.parameters;
    entry.finish(
      Branch(
        _op(entry, .lessThan, start, _int(0)),
        Jump(badStart),
        Jump(checkEnd),
      ),
    );
    badStart.finish(
      Throw(
        _error(badStart, rangeError, [
          start,
          _int(0),
          const Constant.nullValue(),
          const Constant.string('start'),
        ]),
      ),
    );
    checkEnd.finish(
      Branch(
        checkEnd.emit(Equals(end, const Constant.nullValue())),
        Jump(ready, [_int(-1)]),
        Jump(bound),
      ),
    );
    final limit = bound.emit(TypeCast(end, .integer));
    bound.finish(
      Branch(_op(bound, .lessThan, limit, start), Jump(badEnd), Jump(validEnd)),
    );
    badEnd.finish(
      Throw(
        _error(badEnd, rangeError, [
          limit,
          start,
          const Constant.nullValue(),
          const Constant.string('end'),
        ]),
      ),
    );
    validEnd.finish(
      Branch(
        validEnd.emit(Equals(limit, start)),
        Jump(empty),
        Jump(ready, [_op(validEnd, .subtract, limit, start)]),
      ),
    );
    empty.finish(const Return(Constant.string('')));

    final units = ready.emit(NewCollection(CoreTypes.listOf(.integer)));
    final iterator = ready.emit(GetIterator(codes));
    ready.finish(Jump(skip, [start]));
    final remaining = skip.parameters.single;
    skip.finish(
      Branch(
        skip.emit(Equals(remaining, _int(0))),
        Jump(loop, [ready.parameters.single, _int(0)]),
        Jump(skipNext),
      ),
    );
    skipNext.finish(
      Branch(
        skipNext.emit(IteratorMoveNext(iterator)),
        Jump(skipped),
        Jump(empty),
      ),
    );
    skipped.finish(Jump(skip, [_op(skipped, .subtract, remaining, _int(1))]));
    final [take, bits] = loop.parameters;
    loop.finish(
      Branch(
        loop.emit(Equals(take, _int(0))),
        Jump(validate, [bits]),
        Jump(move),
      ),
    );
    move.finish(
      Branch(
        move.emit(IteratorMoveNext(iterator)),
        Jump(read),
        Jump(validate, [bits]),
      ),
    );
    final code = read.emit(
      TypeCast(read.emit(IteratorCurrent(iterator)), .integer),
    );
    read.finish(
      Branch(
        _op(read, .lessOrEqual, code, _int(0xffff)),
        Jump(single),
        Jump(pair),
      ),
    );
    single.emit(CollectionAdd(units, code));
    single.finish(
      Jump(loop, [
        _op(single, .subtract, take, _int(1)),
        _op(single, .bitOr, bits, code),
      ]),
    );
    final point = _op(pair, .subtract, code, _int(0x10000));
    pair.emit(
      CollectionAdd(
        units,
        _op(
          pair,
          .add,
          _int(0xd800),
          _op(pair, .unsignedShiftRight, point, _int(10)),
        ),
      ),
    );
    pair.emit(
      CollectionAdd(
        units,
        _op(pair, .add, _int(0xdc00), _op(pair, .bitAnd, point, _int(0x3ff))),
      ),
    );
    pair.finish(
      Jump(loop, [
        _op(pair, .subtract, take, _int(1)),
        _op(pair, .bitOr, bits, _op(pair, .bitOr, point, _int(0xd800))),
      ]),
    );

    // Validate after iteration so a later iterator exception is not hidden.
    final combined = validate.parameters.single;
    validate.finish(
      Branch(
        _op(validate, .lessThan, combined, _int(0)),
        Jump(badCode),
        Jump(upper),
      ),
    );
    upper.finish(
      Branch(
        _op(upper, .greaterThan, combined, _int(0xfffff)),
        Jump(badCode),
        Jump(create),
      ),
    );
    badCode.finish(
      Throw(
        _error(badCode, argumentError, [
          codes,
          const Constant.string('charCodes'),
        ]),
      ),
    );
    final count = create.emit(CollectionLength(units));
    create.finish(
      Branch(create.emit(Equals(count, _int(0))), Jump(empty), Jump(allocate)),
    );
    final string = _create(allocate, count);
    allocate.finish(Jump(copy, [_int(0)]));
    final index = copy.parameters.single;
    copy.finish(
      Branch(_op(copy, .lessThan, index, count), Jump(write), Jump(done)),
    );
    _set(write, string, index, write.emit(CollectionGet(units, index)));
    write.finish(Jump(copy, [_op(write, .add, index, _int(1))]));
    done.finish(Return(string));
    return IrFunction(target, [
      entry,
      checkEnd,
      bound,
      validEnd,
      badStart,
      badEnd,
      empty,
      ready,
      skip,
      skipNext,
      skipped,
      loop,
      move,
      read,
      single,
      pair,
      validate,
      upper,
      badCode,
      create,
      allocate,
      copy,
      write,
      done,
    ]);
  }

  IrFunction _concatenate() {
    final target = _target('concat', .string, [.string, .string]);
    final entry = Block(target.parameterTypes);
    final [left, right] = entry.parameters;
    final leftCount = entry.emit(LoadField(length, left));
    final rightCount = entry.emit(LoadField(length, right));
    final string = _create(entry, _op(entry, .add, leftCount, rightCount));
    final blocks = [entry];
    var current = entry;
    for (final (source, count, start) in [
      (left, leftCount, _int(0)),
      (right, rightCount, leftCount),
    ]) {
      final loop = Block([.integer]), copy = Block(), next = Block();
      blocks.addAll([loop, copy, next]);
      current.finish(Jump(loop, [_int(0)]));
      final index = loop.parameters.single;
      loop.finish(
        Branch(_op(loop, .lessThan, index, count), Jump(copy), Jump(next)),
      );
      _set(
        copy,
        string,
        _op(copy, .add, start, index),
        _get(copy, source, index),
      );
      copy.finish(Jump(loop, [_op(copy, .add, index, _int(1))]));
      current = next;
    }
    current.finish(Return(string));
    return IrFunction(target, blocks);
  }

  IrFunction _equals() {
    final target = _target('equals', .boolean, [
      .string,
      ValueType.object.nullable,
    ]);
    final entry = Block(target.parameterTypes),
        lengths = Block([.string]),
        loop = Block([.integer]),
        read = Block(),
        next = Block(),
        yes = Block(),
        no = Block();
    final [left, right] = entry.parameters;
    final test = entry.emit(TypeTest(right, .string));
    entry.finish(
      Branch(test, Jump(lengths, [test.refinement(true)!]), Jump(no)),
    );
    final other = lengths.parameters.single;
    final count = lengths.emit(LoadField(length, left));
    final sameLength = lengths.emit(
      Equals(count, lengths.emit(LoadField(length, other))),
    );
    lengths.finish(Branch(sameLength, Jump(loop, [_int(0)]), Jump(no)));
    final index = loop.parameters.single;
    loop.finish(
      Branch(_op(loop, .lessThan, index, count), Jump(read), Jump(yes)),
    );
    read.finish(
      Branch(
        read.emit(Equals(_get(read, left, index), _get(read, other, index))),
        Jump(next),
        Jump(no),
      ),
    );
    next.finish(Jump(loop, [_op(next, .add, index, _int(1))]));
    yes.finish(const Return(Constant.boolean(true)));
    no.finish(const Return(Constant.boolean(false)));
    return IrFunction(target, [entry, lengths, loop, read, next, yes, no]);
  }

  IrFunction _hashCode() {
    final target = _target('hashCode', .integer, [.string]);
    final entry = Block(target.parameterTypes),
        loop = Block([.integer, .integer]),
        read = Block(),
        done = Block();
    final string = entry.parameters.single;
    final count = entry.emit(LoadField(length, string));
    entry.finish(Jump(loop, [_int(0), _int(0)]));
    final [index, hash] = loop.parameters;
    loop.finish(
      Branch(_op(loop, .lessThan, index, count), Jump(read), Jump(done)),
    );
    final combined = _op(
      read,
      .add,
      _op(read, .multiply, hash, _int(31)),
      _get(read, string, index),
    );
    read.finish(
      Jump(loop, [
        _op(read, .add, index, _int(1)),
        _op(read, .bitAnd, combined, _int(0x3fffffff)),
      ]),
    );
    done.finish(Return(hash));
    return IrFunction(target, [entry, loop, read, done]);
  }
}
