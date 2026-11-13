import '../../lib/runtime/contracts.dart';

/// Takes immutable snapshots through the standard Invocation factories.
@RuntimeEntry(.invocation)
Invocation invocation(
  Symbol member,
  int kind,
  List<Type> types,
  List<Object?> positional,
  Map<Symbol, Object?> named,
) => switch (kind) {
  1 => Invocation.getter(member),
  2 => Invocation.setter(member, positional.single),
  _ => Invocation.genericMethod(member, types, positional, named),
};

/// Applies the ordinary noSuchMethod protocol after lookup or shape failure.
@RuntimeEntry(.dispatchFailure)
Object? dispatchFailure(Object? receiver, Invocation invocation) {
  if (receiver == null || receiver is Function) {
    throw NoSuchMethodError.withInvocation(receiver, invocation);
  }
  return receiver.noSuchMethod(invocation);
}

/// Reports a failed irrefutable list or map pattern match.
@RuntimeEntry(.patternMatchFailure)
Never patternMatchFailure() => throw StateError('Pattern matching error');

/// Reports a failed enabled assertion with its lazily evaluated message.
@RuntimeEntry(.assertionFailure)
Never assertionFailure(Object? message) => throw AssertionError(message);

/// Reports a reachable miss after an exhaustive switch.
@RuntimeEntry(.exhaustivenessFailure)
Never exhaustivenessFailure() => throw _ExhaustivenessError();

final class _ExhaustivenessError() extends Error {
  @override
  String toString() => 'Exhaustive switch did not match a value';
}
