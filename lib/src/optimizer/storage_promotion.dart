import 'package:dartc/ir.dart';

import 'flow_state.dart';
import 'flow_value.dart';
import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Carries proven stored values on CFG edges instead of reading their container.
///
/// The shared solver supplies values and state. This pass reconstructs their SSA
/// joins; writes, lazy reads and opaque effects remain explicit proof boundaries.
final class const ProgramStoragePromotion() extends ProgramPass {
  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in facts.program.functions) {
      final rewritten = facts.definitions.contains(function.target)
          ? _Promotion(facts, function).run()
          : function;
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            facts.program.classes,
            functions,
            globals: facts.program.globals,
            externals: facts.program.externals,
          )
        : facts.program;
  }
}

typedef _Access = ({Instruction read, Value? receiver, Value? offset});
typedef _Entry = (Block, Object, Value?, Value?, ValueType);

final class _Promotion(
  final ProgramFlowFacts facts,
  final IrFunction function,
) {
  late final dominance = ValueDominance(function);
  late final activations = facts.activationsOf(function.target).toList();
  late final incoming = <Block, List<Jump>>{
    for (final block in function.blocks) block: [],
  };
  final owners = <Jump, Set<Block>>{};
  final cache = <_Entry, Value>{};
  final phis = <BlockParameter, ({Block block, Map<Jump, Value> incoming})>{};
  final replacements = <Value, Value>{};

  this {
    for (final block in function.blocks) {
      for (final edge in block.successors) {
        incoming[edge.target]!.add(edge);
        (owners[edge] ??= {}).add(block);
      }
    }
  }

  IrFunction run() {
    for (final block in function.blocks) {
      if (!facts.reachesBlock(block)) continue;
      final prior = <Instruction>[];
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        if (operation is LoadField ||
            operation is ReadCell ||
            operation is LoadGlobal ||
            operation is LoadObjectReference) {
          var receiver = operation.inputs.firstOrNull;
          while (receiver is TypeView || receiver is UncheckedCast) {
            receiver = (receiver as Instruction).inputs.single;
          }
          final offset = operation is LoadObjectReference
              ? operation.byteOffset
              : null;
          final access = (read: operation, receiver: receiver, offset: offset);
          // Access operands select storage facts; only emitted phi inputs need dominance.
          if (facts.canDiscard(operation) &&
              prior.every((instruction) => _preserves(access, instruction))) {
            final before = cache.keys.toSet();
            final value = _atEntry(access, block);
            if (value != null) {
              replacements[operation] = value;
            } else {
              for (final key
                  in cache.keys
                      .where((key) => !before.contains(key))
                      .toList()) {
                phis.remove(cache.remove(key));
              }
            }
          }
        }
        prior.add(operation);
      }
    }
    return replacements.isEmpty
        ? function
        : FunctionRewrite(
            function,
            replacements: replacements,
            phis: phis,
            discardable: replacements.keys.cast<Instruction>().toSet(),
          ).run();
  }

  Value? _atEntry(_Access access, Block block) {
    final key = (
      block,
      _slot(access.read),
      access.receiver,
      access.offset,
      access.read.type,
    );
    if (cache.containsKey(key)) return cache[key];
    if (block == function.entry || incoming[block]!.isEmpty) return null;
    final phi = blockParameters([access.read.type]).single;
    final arguments = <Jump, Value>{};
    cache[key] = phi;
    phis[phi] = (block: block, incoming: arguments);
    for (final edge in incoming[block]!) {
      if (!facts.reachesEdge(edge)) return null;
      Value? argument(Value? value) {
        final index = value is BlockParameter
            ? block.parameters.indexOf(value)
            : -1;
        return index < 0 ? value : edge.arguments[index];
      }

      final value = _onEdge((
        read: access.read,
        receiver: argument(access.receiver),
        offset: argument(access.offset),
      ), edge);
      if (value == null) return null;
      arguments[edge] = value;
    }
    return phi;
  }

  Value? _onEdge(_Access access, Jump edge) {
    final values = <(Object, FlowValue)>[];
    for (final activation in activations) {
      if (!facts.reachesEdge(edge, activation: activation)) continue;
      final state = facts.edgeStateOf(edge, activation: activation)!;
      final value = _bound(state, access, activation);
      if (value == null || value.isBottom) return null;
      values.add((activation, value));
    }
    if (values.isEmpty) return null;
    final constant = values.first.$2.constant;
    if (constant != null &&
        access.read.type.accepts(constant.type) &&
        values.every(
          (entry) => entry.$2.constant?.structuralKey == constant.structuralKey,
        )) {
      return constant;
    }
    Set<Value>? sources;
    for (final (activation, value) in values) {
      final available = {
        for (final source in value.sources)
          if (identical(source.activation, activation) &&
              access.read.type.accepts(source.value.type) &&
              dominance.onEdge(source.value, edge))
            source.value,
      };
      sources = sources == null ? available : sources.intersection(available);
    }
    if (sources!.isNotEmpty) return sources.first;
    final predecessors = owners[edge]!;
    if (predecessors.length != 1) return null;
    final block = predecessors.single;
    for (final operation in [
      ...block.instructions,
      if (block.end case Invoke(:final operation)) operation,
    ]) {
      if (!_preserves(access, operation)) return null;
    }
    return _atEntry(access, block);
  }

  FlowValue? _bound(FlowState state, _Access access, Object activation) =>
      state.boundValueOf(access.read, [
        if (access.receiver case final receiver?)
          facts.valueOf(receiver, activation: activation),
        if (access.offset case final offset?)
          facts.valueOf(offset, activation: activation),
      ]);

  bool _preserves(_Access access, Instruction operation) {
    if (!facts.effectsOf(operation).contains(Effect.writesStorage)) return true;
    final read = access.read;
    if (operation is StoreGlobal &&
        (read is! LoadGlobal || read.global != operation.global)) {
      return true;
    }
    if (operation is StoreField &&
        (read is! LoadField || read.field != operation.field)) {
      return true;
    }
    if (operation is WriteCell && read is! ReadCell) return true;
    final written = switch (operation) {
      StoreField(:final receiver) => receiver,
      WriteCell(:final cell) => cell,
      StoreObjectReference(:final object) ||
      StoreObjectData(:final object) => object,
      _ => null,
    };
    for (final activation in activations) {
      final point = facts.pointStateOf(operation, activation: activation);
      if (point == null) continue;
      if (written != null &&
          access.receiver != null &&
          _disjoint(
            facts.valueOf(written, activation: activation),
            facts.valueOf(access.receiver!, activation: activation),
          )) {
        continue;
      }
      final before = _bound(point.before, access, activation);
      if (before == null || before.isBottom) return false;
      for (final state in [?point.normal, ?point.exceptional]) {
        final after = _bound(state, access, activation);
        if (after == null || after.isBottom) return false;
        if (before.constant case final constant?
            when after.constant?.structuralKey == constant.structuralKey) {
          continue;
        }
        if (!before.sources.any(after.sources.contains)) return false;
      }
    }
    return true;
  }
}

Object _slot(Instruction read) => switch (read) {
  LoadGlobal(:final global) => global,
  LoadField(:final field) => field,
  ReadCell() => _cell,
  LoadObjectReference() => _payload,
  _ => throw ArgumentError('Expected storage read.'),
};

final _cell = Object();
final _payload = Object();

bool _disjoint(FlowValue first, FlowValue second) =>
    first.unknownTypes.isEmpty &&
    second.unknownTypes.isEmpty &&
    !first.objects.any(second.objects.contains) &&
    !first.constants.any(
      (a) => second.constants.any((b) => a.structuralKey == b.structuralKey),
    );
