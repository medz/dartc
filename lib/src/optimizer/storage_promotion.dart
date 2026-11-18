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
  ProgramTransform bind() => ProgramTransform(
    run,
    normalize: (program) {
      final functions = [
        for (final function in program.functions) _LocalCells(function, program.executionShapes).run(),
      ];
      return functions.indexed.any(
            (entry) => !identical(entry.$2, program.functions[entry.$1]),
          )
          ? IrProgram(
              program.classes,
              functions,
              globals: program.globals,
              nativeBoundaries: program.nativeBoundaries,
              executionShapes: program.executionShapes,
              externals: program.externals,
            )
          : program;
    },
  );

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
            nativeBoundaries: facts.program.nativeBoundaries,
            executionShapes: facts.program.executionShapes,
            externals: facts.program.externals,
          )
        : facts.program;
  }
}

/// Promotes private cells whose complete set of uses is local reads and writes.
final class _LocalCells(final IrFunction function, final ExecutionShapes? executionShapes) {
  final incoming = <Block, List<Jump>>{};
  final owners = <Jump, Block>{};
  final aliases = <Value, NewCell>{};
  final cells = <NewCell>{};
  final entries = <(Block, NewCell), Value>{};
  final phis = <BlockParameter, ({Block block, Map<Jump, Value> incoming})>{};

  IrFunction run() {
    if (function.bodyKind != .synchronous) return function;
    final operations = [
      for (final block in function.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    ];
    for (final operation in operations) {
      if (operation case NewCell(
        type: CellType(isLate: false, isFinal: false),
        initial: Value(),
      )) {
        cells.add(operation);
        aliases[operation] = operation;
      }
    }
    if (cells.isEmpty) return function;
    for (final block in function.blocks) {
      for (final edge in block.successors) {
        if (owners[edge] case final owner? when owner != block) return function;
        owners[edge] = block;
        (incoming[edge.target] ??= []).add(edge);
      }
    }
    bool changed;
    do {
      changed = false;
      for (final block in function.blocks) {
        final edges = incoming[block];
        if (edges == null || edges.length != 1) continue;
        for (final (index, parameter) in block.parameters.indexed) {
          final cell = aliases[edges.single.arguments[index]];
          if (cell != null && aliases[parameter] != cell) {
            aliases[parameter] = cell;
            changed = true;
          }
        }
      }
    } while (changed);
    for (final operation in operations) {
      for (final input in operation.inputs) {
        final cell = aliases[input];
        if (cell != null && operation is! ReadCell && operation is! WriteCell) {
          cells.remove(cell);
        }
      }
    }
    for (final block in function.blocks) {
      final end = block.end;
      for (final input in switch (end) {
        Return(:final value) => [?value],
        Throw(:final exception, :final stackTrace) => [exception, ?stackTrace],
        _ => const <Value>[],
      }) {
        cells.remove(aliases[input]);
      }
      for (final edge in block.successors) {
        for (final (index, argument) in edge.arguments.indexed) {
          final cell = aliases[argument];
          if (cell != null && aliases[edge.target.parameters[index]] != cell) {
            cells.remove(cell);
          }
        }
      }
    }
    if (cells.isEmpty) return function;
    final replacements = <Value, Value>{};
    final removed = <Instruction>{...cells};
    for (final block in function.blocks) {
      final current = <NewCell, Value>{};
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        if (operation is NewCell && cells.contains(operation)) {
          current[operation] = operation.initial!;
        } else if (operation is ReadCell || operation is WriteCell) {
          final cell = aliases[operation.inputs.first];
          if (!cells.contains(cell)) continue;
          removed.add(operation);
          if (operation is WriteCell) {
            current[cell!] = operation.value;
          } else {
            replacements[operation] = current[cell] ?? atEntry(block, cell!);
          }
        }
      }
    }
    return FunctionRewrite(
      function,
      executionShapes: executionShapes,
      replacements: replacements,
      phis: phis,
      discardable: removed,
    ).run();
  }

  Value atEntry(Block block, NewCell cell) {
    final key = (block, cell);
    if (entries[key] case final value?) return value;
    final parameter = blockParameters([(cell.type as CellType).content]).single;
    entries[key] = parameter;
    final values = <Jump, Value>{};
    phis[parameter] = (block: block, incoming: values);
    for (final edge in incoming[block] ?? const <Jump>[]) {
      final owner = owners[edge]!;
      Value? value;
      for (final operation in [
        ...owner.instructions,
        if (owner.end case Invoke(:final operation)) operation,
      ]) {
        if (identical(operation, cell)) value = cell.initial!;
        if (operation is WriteCell && aliases[operation.cell] == cell) {
          value = operation.value;
        }
      }
      values[edge] = value ?? atEntry(owner, cell);
    }
    return parameter;
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
            executionShapes: facts.program.executionShapes,
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
      final value = _bound(state, access, activation, edge: edge);
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
    // Unwind values are produced on this edge, after its predecessor's operations.
    if (access.receiver is UnwindValue || access.offset is UnwindValue) {
      return null;
    }
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

  FlowValue? _bound(
    FlowState state,
    _Access access,
    Object activation, {
    Jump? edge,
  }) => state.boundValueOf(access.read, [
    if (access.receiver case final receiver?)
      _value(receiver, activation, edge),
    if (access.offset case final offset?) _value(offset, activation, edge),
  ]);

  FlowValue _value(Value value, Object activation, Jump? edge) {
    if (value is! UnwindValue) {
      return facts.valueOf(value, activation: activation);
    }
    if (edge == null) {
      throw StateError('An unwind value requires its exceptional edge.');
    }
    var result = const FlowValue.bottom();
    for (final block in owners[edge]!) {
      if (!facts.reachesBlock(block, activation: activation)) continue;
      final FlowValue exception, trace;
      switch (block.end) {
        case Invoke(:final operation, :final onThrow)
            when identical(onThrow, edge):
          final failure = facts.failureOf(operation, activation: activation);
          exception = failure.exception;
          trace = failure.stackTrace;
        case Throw(exception: final operand, :final stackTrace, :final onThrow)
            when identical(onThrow, edge):
          exception = facts.valueOf(operand, activation: activation);
          trace = stackTrace == null
              ? FlowValue.unknown(.stackTrace)
              : facts.valueOf(stackTrace, activation: activation);
        case ExhaustivenessFailure(:final onThrow)
            when identical(onThrow, edge):
          exception = FlowValue.unknown(.object);
          trace = FlowValue.unknown(.stackTrace);
        default:
          throw StateError(
            'An unwind operand requires an exceptional predecessor.',
          );
      }
      result = result.join(value == UnwindValue.exception ? exception : trace);
    }
    return result;
  }

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
