import 'dart:collection';

import 'signature.dart';
import 'value.dart';

sealed class Terminator {
  const Terminator();
}

final class Return extends Terminator {
  /// A bare return yields null. A function declared void can still return a value.
  final Value? value;
  const Return([this.value]);
}

/// Transfers control to [target], binding its parameters to [arguments] in order.
final class Jump extends Terminator {
  final Block target;
  final List<Value> arguments;
  Jump(this.target, [Iterable<Value> arguments = const []])
    : arguments = List.unmodifiable(arguments) {
    checkArguments(target.parameters.map((p) => p.type), this.arguments);
  }
}

final class Branch extends Terminator {
  final Value condition;
  final Jump ifTrue;
  final Jump ifFalse;
  Branch(this.condition, this.ifTrue, this.ifFalse) {
    if (condition.type != ValueType.boolean) {
      throw ArgumentError('Boolean condition required.');
    }
  }
}

/// An ordered sequence of instructions. Call [finish] once to seal the block.
final class Block {
  final List<BlockParameter> parameters;
  final _instructions = <Instruction>[];
  late final instructions = UnmodifiableListView(_instructions);
  Terminator? _end;
  Terminator get end => _end ?? (throw StateError('Unterminated block.'));

  Block([Iterable<ValueType> types = const []])
    : parameters = blockParameters(types);

  /// Normal control-flow edges, with the true edge first for a conditional.
  Iterable<Jump> get successors => switch (end) {
    Return() => const [],
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
  };

  T emit<T extends Instruction>(T instruction) {
    if (_end != null) throw StateError('Block already terminated.');
    _instructions.add(instruction);
    return instruction;
  }

  void finish(Terminator end) {
    if (_end != null) throw StateError('Block already terminated.');
    _end = end;
  }
}
