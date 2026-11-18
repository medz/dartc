import 'package:dartc/ir.dart';

/// An entry parameter and the exact raw slot it must already bind.
/// A null slot denotes the single payload of a source cell capability.
typedef CellInitializationRequirement = (int, InstanceField?);

/// Definite assignment and capture obligations for one immutable program graph.
/// Requirements are rebuilt from actual source reads or ordinary raw-slot reads.
final class CellInitialization(final IrProgram program) {
  late final Map<FunctionTarget, Set<CellInitializationRequirement>>
  requirements = _infer();

  Map<FunctionTarget, Set<CellInitializationRequirement>> _infer() {
    final contracts = <FunctionTarget, Set<CellInitializationRequirement>>{
      for (final function in program.functions) function.target: {},
    };
    final analysis = _CellInitialization(program, contracts);
    bool changed;
    do {
      changed = false;
      for (final function in program.functions) {
        if (!analysis.demands(function)) continue;
        final all = <(Value, InstanceField?)>{
          for (final parameter in function.entry.parameters)
            for (final field in analysis.fields) (parameter, field),
        };
        final failure = analysis.check(function, all);
        if (failure != null) _uninitialized(function, failure);
        for (final (index, parameter) in function.entry.parameters.indexed) {
          for (final field in analysis.fields) {
            final requirement = (index, field);
            if (contracts[function.target]!.contains(requirement)) continue;
            if (analysis.check(
                  function,
                  all.difference({(parameter, field)}),
                ) !=
                null) {
              contracts[function.target]!.add(requirement);
              changed = true;
            }
          }
        }
      }
    } while (changed);
    return Map.unmodifiable({
      for (final entry in contracts.entries)
        entry.key: Set<CellInitializationRequirement>.unmodifiable(entry.value),
    });
  }

  /// Verifies the body under only its actual, derived entry obligations.
  void check(IrFunction function) {
    final declared = program.implementationOf(function.target);
    if (declared != null && !identical(declared, function)) {
      throw ArgumentError(
        'Cell obligations belong to a different program body.',
      );
    }
    if (declared == null) {
      // Independent consumers receive no assumed initialization for entry slots.
      final failure = _CellInitialization(
        program,
        requirements,
      ).check(function, {});
      if (failure != null) _uninitialized(function, failure);
      return;
    }
    final entryBound = <(Value, InstanceField?)>{
      for (final (slot, field)
          in requirements[function.target] ??
              const <CellInitializationRequirement>{})
        (function.entry.parameters[slot], field),
    };
    final failure = _CellInitialization(
      program,
      requirements,
    ).check(function, entryBound);
    if (failure != null) _uninitialized(function, failure);
  }
}

/// Rebuilds definite-assignment requirements, validating creation and call edges.
Map<FunctionTarget, Set<CellInitializationRequirement>>
cellInitializationRequirements(IrProgram program) =>
    CellInitialization(program).requirements;

/// Checks a standalone body without granting initialization to opaque entries.
/// Supply the whole [program] to establish actual creation/call obligations.
void checkCellInitialization(IrFunction function, {IrProgram? program}) {
  if (program != null) {
    CellInitialization(program).check(function);
    return;
  }
  final failure = _CellInitialization(null, const {}).check(function, {});
  if (failure != null) _uninitialized(function, failure);
}

Never _uninitialized(
  IrFunction function,
  Value failure,
) => throw UnsupportedError(
  'Cell or raw slot may be read before initialization in ${function.target.name}: '
  '${failure.runtimeType}.',
);

final class _CellInitialization(
  final IrProgram? program,
  final Map<FunctionTarget, Set<CellInitializationRequirement>> contracts,
) {
  late final storages = {
    for (final storage
        in (program?.classes ?? const <IrClass>[])
            .map((declaration) => declaration.cellStorage)
            .whereType<CellStorage>())
      storage.type: storage,
  };
  late final Set<InstanceField?> fields = {
    null,
    for (final declaration in program?.classes ?? const <IrClass>[])
      ...declaration.fields.where((field) => field.initiallyUnbound),
  };

  Iterable<Instruction> operations(Block block) => [
    ...block.instructions,
    ?switch (block.end) {
      Invoke(:final operation) => operation,
      _ => null,
    },
  ];

  bool demands(IrFunction function) => function.blocks
      .expand(operations)
      .any(
        (operation) => switch (operation) {
          ReadCell(cell: Value(type: CellType(isLate: false))) ||
          LoadField(field: InstanceField(initiallyUnbound: true)) ||
          InitializeStorageField() => true,
          MakeClosure(:final target) ||
          DirectCall(:final target) => contracts[target]?.isNotEmpty ?? false,
          Construct(callableStorage: CallableStorage(source: final source?)) ||
          InitializeObject(
            receiver: AllocatedObject(
              callableStorage: CallableStorage(source: final source?),
            ),
          ) => contracts[source]?.isNotEmpty ?? false,
          _ => false,
        },
      );

  Value? alias(Value value) => switch (value) {
    CellReference(:final cell) || CellStorageReference(:final cell) => cell,
    CellStorageView(:final backing) => backing,
    TypeView(:final operand) || UncheckedCast(:final operand) => operand,
    _ => null,
  };

  Value? check(IrFunction function, Set<(Value, InstanceField?)> entryBound) {
    if (!demands(function)) return null;
    final slots = {
      ...fields,
      ...function.fields.where((field) => field.initiallyUnbound),
    };
    final values = <Value>{
      for (final block in function.blocks) ...[
        ...block.parameters,
        ...operations(block),
      ],
    };
    final predecessors = {
      for (final block in function.blocks) block: <(Block, Jump, bool)>[],
    };
    for (final block in function.blocks) {
      for (final edge in block.successors) {
        predecessors[edge.target]!.add((
          block,
          edge,
          block.end is Invoke && identical(edge, (block.end as Invoke).onThrow),
        ));
      }
    }
    final origins = {
      for (final value in values)
        value:
            alias(value) != null ||
                value is BlockParameter &&
                    !function.entry.parameters.contains(value)
            ? <Value>{}
            : {value},
    };
    bool changed;
    do {
      changed = false;
      for (final value in values) {
        if (alias(value) case final input?) {
          final before = origins[value]!.length;
          origins[value]!.addAll(origins[input] ?? const <Value>{});
          changed |= before != origins[value]!.length;
        }
      }
      for (final block in function.blocks) {
        for (final (_, edge, _) in predecessors[block]!) {
          for (final (i, parameter) in block.parameters.indexed) {
            final known = origins[parameter]!, before = known.length;
            known.addAll(origins[edge.arguments[i]] ?? const <Value>{});
            changed |= before != known.length;
          }
        }
      }
    } while (changed);

    InstanceField? slot(Value value, InstanceField? field) {
      if (value.type is CellType) return null;
      if (field == null) {
        if (value.type case final ClassType type) {
          return storages[type.declaration]?.value;
        }
      }
      return field;
    }

    bool ready(
      Value value,
      Set<(Value, InstanceField?)> bound,
      InstanceField? field,
    ) =>
        bound.contains((value, slot(value, field))) ||
        (origins[value]?.isNotEmpty ?? false) &&
            origins[value]!.every(
              (origin) => bound.contains((origin, slot(origin, field))),
            );
    void bind(
      Value value,
      Set<(Value, InstanceField?)> bound,
      InstanceField? field,
    ) {
      bound.add((value, slot(value, field)));
      if (origins[value]?.length == 1) {
        final origin = origins[value]!.single;
        bound.add((origin, slot(origin, field)));
      }
    }

    void clear(
      Value value,
      Set<(Value, InstanceField?)> bound,
      InstanceField? field,
    ) {
      final affected = origins[value] ?? {value};
      bound.removeWhere(
        (entry) =>
            entry.$2 == slot(entry.$1, field) &&
            (identical(entry.$1, value) ||
                (origins[entry.$1] ?? {entry.$1}).any(affected.contains)),
      );
    }

    // The actual store identifies the initialized capture or payload. Argument
    // order and an initializer's name are never treated as storage evidence.
    Value? initializedField(
      FunctionTarget target,
      List<Value> inputs,
      InstanceField wanted,
    ) {
      final body = program?.implementationOf(target);
      if (body is! IrFunction ||
          body.blocks.length != 1 ||
          body.entry.end is! Return) {
        return null;
      }
      final mapping = Map<Value, Value>.fromIterables(
        body.entry.parameters,
        inputs,
      );
      Value? stored;
      for (final operation in body.entry.instructions) {
        if (alias(operation) case final operand?) {
          mapping[operation] = mapping[operand] ?? operand;
        }
        if (operation case StoreField(
          :final field,
          :final receiver,
          :final value,
        )) {
          if (field == wanted) {
            stored = identical(receiver, body.entry.parameters.first)
                ? mapping[value] ?? value
                : null;
          }
        } else if (operation.effects.contains(Effect.writesStorage)) {
          stored = null;
        }
      }
      return stored;
    }

    bool localInitializer(FunctionTarget target) {
      final body = program?.implementationOf(target);
      return body is IrFunction &&
          body.blocks.length == 1 &&
          body.entry.end is Return &&
          body.entry.instructions.every(
            (operation) =>
                operation is StoreField &&
                identical(operation.receiver, body.entry.parameters.first),
          );
    }

    // Absence is lattice top: an edge which has not yet been traversed
    // contributes no constraint to an intersection. Only materialize slots
    // which a predecessor can actually establish on this edge.
    final states =
        <
          Block,
          ({_InitializationState normal, _InitializationState exceptional})
        >{};
    Value? failure;
    ({_InitializationState normal, _InitializationState exceptional}) after(
      Block block, {
      bool validate = false,
    }) {
      var merged = block == function.entry
          ? _InitializationState(entryBound.toSet(), {})
          : null;
      for (final (previous, edge, exceptional) in predecessors[block]!) {
        final state = states[previous];
        if (state == null) continue;
        final before = exceptional ? state.exceptional : state.normal;
        final incoming = before.copy();
        incoming.bound.removeWhere(
          (item) => block.parameters.contains(item.$1),
        );
        incoming.fresh.removeWhere(
          (item) => block.parameters.contains(item.$1),
        );
        for (final (i, parameter) in block.parameters.indexed) {
          for (final field in slots) {
            if (ready(edge.arguments[i], before.bound, field)) {
              incoming.bound.add((parameter, slot(parameter, field)));
            }
            if (ready(edge.arguments[i], before.fresh, field)) {
              incoming.fresh.add((parameter, slot(parameter, field)));
            }
          }
        }
        if (merged == null) {
          merged = incoming;
        } else {
          merged.bound.retainAll(incoming.bound);
          merged.fresh.retainAll(incoming.fresh);
        }
      }
      if (merged == null)
        throw StateError('Initialization block has no input.');
      final bound = merged.bound, fresh = merged.fresh;
      void expose(Value value) {
        for (final field in slots) {
          clear(value, fresh, field);
        }
      }

      void require(Value value, Value site, [InstanceField? field]) {
        if (validate && !ready(value, bound, field)) failure ??= site;
      }

      void requireCaptures(
        Instruction operation,
        FunctionTarget initializer,
        List<Value> inputs,
        CallableStorage? storage,
      ) {
        final source = storage?.source;
        if (source == null || source.kind != FunctionKind.closure) return;
        for (final (parameter, field)
            in contracts[source] ?? const <CellInitializationRequirement>{}) {
          if (parameter > 0 && parameter <= source.captures.length) {
            final captured = initializedField(
              initializer,
              inputs,
              storage!.captures[parameter - 1],
            );
            if (captured == null) {
              if (validate) failure ??= operation;
            } else {
              require(captured, operation, field);
            }
          }
        }
      }

      void initialize(
        Value receiver,
        FunctionTarget target,
        List<Value> inputs,
      ) {
        for (final field in slots.whereType<InstanceField>()) {
          if (initializedField(target, inputs, field) != null) {
            bind(receiver, bound, field);
            clear(receiver, fresh, field);
          }
        }
      }

      _InitializationState? failed;
      for (final operation in operations(block)) {
        if (block.end case Invoke(operation: final invoked)
            when identical(invoked, operation)) {
          failed = _InitializationState(bound.toSet(), fresh.toSet());
        }
        switch (operation) {
          case NewCell(:final initial, type: CellType(isLate: false)):
            bound.remove((operation, null));
            if (initial != null) bind(operation, bound, null);
          case CopyCell(:final cell):
            final wasReady = ready(cell, bound, null);
            bound.remove((operation, null));
            if (wasReady) bind(operation, bound, null);
          case WriteCell(cell: final cell) when !(cell.type as CellType).isLate:
            bind(cell, bound, null);
            clear(cell, fresh, null);
          case ReadCell(cell: final cell) when !(cell.type as CellType).isLate:
            require(cell, operation);
          case MakeClosure(:final target, :final inputs):
            for (final (parameter, field)
                in contracts[target] ??
                    const <CellInitializationRequirement>{}) {
              if (parameter > 0 && parameter <= target.captures.length) {
                require(inputs[parameter - 1], operation, field);
              }
            }
            inputs.forEach(expose);
          case DirectCall(:final target, :final inputs):
            for (final (parameter, field)
                in contracts[target] ??
                    const <CellInitializationRequirement>{}) {
              require(inputs[parameter], operation, field);
            }
            inputs.forEach(expose);
          case ReadFunctionEnvironment(:final source, capture: final capture?):
            for (final (parameter, field)
                in contracts[source] ??
                    const <CellInitializationRequirement>{}) {
              if (parameter == capture + 1) bind(operation, bound, field);
            }
          case LoadField(:final field, :final receiver)
              when field.initiallyUnbound:
            require(receiver, operation, field);
          case StoreField(:final field, :final receiver, :final value):
            if (field.initiallyUnbound) {
              bind(receiver, bound, field);
              clear(receiver, fresh, field);
            }
            if (!identical(value, receiver)) expose(value);
          case InitializeStorageField(
            :final field,
            :final destination,
            :final source,
          ):
            if (validate && !ready(destination, fresh, field)) {
              throw UnsupportedError(
                'Storage initialization requires a fresh, unbound, unpublished destination.',
              );
            }
            final wasReady = ready(source, bound, field);
            clear(destination, fresh, field);
            clear(destination, bound, field);
            if (wasReady) bind(destination, bound, field);
          case NewPayload(type: final ClassType storageType) ||
              AllocatedObject(:final storageType) ||
            ManagedStorageAllocation(storageView: StorageView(:final storageType)):
            fresh.removeWhere((item) => identical(item.$1, operation));
            bound.removeWhere((item) => identical(item.$1, operation));
            for (final field in slots.whereType<InstanceField>()) {
              if (storageType.asInstanceOf(field.owner) != null) {
                fresh.add((operation, field));
              }
            }
          case Construct(
            :final initializer,
            :final arguments,
            :final callableStorage,
          ):
            bound.removeWhere((item) => identical(item.$1, operation));
            fresh.removeWhere((item) => identical(item.$1, operation));
            if (localInitializer(initializer)) {
              for (final field in slots.whereType<InstanceField>()) {
                if (operation.instantiatedType.asInstanceOf(field.owner) !=
                    null) {
                  fresh.add((operation, field));
                }
              }
            }
            initialize(operation, initializer, [operation, ...arguments]);
            arguments.forEach(expose);
            requireCaptures(operation, initializer, [
              operation,
              ...arguments,
            ], callableStorage);
          case InitializeObject(
            :final initializer,
            :final receiver,
            :final inputs,
          ):
            if (!localInitializer(initializer)) expose(receiver);
            initialize(receiver, initializer, inputs);
            inputs.skip(1).forEach(expose);
            requireCaptures(
              operation,
              initializer,
              inputs,
              receiver is AllocatedObject ? receiver.callableStorage : null,
            );
          case StoreObjectReference(:final value):
            expose(value);
          case ReferenceAddress(:final object):
            expose(object);
          default:
            if (operation.effects.contains(Effect.callsUserCode) ||
                operation.effects.contains(Effect.writesStorage)) {
              operation.inputs.forEach(expose);
            }
        }
        // A throwing call may publish or write an input before it fails.
        // No successful binding is assumed, but consumed freshness cannot return.
        failed?.fresh.retainAll(fresh);
      }
      final result = _InitializationState(bound, fresh);
      return (normal: result, exceptional: failed ?? result.copy());
    }

    final pending = {function.entry};
    while (pending.isNotEmpty) {
      final block = pending.first;
      pending.remove(block);
      final next = after(block), previous = states[block];
      if (previous == null ||
          !next.normal.same(previous.normal) ||
          !next.exceptional.same(previous.exceptional)) {
        states[block] = next;
        pending.addAll(block.successors.map((edge) => edge.target));
      }
    }
    for (final block in function.blocks) {
      after(block, validate: true);
    }
    return failure;
  }
}

final class _InitializationState(
  final Set<(Value, InstanceField?)> bound,
  final Set<(Value, InstanceField?)> fresh,
) {
  _InitializationState copy() =>
      _InitializationState(bound.toSet(), fresh.toSet());
  bool same(_InitializationState other) =>
      bound.length == other.bound.length &&
      bound.containsAll(other.bound) &&
      fresh.length == other.fresh.length &&
      fresh.containsAll(other.fresh);
}
