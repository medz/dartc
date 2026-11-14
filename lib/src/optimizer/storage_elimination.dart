import 'package:dartc/ir.dart';

import 'flow_state.dart';
import 'flow_value.dart';
import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Removes storage writes whose values, binding checks and lifetimes are unused.
///
/// Demands come from executable operations after value and control-flow rewrites.
/// A new graph must be solved before another elimination pass consumes its facts.
final class const ProgramStorageElimination() implements ProgramPass {
  @override
  bool get repeatUntilStable => true;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    final program = facts.program;
    facts.checkProgram(program);
    final reads = <InstanceField, FlowValue>{};
    final globals = <GlobalVariable>{};
    var cells = const FlowValue.bottom();
    var payloads = const FlowValue.bottom();
    var visible = const FlowValue.bottom();
    var lifetimes = const FlowValue.bottom();
    final points = <Instruction, List<FlowState>>{};
    final bodies = <IrFunction>[];
    final conditional = <InstanceField, Set<InstanceField>>{
      for (final declaration in program.classes)
        for (final entry in declaration.ephemerons.entries) ...{
          entry.key: {entry.key, entry.value},
          entry.value: {entry.key, entry.value},
        },
    };
    final weak = {
      for (final declaration in program.classes) ...declaration.weakFields,
    };

    void readField(InstanceField field, FlowValue receiver) {
      reads[field] = (reads[field] ?? const FlowValue.bottom()).join(receiver);
    }

    for (final target in facts.escapingReturns) {
      visible = visible.join(facts.returnedBy(target));
    }
    for (final body in program.functions) {
      if (!facts.definitions.contains(body.target)) continue;
      bodies.add(body);
      for (final block in body.blocks) {
        if (!facts.reachesBlock(block)) continue;
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          final point = facts.pointStateOf(operation);
          if (point == null) continue;
          final states = points[operation] = [
            point.before,
            ?point.normal,
            ?point.exceptional,
          ];
          for (final state in states) {
            visible = visible.join(state.exposedValues);
          }
          switch (operation) {
            case LoadGlobal(:final global):
              globals.add(global);
            case StoreGlobal(:final global)
                when global.isFinal && facts.exitsOf(operation).exceptional:
              globals.add(global);
            case ReadCell(:final cell) || CopyCell(:final cell):
              cells = cells.join(facts.valueOf(cell));
            case WriteCell(:final cell)
                when (cell.type as CellType).isFinal &&
                    facts.exitsOf(operation).exceptional:
              cells = cells.join(facts.valueOf(cell));
            case LoadField(:final field, :final receiver):
              final owners = facts.valueOf(receiver);
              readField(field, owners);
              if (weak.contains(field)) {
                lifetimes = lifetimes.join(facts.valueOf(operation));
              }
              if (conditional[field] case final pair?) {
                for (final state in states) {
                  for (final object in owners.objects) {
                    for (final related in pair) {
                      lifetimes = lifetimes.join(
                        state.storedValue(object, related),
                      );
                    }
                  }
                }
                for (final constant
                    in owners.constants.whereType<ObjectConstant>()) {
                  for (final related in pair) {
                    if (constant.fields[related] case final value?) {
                      lifetimes = lifetimes.join(.constant(value));
                    }
                  }
                }
                if (owners.unknownTypes.isNotEmpty) {
                  for (final related in pair) {
                    lifetimes = lifetimes.join(.unknown(related.type));
                  }
                }
              }
            case StoreField(:final field, :final receiver)
                when field.isLate &&
                    field.isFinal &&
                    facts.exitsOf(operation).exceptional:
              readField(field, facts.valueOf(receiver));
            case KeepAlive(:final value):
              for (final state in states) {
                lifetimes = lifetimes.join(
                  state.reachableValues([facts.valueOf(value)]),
                );
              }
            case LoadObjectReference(:final object) ||
                LoadObjectData(:final object):
              payloads = payloads.join(facts.valueOf(object));
            case ReferenceAddress(:final object):
              visible = visible.join(facts.valueOf(operation));
              lifetimes = lifetimes.join(facts.valueOf(object));
            default:
              break;
          }
        }
        // Exceptional payloads and suspended protocols can expose their objects.
        final boundary = switch (block.end) {
          Throw(:final exception) => exception,
          Await(:final operand) => operand,
          Yield(:final value) => value,
          YieldStream(:final stream) => stream,
          _ => null,
        };
        if (boundary != null) visible = visible.join(facts.valueOf(boundary));
      }
    }

    for (final states in points.values) {
      for (final state in states) {
        visible = visible.join(state.exposedFrom([visible]));
      }
    }

    var changed = false;
    final rewritten = <FunctionTarget, IrFunction>{};
    for (final body in bodies) {
      final discardable = <Instruction>{};
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          final states = points[operation];
          if (states == null) continue;
          final exits = facts.exitsOf(operation);
          if (!exits.normal || exits.exceptional) continue;
          final (
            FlowValue receiver,
            Value? stored,
            bool demanded,
          ) = switch (operation) {
            StoreGlobal(:final global, :final value) => (
              const FlowValue.bottom(),
              value,
              globals.contains(global),
            ),
            StoreField(:final field, :final receiver, :final value) => (
              facts.valueOf(receiver),
              value,
              _overlaps(
                facts.valueOf(receiver),
                reads[field] ?? const .bottom(),
              ),
            ),
            WriteCell(:final cell, :final value) => (
              facts.valueOf(cell),
              value,
              _overlaps(facts.valueOf(cell), cells),
            ),
            StoreObjectReference(
              :final object,
              :final byteOffset,
              :final value,
            ) =>
              (
                facts.valueOf(object),
                value,
                _overlaps(facts.valueOf(object), payloads) ||
                    facts.pointStateOf(operation)!.normal!.boundValueOf(
                          LoadObjectReference(object, byteOffset),
                          [facts.valueOf(object), facts.valueOf(byteOffset)],
                        ) ==
                        null,
              ),
            _ => (const FlowValue.bottom(), null, true),
          };
          if (stored == null ||
              demanded ||
              receiver.unknownTypes.isNotEmpty ||
              _overlaps(receiver, visible)) {
            continue;
          }
          var references = facts.valueOf(stored);
          for (final state in states) {
            references = references.join(state.reachableValues([references]));
          }
          if (_retains(references, lifetimes)) continue;
          discardable.add(operation);
        }
      }
      if (discardable.isEmpty) continue;
      final result = FunctionRewrite(body, discardable: discardable).run();
      changed |= !identical(body, result);
      rewritten[body.target] = result;
    }
    return changed
        ? IrProgram(
            program.classes,
            [
              for (final body in program.functions)
                rewritten[body.target] ?? body,
            ],
            globals: program.globals,
            externals: program.externals,
          )
        : program;
  }
}

bool _overlaps(FlowValue a, FlowValue b) {
  if (a.isBottom || b.isBottom) return false;
  if (a.objects.any(b.objects.contains)) return true;
  final constants = a.constants.map((c) => c.structuralKey).toSet();
  if (b.constants.any((c) => constants.contains(c.structuralKey))) return true;
  bool admits(ValueType bound, ValueType actual) => actual is ClassType
      ? bound.mayHaveInstance(actual)
      : bound.freeTypeParameters.isNotEmpty ||
            actual.freeTypeParameters.isNotEmpty ||
            bound.accepts(actual);
  if (a.unknownTypes.isNotEmpty && b.unknownTypes.isNotEmpty) return true;
  return a.unknownTypes.any(
        (bound) => b.types.any((type) => admits(bound, type)),
      ) ||
      b.unknownTypes.any((bound) => a.types.any((type) => admits(bound, type)));
}

// Constants are immortal; scalar values cannot acquire a weak/finalizer identity.
bool _retains(FlowValue references, FlowValue lifetimes) {
  var mortal = const FlowValue.bottom();
  for (final object in references.objects) {
    mortal = mortal.join(.object(object));
  }
  for (final type in references.unknownTypes) {
    if ([
      ValueType.number.nullable,
      ValueType.string.nullable,
      ValueType.boolean.nullable,
    ].any((scalar) => scalar.accepts(type))) {
      continue;
    }
    mortal = mortal.join(.unknown(type));
  }
  return _overlaps(mortal, lifetimes);
}
