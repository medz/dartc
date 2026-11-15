import 'package:dartc/ir.dart';

import 'selected_function.dart';

/// Tracks selected operands and stack cells using the shared graph liveness.
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
        stackCells: body.stackCells,
        introduced: body.introduced,
      );
}
