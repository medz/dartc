import 'dart:collection';

import 'type.dart';
import 'value.dart';

/// The control transfer executed after a block's last instruction.
sealed class const Terminator() {
  /// The outgoing edges, with the exceptional edge last when present.
  Iterable<Jump> get successors => switch (this) {
    Return() || Unreachable() => const [],
    Throw(:final onThrow) ||
    ExhaustivenessFailure(:final onThrow) => [?onThrow],
    Invoke(:final onReturn, :final onThrow) => [?onReturn, onThrow],
    Yield(:final onResume, :final onCancel) => [onResume, ?onCancel],
    YieldStream(:final onResume, :final onCancel, :final onThrow) => [
      onResume,
      onCancel,
      ?onThrow,
    ],
    Await(:final onResume, :final onThrow) => [?onResume, ?onThrow],
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
  };
}

/// Ends this activation with an optional result.
///
/// A function declared `void` can still forward a value to its caller.
/// An async body supplies an already checked `FutureOr<T>` only after its
/// finalizers finish. At the activation boundary the runtime adopts a matching
/// `Future<T>`; adoption errors do not re-enter the body's earlier catch regions.
/// This completion protocol is distinct from Await's local exception edge.
final class const Return([
  /// The returned operand, or `null` for a bare return.
  final Value? value,
]) extends Terminator;

/// Publishes one generator element and suspends this activation.
///
/// A synchronous iterator resumes at [onResume] on its next `moveNext`.
/// A stream waits out a pause and takes [onCancel] to run pending finalizers
/// when its subscription has been canceled.
final class const Yield(
  /// The already checked element, evaluated before suspension.
  final Value value,

  /// The continuation after publishing the element.
  final Jump onResume, {

  /// The normal return path on cancellation, required only for a stream.
  final Jump? onCancel,
}) extends Terminator;

/// Forwards a stream's data and error events to an async generator's listener.
///
/// Pausing or canceling the outer subscription propagates to the delegate.
/// Forwarded error events do not enter [onThrow].
final class const YieldStream(
  /// The evaluated stream whose events are forwarded.
  final Value stream,

  /// Continues after the delegated stream closes.
  final Jump onResume, {

  /// Runs pending finalizers after cancellation.
  required final Jump onCancel,

  /// Handles an exception raised by delegation itself, such as a failed listen.
  final Jump? onThrow,
}) extends Terminator;

/// Suspends an async activation until [operand] supplies [result].
///
/// The runtime awaits only the `Future<T>` arm, where T is [result]'s type;
/// a future belonging to the value arm remains a value. Scalar and completed
/// future operands still use Dart's asynchronous resumption protocol.
final class Await(
  final Value operand,
  final AwaitResult result, {
  required final Jump? onResume,
  final Jump? onThrow,
}) extends Terminator {
  this {
    if (operand.type is CellType ||
        !ValueType.futureOr(result.type).accepts(operand.type) ||
        (result.type == .never) != (onResume == null)) {
      throw ArgumentError('Invalid await operand or continuations.');
    }
  }
}

/// The end of a path whose [cause] cannot return a value.
final class Unreachable(
  /// The operand of type `Never` that makes normal completion impossible.
  final Value cause,
) extends Terminator {
  this {
    if (cause.type != .never) throw ArgumentError('Expected a Never operand.');
  }
}

/// Throws [exception] to [onThrow], or unwinds to the caller.
final class Throw(
  /// The exception object from the Dart `throw` expression.
  final Value exception, {

  /// The original trace for a rethrow, or `null` to start a new throw.
  final Value? stackTrace,

  /// The exceptional edge to the innermost local handler, if any.
  final Jump? onThrow,
}) extends Terminator {
  this {
    if (!ValueType.object.accepts(exception.type)) {
      throw ArgumentError('Expected a non-null exception object.');
    }
    if (stackTrace case final trace?
        when !ValueType.stackTrace.accepts(trace.type)) {
      throw ArgumentError('Expected a StackTrace operand.');
    }
  }
}

/// The runtime error if execution reaches the end of an exhaustive switch.
final class const ExhaustivenessFailure([
  /// The local handler for the error, if any.
  final Jump? onThrow,
]) extends Terminator;

/// Evaluates [operation] and transfers control according to its outcome.
///
/// Only [onReturn] can pass the result as an edge argument. Only [onThrow]
/// can pass [UnwindValue.exception] or [UnwindValue.stackTrace].
final class Invoke(
  /// The operation performed once at the end of the block.
  final Instruction operation, {

  /// The success edge, absent for an operation returning `Never`.
  required final Jump? onReturn,

  /// The handler edge used if evaluation throws.
  required final Jump onThrow,
}) extends Terminator {
  this {
    if (!operation.mayThrow ||
        (operation.type == .never) != (onReturn == null)) {
      throw ArgumentError('Invalid continuations for the invoked operation.');
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

  /// The outgoing edges, with the exceptional edge last when present.
  Iterable<Jump> get successors => end.successors;

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
