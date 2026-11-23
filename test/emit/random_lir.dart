import 'dart:math';

import 'package:dartc/lir.dart';

/// Reproducible random functions within the LIR that machine code supports.
///
/// Every function terminates: loops count down and calls only go to functions
/// generated earlier. Division and shifts keep their preconditions.
final class RandomLir(final int seed, {String prefix = ''}) {
  final String _prefix = '$prefix${seed}_';
  final Random _random = Random(seed);
  final _done = <LirFunction>[];
  final _pool = <LirValue>[];
  final _floats = <LirValue>[];
  final _objects = <LirValue>[];
  late LirBlock _block;
  late LirType _result;
  late List<LirBlock> _blocks;

  static const _interesting = [
    0,
    1,
    -1,
    2,
    63,
    64,
    0xffff,
    0x10000,
    0x7fffffffffffffff,
    -0x8000000000000000,
  ];

  /// An integer that is often an edge case.
  int integer() => switch (_random.nextInt(3)) {
    0 => _interesting[_random.nextInt(_interesting.length)],
    1 => _random.nextInt(200) - 100,
    _ => _random.nextInt(1 << 32) << 32 | _random.nextInt(1 << 32),
  };

  /// A double that is often an edge case.
  double float() => switch (_random.nextInt(3)) {
    0 => const [
      0.0,
      -0.0,
      1.0,
      -1.5,
      1e308,
      5e-324,
      double.infinity,
      double.negativeInfinity,
      double.nan,
      9007199254740993.0,
    ][_random.nextInt(10)],
    1 => _random.nextInt(200) / 8 - 12,
    _ => _random.nextDouble() * 1e10 - 5e9,
  };

  /// An argument of [type].
  Object argument(LirType type) => type == .f64 ? float() : integer();

  List<LirFunction> functions() {
    for (var i = 0; i < 5; i++) {
      _done.add(_function('$_prefix$i'));
    }
    return _done;
  }

  LirType _type() => switch (_random.nextInt(6)) {
    0 || 1 => .f64,
    2 => .ref,
    _ => .i64,
  };

  static const _objectBytes = 40;

  LirFunction _function(String name) {
    final arity = _random.nextInt(21);
    final signature = LirSignature([
      for (var i = 0; i < arity; i++) _type(),
    ], _random.nextInt(3) == 0 ? _type() : .i64);
    _result = signature.result!;
    _block = LirBlock(signature.parameters);
    _blocks = [_block];
    _pool.clear();
    _floats.clear();
    _objects.clear();
    _block.parameters.forEach(_keep);
    _keep(_block.add(ConstInt(integer())));
    _keep(_block.add(ConstFloat(float())));
    _allocate();
    _statements(8 + _random.nextInt(30), 2);
    // Reading every remaining value at the end keeps them all alive.
    var result = _pool.first;
    for (final value in [
      ..._pool.skip(1),
      ..._floats.map(_bits),
      ..._objects.map(_content),
    ]) {
      final op = const <IntOp>[.add, .xor, .sub][_random.nextInt(3)];
      result = _block.add(IntBinary(op, result, value));
    }
    _block.end(Return(_convertTo(signature.result!, result)));
    return LirFunction(name, signature, _blocks);
  }

  void _keep(LirValue value) => switch (value.type!) {
    .f64 => _floats,
    .ref => _objects,
    _ => _pool,
  }.add(value);

  /// A new object holding a number, another object and a double.
  void _allocate() {
    final object = _block.add(Alloc(_block.add(ConstInt(_objectBytes))));
    _block.add(Store(.i64, object, _pick(), offset: 8));
    if (_objects.isNotEmpty) {
      _block.add(Store(.ref, object, _pickOf(.ref), offset: 16));
    }
    _block.add(Store(.f64, object, _pickOf(.f64), offset: 24));
    _keep(object);
  }

  /// Reads or writes an object. Its link may be null, so it is only compared.
  void _objectOperation() {
    final object = _pickOf(.ref);
    switch (_random.nextInt(6)) {
      case 0:
        _allocate();
      case 1:
        _block.add(Store(.i64, object, _pick(), offset: 8));
      case 2:
        _block.add(Store(.ref, object, _pickOf(.ref), offset: 16));
      case 3:
        final link = _block.add(Load(.ref, object, offset: 16));
        final none = _block.add(ConstNull());
        final other = _random.nextBool() ? none : _pickOf(.ref);
        _keep(_block.add(Compare(.eq, link, other)));
      case 4:
        _keep(_block.add(Load(.f64, object, offset: 24)));
      default:
        _keep(_block.add(Load(.i64, object, offset: 8)));
    }
  }

  LirValue _content(LirValue object) =>
      _block.add(Load(.i64, object, offset: 8));

  /// The bits of a double, or 0 for NaN, whose bits are not specified.
  LirValue _bits(LirValue value) {
    final bits = _block.add(Convert(.floatBitsToInt, value));
    final known = _block.add(Compare(.eq, value, value));
    return _block.add(IntBinary(.mul, bits, known));
  }

  LirValue _convertTo(LirType type, LirValue value) => switch (type) {
    .f64 => _block.add(Convert(.intToFloat, value)),
    .ref => _pickOf(.ref),
    _ => value,
  };

  LirValue _pickOf(LirType type) => switch (type) {
    .f64 => _floats[_random.nextInt(_floats.length)],
    .ref => _objects[_random.nextInt(_objects.length)],
    _ => _pick(),
  };

  LirValue _pick() => _pool[_random.nextInt(_pool.length)];

  void _statements(int count, int depth) {
    for (var i = 0; i < count; i++) {
      switch (_random.nextInt(depth > 0 ? 23 : 20)) {
        case 0:
          _pool.add(_block.add(ConstInt(integer())));
        case 1:
          final relation = Relation.values[_random.nextInt(10)];
          _pool.add(_block.add(Compare(relation, _pick(), _pick())));
        case 2:
          _address();
        case 3 || 4 when _done.isNotEmpty && depth == 2:
          _call();
        case 13 || 14 || 15 || 16:
          _floatOperation();
        case 17 || 18 || 19:
          _objectOperation();
        case 20:
          _diamond(depth - 1);
        case 21:
          _loop(depth - 1);
        case 22:
          _exit();
        default:
          _arithmetic();
      }
    }
  }

  void _arithmetic() {
    final op = IntOp.values[_random.nextInt(IntOp.values.length)];
    var right = _pick();
    if (op == .div || op == .rem) {
      right = _block.add(IntBinary(.or, right, _block.add(ConstInt(1))));
    } else if (op == .shl || op == .sar || op == .shr) {
      right = _block.add(IntBinary(.and, right, _block.add(ConstInt(63))));
    }
    _pool.add(_block.add(IntBinary(op, _pick(), right)));
  }

  void _floatOperation() {
    LirValue pick() => _pickOf(.f64);
    switch (_random.nextInt(8)) {
      case 0:
        _keep(_block.add(ConstFloat(float())));
      case 1:
        _keep(_block.add(Convert(.intToFloat, _pick())));
      case 2:
        final relation = Relation.values[_random.nextInt(6)];
        _keep(_block.add(Compare(relation, pick(), pick())));
      case 3:
        final op = FloatUnaryOp.values[_random.nextInt(2)];
        _keep(_block.add(FloatUnary(op, pick())));
      case 4:
        _keep(_bits(pick()));
      case 5:
        // Small enough to convert back.
        final mask = _block.add(ConstInt(0xfffffff));
        final small = _block.add(IntBinary(.and, _pick(), mask));
        final whole = _block.add(Convert(.intToFloat, small));
        final eighth = _block.add(ConstFloat(-0.125));
        final scaled = _block.add(FloatBinary(.mul, whole, eighth));
        _keep(_block.add(Convert(.floatToInt, scaled)));
      default:
        final op = FloatOp.values[_random.nextInt(4)];
        _keep(_block.add(FloatBinary(op, pick(), pick())));
    }
  }

  /// Address arithmetic that ends as an ordinary integer.
  void _address() {
    final base = _block.add(Convert(.intToPtr, _pick()));
    final moved = _block.add(PtrAdd(base, _pick()));
    _pool.add(_block.add(Compare(.eq, moved, base)));
    _pool.add(_block.add(Convert(.ptrToInt, moved)));
  }

  void _call() {
    final target = _done[_random.nextInt(_done.length)];
    final arguments = target.signature.parameters.map(_pickOf).toList();
    final call = _random.nextBool()
        ? Call(target.name, target.signature, arguments)
        : CallIndirect(
            _block.add(SymbolAddress(target.name)),
            target.signature,
            arguments,
          );
    _block.add(call);
    // Sometimes the result is never used.
    if (_random.nextInt(4) > 0) _keep(call);
  }

  LirBlock _open(List<LirType> parameters) {
    final block = LirBlock(parameters);
    _blocks.add(block);
    return block;
  }

  List<LirValue> _pickAll(List<LirType> types) => types.map(_pickOf).toList();

  /// Restores the values available before a nested region.
  void _restore(
    List<LirValue> words,
    List<LirValue> floats,
    List<LirValue> objects,
  ) {
    _objects
      ..clear()
      ..addAll(objects);
    _pool
      ..clear()
      ..addAll(words);
    _floats
      ..clear()
      ..addAll(floats);
  }

  /// Two sides computing different values for a shared continuation.
  void _diamond(int depth) {
    final types = [for (var i = _random.nextInt(4); i >= 0; i--) _type()];
    final left = LirBlock(), right = LirBlock();
    _block.end(Branch(_pick(), LirEdge(left), LirEdge(right)));
    final words = List.of(_pool), floats = List.of(_floats);
    final objects = List.of(_objects);
    final ends = <LirBlock>[], results = <List<LirValue>>[];
    for (final side in [left, right]) {
      _blocks.add(side);
      _block = side;
      _statements(1 + _random.nextInt(6), depth);
      ends.add(_block);
      results.add(_pickAll(types));
      _restore(words, floats, objects);
    }
    final join = _open(types);
    for (final (i, end) in ends.indexed) {
      end.end(Jump(LirEdge(join, results[i])));
    }
    _block = join;
    join.parameters.forEach(_keep);
  }

  /// A counted loop whose back edge permutes its carried values.
  void _loop(int depth) {
    final types = [for (var i = _random.nextInt(5); i >= 0; i--) _type()];
    final start = _block.add(ConstInt(_random.nextInt(4)));
    final head = _open([.i64, ...types]);
    _block.end(Jump(LirEdge(head, [start, ..._pickAll(types)])));
    final body = LirBlock(), exit = LirBlock();
    final [counter, ...carried] = head.parameters;
    head.end(Branch(counter, LirEdge(body), LirEdge(exit)));
    carried.forEach(_keep);
    final words = List.of(_pool), floats = List.of(_floats);
    final objects = List.of(_objects);
    _blocks.add(body);
    _block = body;
    _statements(1 + _random.nextInt(6), depth);
    final one = _block.add(ConstInt(1));
    final next = _block.add(IntBinary(.sub, counter, one));
    final rotated = [
      for (final type in types)
        if (carried.where((value) => value.type == type).toList()
            case final same when _random.nextBool())
          same[_random.nextInt(same.length)]
        else
          _pickOf(type),
    ];
    _block.end(Jump(LirEdge(head, [next, ...rotated])));
    _restore(words, floats, objects);
    _blocks.add(exit);
    _block = exit;
  }

  /// An early return, with both edges of its branch carrying arguments.
  void _exit() {
    final leave = LirBlock([_result]), stay = LirBlock([.i64, .f64]);
    final zero = _block.add(ConstInt(0x55));
    final rare = _block.add(Compare(.eq, _pick(), zero));
    _block.end(
      Branch(
        rare,
        LirEdge(leave, [_pickOf(_result)]),
        LirEdge(stay, [_pick(), _pickOf(.f64)]),
      ),
    );
    leave.end(Return(leave.parameters.single));
    _blocks.addAll([leave, stay]);
    _block = stay;
    stay.parameters.forEach(_keep);
  }
}
