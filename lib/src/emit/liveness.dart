import 'package:dartc/graph.dart';
import 'package:dartc/lir.dart';

/// The closed range of positions where a value needs a location.
final class Interval(final LirValue value, final int start) {
  int end = start;

  /// Whether the value must survive a call inside its range.
  bool crossesCall = false;

  /// Extends the range to [position], which is never before the current end.
  void extend(int position) => end = position;
}

/// Blocks in reverse postorder and the live range of every value.
///
/// Instruction number n reads its operands at 2n and writes its result at
/// 2n + 1, so a result may reuse the location of an operand that dies there.
/// Block parameters are written at their block's first position.
final class Liveness(final LirFunction function) {
  final List<LirBlock> order = reversePostorder(
    function.entry,
    (block) => block.terminator!.edges.map((edge) => edge.target),
  );
  final intervals = <LirValue, Interval>{};
  final _liveIn = <LirBlock, Set<LirValue>>{};
  final _calls = <int>[];

  this {
    _solve();
    _buildIntervals();
    for (final interval in intervals.values) {
      interval.crossesCall = _calls.any(
        (call) => interval.start <= call && interval.end > call,
      );
    }
  }

  static List<LirValue> _endUses(LirBlock block) => [
    ...block.terminator!.inputs,
    for (final edge in block.terminator!.edges) ...edge.arguments,
  ];

  Set<LirValue> _liveOut(LirBlock block) => {
    for (final edge in block.terminator!.edges) ...?_liveIn[edge.target],
  };

  /// Grows live-in sets until stable; each is bounded by the value count.
  void _solve() {
    bool changed;
    do {
      changed = false;
      for (final block in order.reversed) {
        final live = _liveOut(block)..addAll(_endUses(block));
        for (final instruction in block.instructions.reversed) {
          live.remove(instruction);
          live.addAll(instruction.inputs);
        }
        live.removeAll(block.parameters);
        if (live.length != _liveIn[block]?.length) {
          _liveIn[block] = live;
          changed = true;
        }
      }
    } while (changed);
  }

  void _include(LirValue value, int position) =>
      (intervals[value] ??= Interval(value, position)).extend(position);

  void _buildIntervals() {
    var position = 0;
    for (final block in order) {
      for (final value in [..._liveIn[block]!, ...block.parameters]) {
        _include(value, position);
      }
      for (final instruction in block.instructions) {
        position += 2;
        for (final input in instruction.inputs) {
          _include(input, position);
        }
        if (instruction is LirCall) _calls.add(position);
        if (instruction.type != null) _include(instruction, position + 1);
      }
      position += 2;
      for (final value in [..._endUses(block), ..._liveOut(block)]) {
        _include(value, position);
      }
      position += 2;
    }
  }
}
