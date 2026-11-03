import 'dart:collection';

import 'type.dart';
import 'value.dart';

/// The control transfer executed after a block's last instruction.
sealed class const Terminator();

/// A transfer back to the caller with an optional result.
///
/// A function declared `void` can still forward a value to its caller.
final class const Return([
  /// The returned operand, or `null` for a bare return.
  final Value? value,
]) extends Terminator;

/// The end of a path whose [cause] cannot return a value.
final class Unreachable(
  /// The operand of type `Never` that makes normal completion impossible.
  final Value cause,
) extends Terminator {
  this {
    if (cause.type != .never) throw ArgumentError('Expected a Never operand.');
  }
}

/// An exceptional transfer carrying [exception] out of the function.
final class Throw(
  /// The exception object from the Dart `throw` expression.
  final Value exception,
) extends Terminator {
  this {
    if (!ValueType.object.accepts(exception.type)) {
      throw ArgumentError('Expected a non-null exception object.');
    }
  }
}

/// A control-flow edge that binds the destination block's parameters.
final class Jump(
  /// The block entered by this edge.
  final Block target, [
  Iterable<Value> arguments = const [],
]) extends Terminator {
  /// The incoming value for each parameter of [target], in order.
  final List<Value> arguments = .unmodifiable(arguments);

  /// Creates an edge to [target] with a snapshot of [arguments].
  ///
  /// Throws [ArgumentError] for a wrong argument count or an incompatible type.
  this {
    checkArguments(target.parameters.map((p) => p.type), this.arguments);
  }
}

/// A conditional transfer that takes exactly one of two edges.
final class Branch(
  /// The boolean operand that selects the edge.
  final Value condition,

  /// The edge taken when [condition] is `true`.
  final Jump ifTrue,

  /// The edge taken when [condition] is `false`.
  final Jump ifFalse,
) extends Terminator {
  /// Creates a branch on [condition].
  ///
  /// Throws [ArgumentError] if [condition] has any type other than [ValueType.boolean].
  this {
    if (condition.type != .boolean) {
      throw ArgumentError('Boolean condition required.');
    }
  }
}

/// A basic block with ordered instructions and a single terminator.
///
/// Each parameter type creates one fresh SSA value. Append instructions with
/// [emit] and seal the block with [finish].
final class Block([Iterable<ValueType> types = const []]) {
  /// The values bound on entry, in the order given to [Block.new].
  final List<BlockParameter> parameters = blockParameters(types);
  final _instructions = <Instruction>[];

  /// A read-only view in execution order that reflects subsequent calls to [emit].
  late final UnmodifiableListView<Instruction> instructions = .new(
    _instructions,
  );
  Terminator? _end;

  /// The control transfer set by [finish].
  ///
  /// Reading this before [finish] throws [StateError].
  Terminator get end => _end ?? (throw StateError('Unterminated block.'));

  /// The outgoing edges of [end], in true-then-false order for a [Branch].
  Iterable<Jump> get successors => switch (end) {
    Return() || Unreachable() || Throw() => const [],
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
  };

  /// Appends [instruction] and returns the same object for use as an SSA operand.
  ///
  /// Throws [StateError] if the block is already sealed.
  T emit<T extends Instruction>(T instruction) {
    if (_end != null) throw StateError('Block already terminated.');
    _instructions.add(instruction);
    return instruction;
  }

  /// Seals the instruction sequence with [end].
  ///
  /// Throws [StateError] if the block already has a terminator.
  void finish(Terminator end) {
    if (_end != null) throw StateError('Block already terminated.');
    _end = end;
  }
}
