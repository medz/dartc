import 'dart:convert';

import '../../frontend/lowering/fixtures/assertions.dart' as statements;
import '../../frontend/lowering/fixtures/disabled_assertion_closure.dart'
    as closures;
import '../../frontend/lowering/fixtures/effects.dart';

void observe(String name, Object? Function() run, [Object? input]) {
  calls.clear();
  Object? value, error;
  try {
    value = run();
  } on AssertionError catch (failure) {
    error = ['assert', failure.message];
  } on StateError catch (failure) {
    error = ['state', failure.message];
  }
  print(jsonEncode([name, input, value, error, calls]));
}

class Message(final int value) {
  @override
  String toString() => throw StateError('message must not be formatted');
}

bool retainedMessage(int mode) {
  final Object? message = switch (mode) {
    0 => null,
    1 => 42,
    2 => 1.25,
    3 => false,
    4 => 'assertion',
    _ => Message(7),
  };
  try {
    assert(false, message);
  } on AssertionError catch (error, trace) {
    for (var i = 0; i < 40000; i++) {
      Message(i);
    }
    return identical(error.message, message) &&
        trace.toString().contains('retainedMessage') &&
        error.stackTrace.toString() == trace.toString();
  }
  return true;
}

void main() {
  for (final (name, run) in <(String, Object? Function(int))>[
    ('asserted', statements.asserted),
    ('caught', statements.caught),
    ('closure', statements.closureCondition),
    ('construct', statements.construct),
    ('early', statements.constructEarly),
    ('typed', statements.typedCatch),
  ]) {
    for (final input in [-1, 0, 1]) {
      observe(name, () => run(input), input);
    }
  }
  for (final (name, run) in <(String, Object? Function(bool))>[
    ('withoutMessage', statements.withoutMessage),
    ('throwingMessage', statements.throwingMessage),
    ('finallyOverride', statements.finalizerOverride),
  ]) {
    for (final input in [false, true]) {
      observe(name, () => run(input), input);
    }
  }
  observe('nestedClosure', closures.skippedClosure);
  observe('nestedConstructor', closures.skippedConstructor);
  observe('nestedExtension', closures.skippedExtension);
  for (var mode = 0; mode < 6; mode++) {
    observe('retainedMessage', () => retainedMessage(mode), mode);
  }
}
