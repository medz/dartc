import 'package:dartc/ir.dart';

import 'double_bits.dart';
import 'native_invocation.dart';
import 'program_layout.dart';
import 'reference_equality.dart';
import 'selected_graph.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// A native call entry and its graph, before register and root allocation.
base class SelectedFunction(
  final FunctionTarget target,
  final ProgramLayout layouts,
  final Block entry, {
  List<BlockParameter>? parameters,
  FunctionTarget? sourceTarget,
}) extends SelectedGraph {
  final FunctionTarget sourceTarget = sourceTarget ?? target;
  final sourceLocations = <Object, SourceLocation>{};

  /// A continuation reference retained at every call for asynchronous unwinding.
  Value? stackContext;
  final List<BlockParameter> entryParameters = parameters ?? entry.parameters;
  final operands = <Value, List<Value>>{};
  final edgeArguments = <Jump, List<Value>>{};
  final boxes = <Instruction, Value>{};
  final introduced = <Instruction>{};
  final tests = <TypeTest, TypeTestKind>{};
  final invocations = <Instruction, FunctionTarget>{};
  // Representation changes preserve the already analyzed argument flow.
  final callOrigins = <Instruction, Instruction>{};
  final aliases = <Instruction>{};
  final resultTypes = <Value, ValueType>{};
  final stackCells = <NewCell>{};
  final operandsForAwait = <Await, Value>{};
  final operandsForYield = <Yield, Value>{};
  final parameterOverrides = <Block, List<BlockParameter>>{};

  List<BlockParameter> parametersOf(Block block) =>
      parameterOverrides[block] ??
      (block == entry ? entryParameters : block.parameters);

  Iterable<Value> inputsOf(Value operation) =>
      operands[operation] ??
      switch (operation) {
        StorageAccess(:final inputs) => inputs,
        DoubleBits(:final operand) => [operand],
        TypeReference(:final operand) => [operand],
        ReferenceEquality(:final left, :final right) => [left, right],
        NativeInvocation(:final inputs) => inputs,
        Instruction() => operation.inputs,
        _ => throw ArgumentError('Expected a selected operation.'),
      };

  ValueType typeOf(Value value) =>
      resultTypes[value] ??
      (stackCells.contains(value)
          ? (value.type as CellType).content
          : value.type);

  List<Value> argumentsOf(Jump edge) => edgeArguments[edge] ?? edge.arguments;

  /// Removes paths disproved by representation facts before selecting callees.
  void prune() {
    bool? known(Value value) {
      if (value case ScalarConstant(value: final bool result)) return result;
      if (value is TypeTest) {
        final result = switch (tests[value]) {
          TypeTestKind.constantTrue => true,
          TypeTestKind.constantFalse => false,
          _ => null,
        };
        return result == null ? null : result != value.negated;
      }
      return aliases.contains(value) ? known(inputsOf(value).single) : null;
    }

    final reached = <Block>{}, pending = [entry];
    while (pending.isNotEmpty) {
      final block = pending.removeLast();
      if (!reached.add(block)) continue;
      if (ends[block] case Branch(
        :final condition,
        :final ifTrue,
        :final ifFalse,
      )) {
        if (known(condition) case final result?) {
          ends[block] = result ? ifTrue : ifFalse;
        }
      }
      pending.addAll(successors(block).map((edge) => edge.target));
    }
    blocks.removeWhere((block) => !reached.contains(block));
    instructions.removeWhere((block, _) => !reached.contains(block));
    ends.removeWhere((block, _) => !reached.contains(block));
    final retained = instructions.values.expand((values) => values).toSet();
    invocations.removeWhere((value, _) => !retained.contains(value));
    boxes.removeWhere((value, _) => !retained.contains(value));
  }

  Iterable<Jump> successors(Block block) => switch (ends[block]!) {
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
    Invoke(:final onReturn, :final onThrow) => [?onReturn, onThrow],
    Throw(:final onThrow) ||
    ExhaustivenessFailure(:final onThrow) => [?onThrow],
    Await(:final onResume, :final onThrow) => [?onResume, ?onThrow],
    Yield(:final onResume, :final onCancel) => [onResume, ?onCancel],
    YieldStream(:final onResume, :final onCancel, :final onThrow) => [
      onResume,
      onCancel,
      ?onThrow,
    ],
    Return() || Unreachable() => const [],
  };
}
