import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'boxes.dart';
import 'dispatch.dart';
import 'statics.dart';

/// Lowers calls of the runtime function that tests objects against types.
///
/// Type arguments are often types that no class is of but their own, such as
/// `int`. For these, the class of the object tells: the object is of such a
/// type if its class passes the test of the type. Everything else, and null,
/// is left to the call.
final class InstanceTests(
  final ObjectLayout _layout,
  final StaticData _statics,
  final BoxLowering _boxes,

  /// Adds blocks to the function.
  final void Function(LirBlock block) _addBlock,
) {
  HirModule get _module => _layout.module;

  /// Whether a call of [target] with [type] is lowered here.
  bool lowers(HirCallable target, HirValue type) =>
      target == _module.isInstance &&
      switch (type) {
        HirStatic(:final object) => _module.sealedTypes.containsKey(object),
        _ => _module.sealedTypes.isNotEmpty,
      };

  /// Whether [object] is of [type], which [lowers] allowed, where [call] asks
  /// the runtime. Ends [block], and returns the block that continues and the
  /// answer.
  (LirBlock, LirValue) lower(
    LirBlock block,
    LirValue object,
    HirValue type,
    LirValue typeObject,
    LirCall call,
  ) {
    final asked = _newBlock(), yes = _newBlock(), present = _newBlock();
    final done = _newBlock([.i64]);
    final isNull = block.add(Compare(.eq, object, block.add(ConstNull())));
    block.end(Branch(isNull, LirEdge(asked), LirEdge(present)));
    final (next, number) = _boxes.classNumber(
      present,
      object,
      mayBeInteger: true,
    );
    final LirValue passes;
    if (type case HirStatic(object: final known)) {
      final test = _statics.test(_module.sealedTypes[known]!);
      passes = _layout.isInstance(next, test, number);
    } else {
      // The type that the class decides, if any, at its number.
      final table = next.add(StaticObject(_statics.sealedTypes));
      final offset = next.add(IntBinary(.shl, number, next.add(ConstInt(3))));
      final decided = next.add(Load(.ref, table, offset: 8, index: offset));
      passes = next.add(Compare(.eq, decided, typeObject));
    }
    next.end(Branch(passes, LirEdge(yes), LirEdge(asked)));
    yes.end(Jump(LirEdge(done, [yes.add(ConstInt(1))])));
    asked.end(Jump(LirEdge(done, [asked.add(call)])));
    return (done, done.parameters.single);
  }

  LirBlock _newBlock([List<LirType> parameters = const []]) {
    final block = LirBlock(parameters);
    _addBlock(block);
    return block;
  }
}
