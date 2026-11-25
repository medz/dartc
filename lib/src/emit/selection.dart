import 'package:dartc/lir.dart';

/// What a kind of processor can do within other instructions.
abstract interface class Abilities() {
  /// Whether [op] can have [value] on its right in the instruction.
  bool takesImmediate(IntOp op, int value);

  /// Whether integers can be compared with [value] in the instruction.
  bool comparesImmediate(int value);
}

/// Which values of [_function] are computed within the instructions that use
/// them, and what those then need.
final class Selection(final LirFunction _function, final Abilities _abilities) {
  final _uses = <LirValue, int>{};
  final _folded = <LirValue>{};

  /// The comparisons that branches do themselves.
  final _branches = <Branch, Compare>{};

  /// The numbers of what they access that loads and stores have as their index.
  final _scaled = <LirInstruction, LirValue>{};

  /// What instructions have on their right.
  final _immediates = <LirInstruction, int>{};

  this {
    for (final block in _function.blocks) {
      for (final instruction in block.instructions) {
        instruction.inputs.forEach(_use);
      }
      final end = block.terminator!;
      end.inputs.forEach(_use);
      if (end case Invoke(:final call)) call.inputs.forEach(_use);
      for (final edge in end.edges) {
        edge.arguments.forEach(_use);
      }
    }
    for (final block in _function.blocks) {
      _foldBranch(block);
      block.instructions.forEach(_fold);
    }
    // Other constants are there for those that cannot have them.
    for (final MapEntry(key: value, value: count) in _uses.entries) {
      final isRemade = constantOf(value) != null;
      if (isRemade || value is ConstInt && count == 0) _folded.add(value);
    }
  }

  void _use(LirValue value) => _uses[value] = (_uses[value] ?? 0) + 1;

  void _foldBranch(LirBlock block) {
    final end = block.terminator;
    if (end is! Branch) return;
    final condition = end.condition;
    // It is done at the end of the block instead.
    if (condition is! Compare || _uses[condition] != 1) return;
    if (!block.instructions.contains(condition)) return;
    _branches[end] = condition;
    _folded.add(condition);
  }

  void _fold(LirInstruction instruction) {
    switch (instruction) {
      case IntBinary(:final op, right: final ConstInt right)
          when _abilities.takesImmediate(op, right.value):
        _immediates[instruction] = right.value;
        _uses[right] = _uses[right]! - 1;
      case Compare(left: LirValue(type: .i64), right: final ConstInt right)
          when _abilities.comparesImmediate(right.value):
        _immediates[instruction] = right.value;
        _uses[right] = _uses[right]! - 1;
      case Load(:final index?, :final width) ||
          Store(:final index?, :final width):
        if (index
            case IntBinary(op: .shl, :final left, right: ConstInt(:final value))
            when value == width.shift && value > 0 && _uses[index] == 1) {
          _scaled[instruction] = left;
          _folded.add(index);
        }
      default:
        break;
    }
  }

  /// What [value] is if it is made anew for each use, as that takes little.
  static int? constantOf(LirValue value) => switch (value) {
    ConstNull() => 0,
    ConstInt(:final value) when value >= -0x10000 && value < 0x10000 => value,
    _ => null,
  };

  /// Whether [value] is computed where it is used only.
  bool isFolded(LirValue value) => _folded.contains(value);

  /// What [instruction] has on its right instead of a value.
  int? immediateOf(LirInstruction instruction) => _immediates[instruction];

  /// Whether the index of [instruction] is a number of what it accesses.
  bool isScaled(LirInstruction instruction) => _scaled.containsKey(instruction);

  /// The comparison that [branch] does.
  Compare? comparisonOf(Branch branch) => _branches[branch];

  /// The values that [instruction] needs.
  List<LirValue> inputsOf(LirInstruction instruction) {
    if (_immediates.containsKey(instruction)) {
      return [instruction.inputs.first];
    }
    final scaled = _scaled[instruction];
    if (scaled == null) return instruction.inputs;
    return [
      for (final (i, input) in instruction.inputs.indexed)
        if (i == 1) scaled else input,
    ];
  }

  /// The values that [terminator] needs, apart from edges and calls.
  List<LirValue> endInputsOf(LirTerminator terminator) {
    final comparison = terminator is Branch ? _branches[terminator] : null;
    return comparison == null ? terminator.inputs : inputsOf(comparison);
  }
}
