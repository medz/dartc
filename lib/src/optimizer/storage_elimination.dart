import 'package:dartc/interop.dart';
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
final class const ProgramStorageElimination() extends ProgramPass {
  @override
  IrProgram run(ProgramFlowFacts facts) {
    final program = facts.program;
    final discardable = storageDiscardable(facts);
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      final rewritten = facts.definitions.contains(function.target)
          ? FunctionRewrite(function, discardable: discardable(function)).run()
          : function;
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
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
}

/// Shared storage and lifetime proofs for whole bodies and selected executions.
Set<Instruction> Function(IrFunction, {Set<Object>? activations})
storageDiscardable(ProgramFlowFacts facts) {
  final program = facts.program;
  facts.checkProgram(program);
  final reads = <InstanceField, FlowValue>{};
  final globals = <GlobalVariable>{};
  var cells = const FlowValue.bottom();
  var payloads = const FlowValue.bottom();
  var addressable = const FlowValue.bottom();
  var unknownReads = false;
  var visible = const FlowValue.bottom();
  var lifetimes = const FlowValue.bottom();
  var observations = const FlowValue.bottom();
  final markers = <KeepAlive, FlowValue>{};
  final points = <Instruction, List<FlowState>>{};
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

  FlowValue objectAddress(Value object, Value offset) {
    final owner = facts.valueOf(object);
    final offsets = facts.valueOf(offset).integers;
    var address = const FlowValue.bottom();
    for (final base in <Object>[...owner.objects, ...owner.constants]) {
      address = address.join(
        FlowValue.address(FlowAddress.ranged(base, offsets)),
      );
    }
    if (owner.unknownTypes.isNotEmpty || owner.addresses.isNotEmpty) {
      address = address.join(
        FlowValue.unknown(.integer).withReferences([owner]),
      );
    }
    return address;
  }

  void readNative(FlowValue address, NativeTypeRef storage, FlowState state) {
    address = state.resolveValue(address);
    payloads = payloads.join(address.references);
    unknownReads |= !state.containsNative(address, storage);
  }

  for (final target in facts.escapingReturns) {
    visible = visible.join(facts.returnedBy(target));
  }
  for (final body in program.functions) {
    if (!facts.definitions.contains(body.target)) continue;
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
          observations = observations.join(state.escapedValues);
        }
        // Weak registrations can be observed later by the collector.
        observations = observations.join(switch (operation) {
          LoadField(:final field) || StoreField(:final field)
              when weak.contains(field) || conditional.containsKey(field) =>
            operation.inputs.fold<FlowValue>(
              facts.valueOf(operation),
              (value, input) => value.join(facts.valueOf(input)),
            ),
          LoadNative(:final address) || StoreNative(:final address) =>
            point.before.resolveValue(facts.valueOf(address)).references,
          CopyNative() => operation.inputs.fold<FlowValue>(
            const .bottom(),
            (value, input) => value.join(
              point.before.resolveValue(facts.valueOf(input)).references,
            ),
          ),
          LoadObjectData(:final object) ||
          StoreObjectData(:final object) => facts.valueOf(object),
          _ => const .bottom(),
        });
        switch (operation) {
          case ReferenceAddress(:final object):
            addressable = addressable.join(facts.valueOf(object));
          case NativeAddress(:final view):
            addressable = addressable.join(facts.valueOf(view));
          case ReferenceFromAddress() || AllocatedObject():
            addressable = addressable.join(facts.valueOf(operation));
          case NativeView(address: final address?, copy: false):
            addressable = addressable
                .join(facts.valueOf(operation))
                .join(facts.valueOf(address).references);
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
              markers[operation] = (markers[operation] ?? const .bottom()).join(
                state.reachableValues([facts.valueOf(value)]),
              );
            }
          case LoadObjectReference(:final object):
            payloads = payloads.join(facts.valueOf(object));
          case LoadObjectData(
            :final object,
            :final byteOffset,
            :final nativeType,
          ):
            readNative(
              objectAddress(object, byteOffset),
              nativeType,
              point.before,
            );
          case LoadNative(:final address, :final nativeType):
            readNative(facts.valueOf(address), nativeType, point.before);
          case CopyNative(:final source, :final nativeType):
            readNative(facts.valueOf(source), nativeType, point.before);
          case StringLength(:final string) || StringCodeUnitAt(:final string):
            payloads = payloads.join(facts.valueOf(string));
          case StringConcat(:final left, :final right):
            payloads = payloads
                .join(facts.valueOf(left))
                .join(facts.valueOf(right));
          case StringFromCharCodes(:final codes):
            payloads = payloads.join(facts.valueOf(codes));
          default:
            break;
        }
      }
      // Uncaught payloads and suspended protocols can expose their objects.
      final boundary = switch (block.end) {
        Throw(:final exception, onThrow: null) => exception,
        Await(:final operand) => operand,
        Yield(:final value) => value,
        YieldStream(:final stream) => stream,
        _ => null,
      };
      if (boundary != null) {
        visible = visible.join(facts.valueOf(boundary));
        observations = observations.join(facts.valueOf(boundary));
      }
    }
  }

  // Foreign addresses can alias exposed storage, not private Dart objects.
  if (unknownReads) payloads = payloads.join(addressable);
  for (final states in points.values) {
    for (final state in states) {
      visible = visible.join(state.exposedFrom([visible]));
    }
  }
  while (true) {
    final before = observations;
    for (final states in points.values) {
      for (final state in states) {
        observations = observations.join(state.reachableValues([observations]));
      }
    }
    if (observations == before) break;
  }
  observations = _mortal(observations);
  lifetimes = _mortal(lifetimes.join(observations));
  final unusedMarkers = <KeepAlive>{};
  for (final MapEntry(key: marker, value: references) in markers.entries) {
    final mortal = _mortal(references);
    if (mortal.unknownTypes.isEmpty &&
        !_overlaps(facts, mortal, observations)) {
      unusedMarkers.add(marker);
    } else {
      lifetimes = lifetimes.join(references);
    }
  }

  (FlowValue, FlowValue?, bool) rawWrite(
    Instruction operation,
    FlowValue address,
    NativeTypeRef storage,
    FlowValue stored, {
    FlowValue? source,
  }) {
    final state = points[operation]!.first;
    address = state.resolveValue(address);
    if (source != null) source = state.resolveValue(source);
    if (!state.containsNative(address, storage) ||
        address.addresses.any((pointer) => pointer.base is! FlowObject) ||
        source != null && !state.containsNative(source, storage)) {
      return (const FlowValue.bottom(), null, true);
    }
    final owners = address.references;
    return (
      owners,
      source == null ? stored : state.nativeReferences(source),
      _overlaps(facts, owners, payloads) ||
          reads.values.any((receivers) => _overlaps(facts, owners, receivers)),
    );
  }

  return (body, {activations}) {
    if (!identical(program.implementationOf(body.target), body)) {
      throw ArgumentError('Storage proofs require the analyzed function.');
    }
    final discardable = _restoredGlobalWrites(
      facts,
      body,
      points,
      lifetimes,
      activations: activations,
    );
    for (final block in body.blocks) {
      for (final operation in [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        final states = points[operation];
        if (states == null) continue;
        if (unusedMarkers.contains(operation)) {
          discardable.add(operation);
          continue;
        }
        final exits = facts.exitsOf(operation);
        if (!exits.normal || exits.exceptional) continue;
        final (
          FlowValue receiver,
          FlowValue? stored,
          bool demanded,
        ) = switch (operation) {
          StoreGlobal(:final global, :final value) => (
            const FlowValue.bottom(),
            facts.valueOf(value),
            globals.contains(global),
          ),
          StoreField(:final field, :final receiver, :final value) => (
            facts.valueOf(receiver),
            facts.valueOf(value),
            _overlaps(facts, facts.valueOf(receiver), payloads) ||
                _overlaps(
                  facts,
                  facts.valueOf(receiver),
                  reads[field] ?? const .bottom(),
                ),
          ),
          WriteCell(:final cell, :final value) => (
            facts.valueOf(cell),
            facts.valueOf(value),
            _overlaps(facts, facts.valueOf(cell), cells),
          ),
          StoreObjectReference(
            :final object,
            :final byteOffset,
            :final value,
          ) =>
            (
              facts.valueOf(object),
              facts.valueOf(value),
              _overlaps(facts, facts.valueOf(object), payloads) ||
                  facts.pointStateOf(operation)!.normal!.boundValueOf(
                        LoadObjectReference(object, byteOffset),
                        [facts.valueOf(object), facts.valueOf(byteOffset)],
                      ) ==
                      null,
            ),
          StoreNative(:final address, :final nativeType, :final value) =>
            rawWrite(
              operation,
              facts.valueOf(address),
              nativeType,
              facts.valueOf(value),
            ),
          StoreObjectData(
            :final object,
            :final byteOffset,
            :final nativeType,
            :final value,
          ) =>
            rawWrite(
              operation,
              objectAddress(object, byteOffset),
              nativeType,
              facts.valueOf(value),
            ),
          CopyNative(:final destination, :final source, :final nativeType) =>
            rawWrite(
              operation,
              facts.valueOf(destination),
              nativeType,
              const FlowValue.bottom(),
              source: facts.valueOf(source),
            ),
          _ => (const FlowValue.bottom(), null, true),
        };
        if (stored == null ||
            demanded ||
            receiver.unknownTypes.isNotEmpty ||
            _overlaps(facts, receiver, visible)) {
          continue;
        }
        var references = stored;
        for (final state in states) {
          references = references.join(state.reachableValues([references]));
        }
        if (_retains(facts, references, lifetimes)) continue;
        discardable.add(operation);
      }
    }
    return discardable;
  };
}

/// Temporary writes can disappear when every exit restores unobserved storage.
Set<Instruction> _restoredGlobalWrites(
  ProgramFlowFacts facts,
  IrFunction function,
  Map<Instruction, List<FlowState>> points,
  FlowValue lifetimes, {
  Set<Object>? activations,
}) {
  if (function.bodyKind != .synchronous) return {};
  final executions =
      activations ?? facts.activationsOf(function.target).toSet();
  if (executions.isEmpty) return {};
  final stores = <GlobalVariable, List<StoreGlobal>>{};
  for (final block in function.blocks) {
    for (final operation in [
      ...block.instructions,
      if (block.end case Invoke(:final operation)) operation,
    ]) {
      if (operation is StoreGlobal &&
          !operation.global.isFinal &&
          executions.any(
            (a) => facts.reachesOperation(operation, activation: a),
          )) {
        (stores[operation.global] ??= []).add(operation);
      }
    }
  }
  if (stores.isEmpty) return {};
  final dominance = ValueDominance(function);
  final discardable = <Instruction>{};
  for (final MapEntry(key: global, value: writes) in stores.entries) {
    final first = writes
        .where(
          (write) => writes.every(
            (other) =>
                identical(write, other) || dominance.before(write, other),
          ),
        )
        .firstOrNull;
    if (first == null) continue;
    if (writes.any((write) {
      var references = facts.valueOf(write.value);
      for (final state in points[write] ?? const <FlowState>[]) {
        references = references.join(state.reachableValues([references]));
      }
      return _retains(facts, references, lifetimes);
    })) {
      continue;
    }
    final read = LoadGlobal(global);
    bool restored(Object activation) {
      final point = facts.pointStateOf(first, activation: activation);
      if (point == null) return true;
      final before = point.before.boundValueOf(read, const []);
      if (before == null || before.isBottom) return false;
      final incoming = <Block, bool>{function.entry: false};
      final pending = [function.entry];
      while (pending.isNotEmpty) {
        final block = pending.removeLast();
        var dirty = incoming[block]!;
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (!facts.reachesOperation(operation, activation: activation)) {
            continue;
          }
          final exits = facts.exitsOf(operation, activation: activation);
          if (operation is StoreGlobal && operation.global == global) {
            if (!exits.normal || exits.exceptional) return false;
            final value = facts.valueOf(
              operation.value,
              activation: activation,
            );
            dirty =
                !(before.constant != null &&
                    value.constant?.structuralKey ==
                        before.constant!.structuralKey) &&
                !before.sources.any(value.sources.contains);
          } else {
            final effects = facts.effectsOf(operation, activation: activation);
            if ((dirty || dominance.before(first, operation)) &&
                (effects.contains(Effect.writesStorage) ||
                    effects.contains(Effect.callsUserCode))) {
              return false;
            }
            if (dirty &&
                (effects.contains(Effect.readsStorage) ||
                    exits.exceptional &&
                        !(block.end is Invoke &&
                            identical(
                              (block.end as Invoke).operation,
                              operation,
                            )))) {
              return false;
            }
          }
        }
        if (dirty) {
          switch (block.end) {
            case Return() ||
                Unreachable() ||
                Await() ||
                Yield() ||
                YieldStream() ||
                ExhaustivenessFailure():
              return false;
            case Throw(:final onThrow, :final isRecorded)
                when onThrow == null || !isRecorded:
              return false;
            default:
              break;
          }
        }
        for (final edge in block.successors) {
          if (!facts.reachesEdge(edge, activation: activation)) continue;
          final prior = incoming[edge.target];
          if (prior == null || dirty && !prior) {
            incoming[edge.target] = dirty || (prior ?? false);
            pending.add(edge.target);
          }
        }
      }
      return true;
    }

    if (executions.every(restored)) discardable.addAll(writes);
  }
  return discardable;
}

bool _overlaps(ProgramFlowFacts facts, FlowValue a, FlowValue b) {
  if (a.isBottom || b.isBottom) return false;
  if (a.objects.any(
    (left) =>
        b.objects.any((right) => facts.mayAliasAcrossSummaries(left, right)),
  )) {
    return true;
  }
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
bool _retains(
  ProgramFlowFacts facts,
  FlowValue references,
  FlowValue lifetimes,
) => _overlaps(facts, _mortal(references), lifetimes);

FlowValue _mortal(FlowValue references) {
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
  return mortal;
}
