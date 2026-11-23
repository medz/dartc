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
  late LirBlock _block;
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

  List<LirFunction> functions() {
    for (var i = 0; i < 5; i++) {
      _done.add(_function('$_prefix$i'));
    }
    return _done;
  }

  LirFunction _function(String name) {
    final arity = _random.nextInt(13);
    final signature = LirSignature(List.filled(arity, .i64), .i64);
    _block = LirBlock(signature.parameters);
    _blocks = [_block];
    _pool
      ..clear()
      ..addAll(_block.parameters);
    _pool.add(_block.add(ConstInt(integer())));
    _statements(8 + _random.nextInt(30), 2);
    // Reading every remaining value at the end keeps them all alive.
    var result = _pool.first;
    for (final value in _pool.skip(1)) {
      final op = const <IntOp>[.add, .xor, .sub][_random.nextInt(3)];
      result = _block.add(IntBinary(op, result, value));
    }
    _block.end(Return(result));
    return LirFunction(name, signature, _blocks);
  }

  LirValue _pick() => _pool[_random.nextInt(_pool.length)];

  void _statements(int count, int depth) {
    for (var i = 0; i < count; i++) {
      switch (_random.nextInt(depth > 0 ? 16 : 13)) {
        case 0:
          _pool.add(_block.add(ConstInt(integer())));
        case 1:
          final relation = Relation.values[_random.nextInt(10)];
          _pool.add(_block.add(Compare(relation, _pick(), _pick())));
        case 2:
          _address();
        case 3 || 4 when _done.isNotEmpty && depth == 2:
          _call();
        case 13:
          _diamond(depth - 1);
        case 14:
          _loop(depth - 1);
        case 15:
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

  /// Address arithmetic that ends as an ordinary integer.
  void _address() {
    final base = _block.add(Convert(.intToPtr, _pick()));
    final moved = _block.add(PtrAdd(base, _pick()));
    _pool.add(_block.add(Compare(.eq, moved, base)));
    _pool.add(_block.add(Convert(.ptrToInt, moved)));
  }

  void _call() {
    final target = _done[_random.nextInt(_done.length)];
    final arguments = [for (final _ in target.signature.parameters) _pick()];
    final call = _random.nextBool()
        ? Call(target.name, target.signature, arguments)
        : CallIndirect(
            _block.add(SymbolAddress(target.name)),
            target.signature,
            arguments,
          );
    _block.add(call);
    // Sometimes the result is never used.
    if (_random.nextInt(4) > 0) _pool.add(call);
  }

  LirBlock _open(List<LirType> parameters) {
    final block = LirBlock(parameters);
    _blocks.add(block);
    return block;
  }

  /// Two sides computing different values for a shared continuation.
  void _diamond(int depth) {
    final width = 1 + _random.nextInt(4);
    final left = LirBlock(), right = LirBlock();
    _block.end(Branch(_pick(), LirEdge(left), LirEdge(right)));
    final outer = List.of(_pool);
    final ends = <LirBlock>[], results = <List<LirValue>>[];
    for (final side in [left, right]) {
      _blocks.add(side);
      _block = side;
      _statements(1 + _random.nextInt(6), depth);
      ends.add(_block);
      results.add([for (var i = 0; i < width; i++) _pick()]);
      _pool
        ..clear()
        ..addAll(outer);
    }
    final join = _open(List.filled(width, .i64));
    for (final (i, end) in ends.indexed) {
      end.end(Jump(LirEdge(join, results[i])));
    }
    _block = join;
    _pool.addAll(join.parameters);
  }

  /// A counted loop whose back edge permutes its carried values.
  void _loop(int depth) {
    final width = 1 + _random.nextInt(5);
    final start = _block.add(ConstInt(_random.nextInt(4)));
    final initial = [for (var i = 0; i < width; i++) _pick()];
    final head = _open(List.filled(width + 1, .i64));
    _block.end(Jump(LirEdge(head, [start, ...initial])));
    final body = LirBlock(), exit = LirBlock();
    final [counter, ...carried] = head.parameters;
    head.end(Branch(counter, LirEdge(body), LirEdge(exit)));
    _pool.addAll(carried);
    final outer = List.of(_pool);
    _blocks.add(body);
    _block = body;
    _statements(1 + _random.nextInt(6), depth);
    final one = _block.add(ConstInt(1));
    final next = _block.add(IntBinary(.sub, counter, one));
    final rotated = [...carried.skip(1), _pick()]..shuffle(_random);
    _block.end(Jump(LirEdge(head, [next, ...rotated])));
    _pool
      ..clear()
      ..addAll(outer);
    _blocks.add(exit);
    _block = exit;
  }

  /// An early return, with both edges of its branch carrying arguments.
  void _exit() {
    final leave = LirBlock([.i64]), stay = LirBlock([.i64, .i64]);
    final zero = _block.add(ConstInt(0x55));
    final rare = _block.add(Compare(.eq, _pick(), zero));
    _block.end(
      Branch(
        rare,
        LirEdge(leave, [_pick()]),
        LirEdge(stay, [_pick(), _pick()]),
      ),
    );
    leave.end(Return(leave.parameters.single));
    _blocks.addAll([leave, stay]);
    _block = stay;
    _pool.addAll(stay.parameters);
  }
}
