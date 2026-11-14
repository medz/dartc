import 'package:dartc/ir.dart';

import 'call_type_flow.dart';

/// Inlines small direct callees in the functions selected by [facts].
///
/// A single pass visits original call sites, without recursively expanding new
/// calls. Cost counts copied operations, parameter views and return adaptation;
/// [maxCallerGrowth] also charges exceptional continuations. Both limits must
/// be nonnegative, and zero disables expansion.
///
/// Candidates are synchronous, nongeneric, single-block bodies ending in a
/// return, without lexical captures, constructor-only writes or callback entries
/// whose native addresses belong to the original instruction site. Call arguments
/// still execute in order, including unused arguments with effects. Throwing
/// operations keep the call site's exceptional continuation. Cleanup removes
/// constant branches, unreachable blocks and unused operations without effects.
///
/// Unchanged input is returned by identity. Otherwise only changed functions
/// are copied, and the new verified program invalidates prior call, reachability
/// and preparation facts. Reanalyze it from the actual roots and supplemental
/// facts, never from the old retained definitions.
IrProgram inlineDirectCalls(
  IrProgram program,
  CallTypeFacts facts, {
  int maxCalleeCost = 12,
  int maxCallerGrowth = 64,
}) {
  facts.checkProgram(program);
  RangeError.checkNotNegative(maxCalleeCost, 'maxCalleeCost');
  RangeError.checkNotNegative(maxCallerGrowth, 'maxCallerGrowth');
  if (maxCalleeCost == 0 || maxCallerGrowth == 0) return program;
  var changed = false;
  final functions = <IrFunction>[];
  for (final function in program.functions) {
    final sites = <DirectCall, ({IrFunction body, Jump? handler})>{};
    var budget = maxCallerGrowth;
    if (facts.definitions.contains(function.target) &&
        function.bodyKind == .synchronous) {
      for (final block in function.blocks) {
        for (final (operation, handler) in [
          for (final operation in block.instructions) (operation, null),
          if (block.end case Invoke(:final operation, :final onThrow))
            (operation, onThrow),
        ]) {
          if (operation is! DirectCall || operation.target == function.target) {
            continue;
          }
          final body = program.implementationOf(operation.target);
          // shortcut: single-block monomorphic bodies, expand with CFG and binder substitution.
          if (body is! IrFunction ||
              body.bodyKind != .synchronous ||
              body.blocks.length != 1 ||
              body.entry.end is! Return ||
              body.target.kind == .initializer ||
              body.target.enclosing != null ||
              body.target.awaiterCapture != null ||
              body.target.typeParameters.isNotEmpty ||
              (body.target.owner?.typeParameters.isNotEmpty ?? false) ||
              body.closures.isNotEmpty ||
              body.entry.instructions.any(
                (op) => op.type == .never || op is NativeCallbackEntry,
              )) {
            continue;
          }
          final cost =
              body.entry.instructions.length + body.entry.parameters.length + 1;
          final growth = cost + (handler == null ? 0 : 2 * cost);
          if (cost > maxCalleeCost || growth > budget) continue;
          budget -= growth;
          sites[operation] = (body: body, handler: handler);
        }
      }
    }
    if (sites.isEmpty) {
      functions.add(function);
    } else {
      functions.add(_inline(function, sites));
      changed = true;
    }
  }
  return changed
      ? IrProgram(
          program.classes,
          functions,
          globals: program.globals,
          externals: program.externals,
        )
      : program;
}

IrFunction _inline(
  IrFunction function,
  Map<DirectCall, ({IrFunction body, Jump? handler})> sites,
) {
  final blocks = <Block, Block>{
    for (final block in function.blocks)
      block: Block(block.parameters.map((p) => p.type)),
  };
  final values = <Value, Value>{
    for (final block in function.blocks)
      for (final (i, parameter) in block.parameters.indexed)
        parameter: blocks[block]!.parameters[i],
  };
  final instructions = <Block, List<Instruction>>{};
  final ends = <Block, Terminator>{};
  final locations = <Object, SourceLocation>{};
  final expansions = <DirectCall, List<Instruction>>{};
  final continuations = <Instruction, Block>{};
  late Value Function(Value) value;

  void locate(
    Object source,
    Object copy,
    IrFunction owner, [
    Object? fallback,
  ]) {
    final location =
        owner.sourceLocations[source] ?? function.sourceLocations[fallback];
    if (location != null) locations[copy] = location;
  }

  Value expand(DirectCall call) {
    final site = sites[call]!;
    final body = site.body;
    final output = expansions[call] = [];
    final locals = <Value, Value>{};
    Value read(Value operand) =>
        operand is Constant ? operand : locals[operand]!;
    Value append(Instruction instruction, Object source) {
      output.add(instruction);
      locate(source, instruction, body, call);
      if (site.handler != null && instruction.mayThrow) {
        final next = continuations[instruction] = Block([instruction.type]);
        return next.parameters.single;
      }
      return instruction;
    }

    for (final (i, parameter) in body.entry.parameters.indexed) {
      final argument = value(call.inputs[i]);
      locals[parameter] = argument.type == parameter.type
          ? argument
          : append(TypeView(argument, parameter.type), parameter);
    }
    for (final operation in body.entry.instructions) {
      locals[operation] = append(operation.mapInputs(read), operation);
    }
    final returned = (body.entry.end as Return).value;
    final result = returned == null
        ? const Constant.nullValue()
        : read(returned);
    return result.type == call.type
        ? result
        : append(TypeView(result, call.type), body.entry);
  }

  value = (original) {
    if (original is Constant || original is UnwindValue) return original;
    if (values[original] case final known?) return known;
    final Value result;
    if (original is DirectCall && sites.containsKey(original)) {
      result = expand(original);
    } else if (original is Instruction) {
      result = original.mapInputs(value);
      locate(original, result, function);
    } else if (original is TestedValue) {
      result = (value(original.test) as TypeTest).refinement(original.outcome)!;
    } else {
      throw StateError('Unexpected value in a synchronous IR graph.');
    }
    return values[original] = result;
  };
  Jump jump(Jump edge) => Jump(blocks[edge.target]!, edge.arguments.map(value));
  Terminator end(Terminator original) => switch (original) {
    Return(value: final returned) => Return(
      returned == null ? null : value(returned),
    ),
    final Jump edge => jump(edge),
    Branch(:final condition, :final ifTrue, :final ifFalse) => switch (value(
      condition,
    )) {
      ScalarConstant(value: final bool condition) => jump(
        condition ? ifTrue : ifFalse,
      ),
      final condition => Branch(condition, jump(ifTrue), jump(ifFalse)),
    },
    Invoke(:final operation, :final onReturn, :final onThrow) => Invoke(
      value(operation) as Instruction,
      onReturn: onReturn == null ? null : jump(onReturn),
      onThrow: jump(onThrow),
    ),
    Throw(:final exception, :final stackTrace, :final onThrow) => Throw(
      value(exception),
      stackTrace: stackTrace == null ? null : value(stackTrace),
      onThrow: onThrow == null ? null : jump(onThrow),
    ),
    ExhaustivenessFailure(:final onThrow) => ExhaustivenessFailure(
      onThrow == null ? null : jump(onThrow),
    ),
    Unreachable(:final cause) => Unreachable(value(cause)),
    Await() ||
    Yield() ||
    YieldStream() => throw StateError('A synchronous IR graph cannot suspend.'),
  };

  for (final original in function.blocks) {
    var current = blocks[original]!;
    instructions[current] = [];
    void emit(Instruction operation) {
      if (operation is DirectCall && sites.containsKey(operation)) {
        value(operation);
        for (final copied in expansions[operation]!) {
          if (continuations[copied] case final next?) {
            ends[current] = Invoke(
              copied,
              onReturn: Jump(next, [copied]),
              onThrow: jump(sites[operation]!.handler!),
            );
            current = next;
            instructions[current] = [];
          } else {
            instructions[current]!.add(copied);
          }
        }
      } else {
        instructions[current]!.add(value(operation) as Instruction);
      }
    }

    for (final operation in original.instructions) {
      emit(operation);
    }
    final terminal = original.end;
    if (terminal is Invoke && sites.containsKey(terminal.operation)) {
      emit(terminal.operation);
      ends[current] = jump(terminal.onReturn!);
    } else {
      ends[current] = end(terminal);
    }
    locate(original, current, function);
  }

  final reachable = <Block>{}, pending = [blocks[function.entry]!];
  while (pending.isNotEmpty) {
    final block = pending.removeLast();
    if (reachable.add(block)) {
      pending.addAll(ends[block]!.successors.map((edge) => edge.target));
    }
  }
  final used = <Value>{};
  void retain(Value operand) {
    if (!used.add(operand)) return;
    if (operand is Instruction) operand.inputs.forEach(retain);
    if (operand is TestedValue) retain(operand.test);
  }

  for (final block in reachable) {
    for (final operation in instructions[block]!) {
      if (operation.effects.isNotEmpty) retain(operation);
    }
    final terminal = ends[block]!;
    for (final edge in terminal.successors) {
      edge.arguments.forEach(retain);
    }
    switch (terminal) {
      case Return(:final value?):
        retain(value);
      case Branch(:final condition):
        retain(condition);
      case Invoke(:final operation):
        retain(operation);
      case Throw(:final exception, :final stackTrace):
        retain(exception);
        if (stackTrace != null) retain(stackTrace);
      case Unreachable(:final cause):
        retain(cause);
      default:
        break;
    }
  }
  final owned = <Object>{...reachable};
  for (final block in reachable) {
    for (final operation in instructions[block]!) {
      if (used.contains(operation)) {
        block.emit(operation);
        owned.add(operation);
      }
    }
    block.finish(ends[block]!);
    if (block.end case Invoke(:final operation)) owned.add(operation);
  }
  return IrFunction(
    function.target,
    reachable,
    defaults: function.defaults,
    sourceLocations: {
      for (final e in locations.entries)
        if (owned.contains(e.key)) e.key: e.value,
    },
  );
}
