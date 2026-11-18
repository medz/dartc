import 'package:dartc/ir.dart';

import 'selected_function.dart';

/// Tracks selected operands using the shared graph liveness.
final class FunctionLiveness(
  SelectedFunction body,
  Iterable<Value> Function(Value) inputsOf,
  Set<Value> calls, {
  super.extraInputs,
}) extends ValueLiveness {
  this
    : super(
        body.blocks,
        body.entry,
        body.parametersOf,
        (block) => body.instructions[block]!,
        (block) => body.ends[block]!,
        body.argumentsOf,
        inputsOf,
        calls,
        introduced: body.introduced,
      );
}
