import 'package:dartc/ir.dart';

import 'program_flow.dart';

/// Follows exception-channel uses back through handlers and callable bodies.
/// Recording a trace on an Error is an ordinary storage effect, not this output.
Set<Throw> demandedTraces(ProgramFlowFacts facts) {
  final entries = {...facts.escapingThrows};
  final demanded = <Throw>{};
  final definitions = facts.definitions;
  final functions = facts.program.functions
      .where((f) => definitions.contains(f.target))
      .toList();
  if (!functions.any(
    (body) => body.blocks.any(
      (block) => switch (block.end) {
        Throw(isRecorded: true, stackTrace: != null) => true,
        _ => false,
      },
    ),
  )) {
    return demanded;
  }
  final bodies = {for (final body in functions) body.target: body};
  final pending = functions.toList(), queued = functions.toSet();
  void schedule(IrFunction body) {
    if (queued.add(body)) pending.add(body);
  }

  while (pending.isNotEmpty) {
    final body = pending.removeLast();
    queued.remove(body);
    late final liveness = ValueLiveness(
      body.blocks,
      body.entry,
      (b) => b.parameters,
      (b) => [
        ...b.instructions,
        if (b.end case Invoke(:final operation)) operation,
      ],
      (b) => switch (b.end) {
        final Throw end when end.isRecorded && !demanded.contains(end) =>
          Throw.recorded(end.exception, null, onThrow: end.onThrow),
        final end => end,
      },
      (edge) => edge.arguments,
      (v) => (v as Instruction).inputs,
      {},
      introduced: {
        for (final block in body.blocks)
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ])
            if (facts.canDiscard(operation)) operation,
      },
    );
    bool observes(Jump? handler) => handler == null
        ? entries.contains(body.target)
        : liveness.liveParameters[handler.target]!.any(
            (i) => handler.arguments[i] == UnwindValue.stackTrace,
          );
    for (final b in body.blocks) {
      if (!facts.reachesBlock(b)) continue;
      if (b.end case final Throw throwing
          when throwing.isRecorded &&
              throwing.stackTrace != null &&
              observes(throwing.onThrow)) {
        if (demanded.add(throwing)) schedule(body);
      }
      for (final (op, handler) in [
        for (final op in b.instructions) (op, null),
        if (b.end case Invoke(:final operation, :final onThrow))
          (operation, onThrow),
      ]) {
        if (!facts.reachesOperation(op) ||
            !facts.exitsOf(op).exceptional ||
            !observes(handler)) {
          continue;
        }
        for (final target in facts.unwindingTargetsOf(op)) {
          if (bodies[target] case final callee? when entries.add(target)) {
            schedule(callee);
          }
        }
      }
    }
  }
  return demanded;
}
