import 'instruction.dart';
import 'value.dart';

/// A straight run of instructions with one entry and one terminator.
final class LirBlock([Iterable<LirType> parameters = const []]) {
  final List<LirParameter> parameters = .unmodifiable(
    parameters.map(LirParameter.new),
  );
  final List<LirInstruction> instructions = [];

  /// The final transfer; set once by [end].
  LirTerminator? terminator;

  /// Appends [instruction] and returns it.
  T add<T extends LirInstruction>(T instruction) {
    if (terminator != null) throw StateError('The block has already ended.');
    instructions.add(instruction);
    return instruction;
  }

  /// Finishes this block.
  void end(LirTerminator terminator) {
    if (this.terminator != null) {
      throw StateError('The block has already ended.');
    }
    this.terminator = terminator;
  }
}

/// A transfer to [target], supplying its trailing parameters.
final class LirEdge(
  final LirBlock target, [
  Iterable<LirValue> arguments = const [],
]) {
  final List<LirValue> arguments = .unmodifiable(arguments);
}

/// The operation ending a block.
sealed class LirTerminator() {
  /// Values consumed here, excluding a call's own operands.
  List<LirValue> get inputs;

  /// Outgoing edges in a fixed order.
  List<LirEdge> get edges;

  /// Types an edge supplies before its explicit arguments.
  List<LirType> implicit(LirEdge edge) => const [];
}

final class Jump(final LirEdge edge) extends LirTerminator {
  @override
  List<LirValue> get inputs => const [];
  @override
  List<LirEdge> get edges => [edge];
}

/// Takes [ifTrue] unless [condition] is 0.
final class Branch(
  final LirValue condition,
  final LirEdge ifTrue,
  final LirEdge ifFalse,
) extends LirTerminator {
  @override
  List<LirValue> get inputs => [condition];
  @override
  List<LirEdge> get edges => [ifTrue, ifFalse];
}

final class Return([final LirValue? value]) extends LirTerminator {
  @override
  List<LirValue> get inputs => [?value];
  @override
  List<LirEdge> get edges => const [];
}

/// Leaves this function by throwing to its caller.
final class Throw(final LirValue exception, final LirValue trace)
    extends LirTerminator {
  @override
  List<LirValue> get inputs => [exception, trace];
  @override
  List<LirEdge> get edges => const [];
}

/// Performs [call] and continues on the edge matching its outcome.
///
/// [onReturn] first receives the result, if any. [onThrow] first receives the
/// exception and its trace, so a failed call's result is never visible.
final class Invoke(
  final LirCall call,
  final LirEdge onReturn,
  final LirEdge onThrow,
) extends LirTerminator {
  @override
  List<LirValue> get inputs => const [];
  @override
  List<LirEdge> get edges => [onReturn, onThrow];
  @override
  List<LirType> implicit(LirEdge edge) =>
      identical(edge, onThrow) ? const [.ref, .ref] : [?call.type];
}

/// A point that execution never reaches.
final class Unreachable() extends LirTerminator {
  @override
  List<LirValue> get inputs => const [];
  @override
  List<LirEdge> get edges => const [];
}
