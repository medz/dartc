import 'package:dartc/graph.dart';
import 'package:dartc/lir.dart';

import 'selection.dart';

/// The closed range of positions where a value needs a location.
final class Interval(final LirValue value, final int start) {
  int end = start;

  /// Whether the value must survive a call inside its range.
  bool crossesCall = false;

  /// Whether the value is used after a throw is caught.
  bool crossesThrow = false;

  /// Extends the range to [position], which is never before the current end.
  void extend(int position) => end = position;
}

/// Blocks in the order of their code and the live range of every value.
///
/// Those that are seldom come to are last, and otherwise in reverse postorder.
///
/// Instruction number n reads its operands at 2n and writes its result at
/// 2n + 1, so a result may reuse the location of an operand that dies there.
/// Block parameters are written at their block's first position.
final class Liveness(final LirFunction function, final Selection selection) {
  final List<LirBlock> order = _orderOf(function);

  /// The values that should be where a value is.
  final related = <LirValue, List<LirValue>>{};

  final intervals = <LirValue, Interval>{};
  final _liveIn = <LirBlock, Set<LirValue>>{};
  final _liveAfter = <LirCall, Set<LirValue>>{};

  this {
    _solve();
    _recordCalls();
    _buildIntervals();
    for (final live in _liveAfter.values) {
      for (final value in live) {
        intervals[value]!.crossesCall = true;
      }
    }
    _relate();
    for (final block in order) {
      if (block.terminator case Invoke(:final onThrow)) {
        for (final value in [
          ..._kept(onThrow.arguments),
          ...?_liveIn[onThrow.target],
        ]) {
          intervals[value]!.crossesThrow = true;
        }
      }
    }
  }

  /// The values that exist before [call] and are used after it.
  Set<LirValue> liveAfter(LirCall call) => _liveAfter[call]!;

  static List<LirBlock> _orderOf(LirFunction function) {
    Iterable<LirBlock> successors(LirBlock block) =>
        block.terminator!.edges.map((edge) => edge.target);
    final all = reversePostorder(function.entry, successors);
    // Blocks that only lead to throws, or that only throws lead to.
    final cold = <LirBlock>{};
    for (final block in all.reversed) {
      final next = successors(block);
      final isEnd = block.terminator is! Return && next.isEmpty;
      if (isEnd || next.isNotEmpty && next.every(cold.contains)) {
        cold.add(block);
      }
    }
    final usual = reversePostorder(
      function.entry,
      (block) => switch (block.terminator!) {
        Invoke(:final onReturn) => [onReturn.target],
        final end => end.edges.map((edge) => edge.target),
      },
    ).toSet();
    bool isLast(LirBlock block) =>
        block != function.entry &&
        (cold.contains(block) || !usual.contains(block));
    return [...all.where((block) => !isLast(block)), ...all.where(isLast)];
  }

  void _relate() {
    void relate(LirValue a, LirValue b) {
      (related[a] ??= []).add(b);
      (related[b] ??= []).add(a);
    }

    for (final block in order) {
      final end = block.terminator!;
      for (final edge in end.edges) {
        final parameters = edge.target.parameters;
        final implicit = parameters.length - edge.arguments.length;
        for (final (i, argument) in edge.arguments.indexed) {
          relate(parameters[implicit + i], argument);
        }
      }
    }
  }

  List<LirValue> _kept(Iterable<LirValue> values) => [
    for (final value in values)
      if (!selection.isFolded(value)) value,
  ];

  List<LirValue> _inputsOf(LirInstruction instruction) =>
      _kept(selection.inputsOf(instruction));

  /// What the end of [block] uses, after a call it makes.
  List<LirValue> _endUses(LirBlock block) => _kept([
    ...selection.endInputsOf(block.terminator!),
    for (final edge in block.terminator!.edges) ...edge.arguments,
  ]);

  /// The call that ends [block], if there is one.
  static LirCall? _endCall(LirBlock block) => switch (block.terminator) {
    Invoke(:final call) => call,
    _ => null,
  };

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
        if (_endCall(block) case final call?) live.addAll(_inputsOf(call));
        for (final instruction in block.instructions.reversed) {
          live.remove(instruction);
          if (!selection.isFolded(instruction)) {
            live.addAll(_inputsOf(instruction));
          }
        }
        live.removeAll(block.parameters);
        if (live.length != _liveIn[block]?.length) {
          _liveIn[block] = live;
          changed = true;
        }
      }
    } while (changed);
  }

  /// Finds what is alive at each call, now that live-in sets are stable.
  void _recordCalls() {
    for (final block in order) {
      final live = _liveOut(block)..addAll(_endUses(block));
      if (_endCall(block) case final call?) {
        _liveAfter[call] = Set.of(live);
        live.addAll(_inputsOf(call));
      }
      for (final instruction in block.instructions.reversed) {
        live.remove(instruction);
        if (instruction is LirCall) _liveAfter[instruction] = Set.of(live);
        if (!selection.isFolded(instruction)) {
          live.addAll(_inputsOf(instruction));
        }
      }
    }
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
        if (selection.isFolded(instruction)) continue;
        for (final input in _inputsOf(instruction)) {
          _include(input, position);
        }
        if (instruction.type != null) _include(instruction, position + 1);
      }
      position += 2;
      if (_endCall(block) case final call?) {
        for (final input in _inputsOf(call)) {
          _include(input, position);
        }
        position += 2;
      }
      for (final value in [..._endUses(block), ..._liveOut(block)]) {
        _include(value, position);
      }
      position += 2;
    }
  }
}
