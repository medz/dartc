import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'dispatch.dart';

/// Lowers what depends on references that are integers without an object.
///
/// Such a reference is odd: twice the integer, plus 1. Only integers of 63 bits
/// are so.
final class BoxLowering(
  final ObjectLayout _layout,

  /// Adds blocks to the function.
  final void Function(LirBlock block) _addBlock,
) {
  HirClass? get _integers => _layout.module.integers;

  /// The bits of the reference for [value], if it has no object.
  static int? bitsOf(int value) {
    final bits = value << 1;
    return bits >> 1 == value ? bits | 1 : null;
  }

  LirBlock _newBlock([List<LirType> parameters = const []]) {
    final block = LirBlock(parameters);
    _addBlock(block);
    return block;
  }

  /// Boxes [value], where [allocate] makes [target] objects at the end of a
  /// block and gives the block that continues and the object. Returns these.
  (LirBlock, LirValue) box(
    LirBlock block,
    HirClass target,
    LirValue value,
    (LirBlock, LirValue) Function(LirBlock block) allocate,
  ) {
    if (target != _integers) {
      final (next, object) = allocate(block);
      _fill(next, target, object, value);
      return (next, object);
    }
    final one = block.add(ConstInt(1));
    final bits = block.add(IntBinary(.shl, value, one));
    final back = block.add(IntBinary(.sar, bits, one));
    final fits = block.add(Compare(.eq, back, value));
    final small = _newBlock(), large = _newBlock();
    final done = _newBlock([.ref]);
    block.end(Branch(fits, LirEdge(small), LirEdge(large)));
    final tagged = small.add(IntBinary(.or, bits, small.add(ConstInt(1))));
    small.end(Jump(LirEdge(done, [small.add(Convert(.intToRef, tagged))])));
    final (next, object) = allocate(large);
    _fill(next, target, object, value);
    next.end(Jump(LirEdge(done, [object])));
    return (done, done.parameters.single);
  }

  void _fill(LirBlock block, HirClass target, LirValue object, LirValue value) {
    _layout
      ..setClass(block, object, target)
      ..store(block, target.fields.single, object, value);
  }

  /// What [object] has in [field]. Returns the block that continues, too.
  (LirBlock, LirValue) unbox(LirBlock block, HirField field, LirValue object) {
    if (_integers?.fields.single != field) {
      return (block, _layout.load(block, field, object));
    }
    return _choose(
      block,
      object,
      .i64,
      (small, bits) => small.add(IntBinary(.sar, bits, small.add(ConstInt(1)))),
      (large) => _layout.load(large, field, object),
    );
  }

  /// The number of the class of [object], which is an integer only if it
  /// [mayBeInteger]. Returns the block that continues, too.
  (LirBlock, LirValue) classNumber(
    LirBlock block,
    LirValue object, {
    required bool mayBeInteger,
  }) {
    LirValue load(LirBlock block) =>
        block.add(Load(.u32, object, offset: classOffset));
    final integers = _integers;
    if (!mayBeInteger || integers == null) return (block, load(block));
    return _choose(
      block,
      object,
      .i64,
      (small, _) => small.add(ConstInt(_layout.numberOf(integers)!)),
      load,
    );
  }

  /// What [ifNumber] gives for the bits of [object], if those are odd, and
  /// [ifObject] if not.
  (LirBlock, LirValue) _choose(
    LirBlock block,
    LirValue object,
    LirType type,
    LirValue Function(LirBlock block, LirValue bits) ifNumber,
    LirValue Function(LirBlock block) ifObject,
  ) {
    final bits = block.add(Convert(.refToInt, object));
    final isNumber = block.add(IntBinary(.and, bits, block.add(ConstInt(1))));
    final small = _newBlock(), large = _newBlock(), done = _newBlock([type]);
    block.end(Branch(isNumber, LirEdge(small), LirEdge(large)));
    small.end(Jump(LirEdge(done, [ifNumber(small, bits)])));
    large.end(Jump(LirEdge(done, [ifObject(large)])));
    return (done, done.parameters.single);
  }
}
