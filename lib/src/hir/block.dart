import 'instruction.dart';
import 'value.dart';

/// A straight run of instructions with one entry and one terminator.
final class HirBlock([Iterable<HirType> parameters = const []]) {
  final List<HirParameter> parameters = .unmodifiable(
    parameters.map(HirParameter.new),
  );
  final List<HirInstruction> instructions = [];

  /// The final transfer; set once by [end].
  HirTerminator? terminator;

  /// Appends [instruction] and returns it.
  T add<T extends HirInstruction>(T instruction) {
    if (terminator != null) throw StateError('The block has already ended.');
    instructions.add(instruction);
    return instruction;
  }

  /// Finishes this block.
  void end(HirTerminator terminator) {
    if (this.terminator != null) {
      throw StateError('The block has already ended.');
    }
    this.terminator = terminator;
  }
}

/// A transfer to [target], supplying its parameters.
final class HirEdge(
  final HirBlock target, [
  Iterable<HirValue> arguments = const [],
]) {
  final List<HirValue> arguments = .unmodifiable(arguments);
}

/// The operation ending a block.
sealed class HirTerminator() {
  /// Values consumed here, excluding edge arguments.
  List<HirValue> get inputs;

  /// Outgoing edges in a fixed order.
  List<HirEdge> get edges => const [];
}

final class HirJump(final HirEdge edge) extends HirTerminator {
  @override
  List<HirValue> get inputs => const [];
  @override
  List<HirEdge> get edges => [edge];
}

final class HirBranch(
  final HirValue condition,
  final HirEdge ifTrue,
  final HirEdge ifFalse,
) extends HirTerminator {
  @override
  List<HirValue> get inputs => [condition];
  @override
  List<HirEdge> get edges => [ifTrue, ifFalse];
}

final class HirReturn([final HirValue? value]) extends HirTerminator {
  @override
  List<HirValue> get inputs => [?value];
}

/// Ends the process, as `exit` from `dart:io` does.
final class HirExit(final HirValue code) extends HirTerminator {
  @override
  List<HirValue> get inputs => [code];
}

/// A point that execution never reaches.
final class HirUnreachable() extends HirTerminator {
  @override
  List<HirValue> get inputs => const [];
}
