import 'instruction.dart';

/// A straight run of instructions.
final class HirBlock() {
  final List<HirInstruction> instructions = [];
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

/// A function body without parameters or a result.
final class HirFunction(final String name, final HirBlock body);

/// A whole program, started by [main].
final class HirModule(final HirFunction main);
