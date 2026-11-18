import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'cell_initialization.dart';

/// Expands shared-variable storage and lazy binding into ordinary typed IR.
final class CellLowering({final FunctionTarget? failure}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final owner = _Cells(failure);
    return ProgramTransform(
      (facts) => owner.lower(facts.program),
      normalize: owner.lower,
      realizations: () => const [],
    );
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _Cells(FunctionTarget? failure) {
  FunctionTarget? _failure = failure;
  final _storage = <(ExecutionShape, ValueType, bool), CellStorage>{};
  final _classes = <ClassType, IrClass>{};
  final _functions = <FunctionTarget, IrFunction>{};
  final _reads = <(CellStorage, CellType), IrFunction>{};
  final _writes = <(CellStorage, CellType), IrFunction>{};

  ValueType _payload(CellType type) => type.slotShape.isReference
      ? ValueType.object.nullable
      : ValueType.boolean.accepts(type.content)
      ? ValueType.boolean
      : type.slotShape == ExecutionShape.floating
      ? ValueType.floating
      : ValueType.integer;

  CellStorage storage(CellType cell) =>
      _storage.putIfAbsent((cell.slotShape, _payload(cell), cell.isLate), () {
        final owner = ClassType(null, 'CellBacking${_storage.length}');
        final content = _payload(cell);
        final value = InstanceField(
          owner,
          'value',
          content,
          initiallyUnbound: !cell.isLate,
        );
        final bound = cell.isLate
            ? InstanceField(owner, 'bound', .boolean)
            : null;
        final thunk = cell.isLate
            ? InstanceField(owner, 'thunk', FunctionType(content, []).nullable)
            : null;
        final fields = [value, ?bound, ?thunk];
        final initializer = FunctionTarget(
          null,
          'new',
          .voidType,
          const [],
          owner: owner,
          kind: .initializer,
        );
        final body = Block(initializer.parameterTypes);
        body.finish(const Return());
        _functions[initializer] = IrFunction(initializer, [body]);
        final storage = CellStorage(
          owner,
          value,
          bound,
          initializer,
          cell.slotShape,
          thunk: thunk,
        );
        _classes[owner] = IrClass(
          owner,
          fields,
          constructors: [initializer],
          cellStorage: storage,
        );
        return storage;
      });

  Constant _empty(CellStorage storage) => storage.slotShape.isReference
      ? const Constant.nullValue()
      : storage.value.type == ValueType.boolean
      ? const Constant.boolean(false)
      : storage.value.type == ValueType.floating
      ? const Constant.floating(0)
      : const Constant.integer(0);

  IrFunction create(NewCell operation, CellStorage storage) {
    final cell = operation.type as CellType;
    final type = storage.backingOf(cell);
    final target = FunctionTarget(
      null,
      'createCell',
      type,
      operation.inputs.map((value) => value.type),
      typeParameters: cell.content.freeTypeParameters,
    );
    final entry = Block(target.parameterTypes);
    final view = storage.viewOf(cell);
    final result = entry.emit(
      Construct(
        storage.initializer,
        const [],
        instantiatedType: type,
        storageView: view,
      ),
    );
    if (operation.initial != null || cell.isLate) {
      final initial = operation.initial == null
          ? _empty(storage)
          : entry.parameters.first;
      entry.emit(StoreField(storage.value, result, initial, storageView: view));
    }
    if (cell.isLate) {
      entry.emit(
        StoreField(
          storage.bound!,
          result,
          Constant.boolean(operation.initial != null),
          storageView: view,
        ),
      );
      entry.emit(
        StoreField(
          storage.thunk!,
          result,
          operation.initializer == null
              ? const Constant.nullValue()
              : entry.parameters.last,
          storageView: view,
        ),
      );
    }
    entry.finish(Return(result));
    return IrFunction(target, [entry]);
  }

  IrFunction copy(CellType cell, CellStorage storage) {
    final type = storage.backingOf(cell);
    final target = FunctionTarget(null, 'copyCell', type, [
      type,
    ], typeParameters: cell.content.freeTypeParameters);
    final entry = Block(target.parameterTypes);
    final view = storage.viewOf(cell);
    final result = entry.emit(
      Construct(
        storage.initializer,
        const [],
        instantiatedType: type,
        storageView: view,
      ),
    );
    if (cell.isLate) {
      for (final field in storage.fields) {
        final value = entry.emit(
          LoadField(field, entry.parameters.single, storageView: view),
        );
        entry.emit(StoreField(field, result, value, storageView: view));
      }
    } else {
      entry.emit(
        InitializeStorageField(
          storage.value,
          result,
          entry.parameters.single,
          storageView: view,
        ),
      );
    }
    entry.finish(Return(result));
    return IrFunction(target, [entry]);
  }

  void fail(Block block, String message) {
    final failure =
        _failure ??
        (throw StateError(
          'Cell binding requires its actual failure implementation.',
        ));
    final call = block.emit(DirectCall(failure, [Constant.string(message)]));
    block.finish(Unreachable(call));
  }

  IrFunction read(CellType cell, CellStorage storage) => _reads.putIfAbsent(
    (storage, cell),
    () {
      final view = storage.viewOf(cell);
      final target = FunctionTarget(null, 'readCell', cell.content, [
        storage.backingOf(cell),
      ], typeParameters: cell.content.freeTypeParameters);
      final entry = Block(target.parameterTypes);
      if (!cell.isLate) {
        final value = entry.emit(
          LoadField(storage.value, entry.parameters.single, storageView: view),
        );
        entry.finish(Return(value));
        final body = IrFunction(target, [entry]);
        _functions[target] = body;
        return body;
      }
      final bound = Block(), unbound = Block();
      final receiver = entry.parameters.single;
      final blocks = [entry, bound, unbound];
      entry.finish(
        Branch(
          entry.emit(LoadField(storage.bound!, receiver, storageView: view)),
          Jump(bound),
          Jump(unbound),
        ),
      );
      bound.finish(
        Return(
          bound.emit(
            TypeCast(
              bound.emit(LoadField(storage.value, receiver, storageView: view)),
              cell.content,
            ),
          ),
        ),
      );
      if (storage.thunk == null) {
        fail(unbound, 'Local has not been initialized.');
      } else {
        final evaluate = Block(), missing = Block();
        blocks.addAll([evaluate, missing]);
        final thunk = unbound.emit(
          LoadField(storage.thunk!, receiver, storageView: view),
        );
        unbound.finish(
          Branch(
            unbound.emit(Equals(thunk, const Constant.nullValue())),
            Jump(missing),
            Jump(evaluate),
          ),
        );
        fail(missing, 'Local has not been initialized.');
        final value = evaluate.emit(
          FunctionCall(evaluate.emit(NullCheck(thunk)), []),
        );
        var commit = evaluate;
        if (cell.isFinal) {
          commit = Block();
          final assigned = Block();
          blocks.addAll([commit, assigned]);
          evaluate.finish(
            Branch(
              evaluate.emit(
                LoadField(storage.bound!, receiver, storageView: view),
              ),
              Jump(assigned),
              Jump(commit),
            ),
          );
          fail(assigned, 'Local has been assigned during initialization.');
        }
        commit.emit(
          StoreField(storage.value, receiver, value, storageView: view),
        );
        commit.emit(
          StoreField(
            storage.bound!,
            receiver,
            const Constant.boolean(true),
            storageView: view,
          ),
        );
        commit.emit(
          StoreField(
            storage.thunk!,
            receiver,
            const Constant.nullValue(),
            storageView: view,
          ),
        );
        commit.finish(Return(value));
      }
      final body = IrFunction(target, blocks);
      _functions[target] = body;
      return body;
    },
  );

  IrFunction write(
    CellType cell,
    CellStorage storage,
  ) => _writes.putIfAbsent((storage, cell), () {
    final view = storage.viewOf(cell);
    final target = FunctionTarget(null, 'writeCell', .voidType, [
      storage.backingOf(cell),
      cell.content,
    ], typeParameters: cell.content.freeTypeParameters);
    final entry = Block(target.parameterTypes);
    final blocks = [entry];
    final receiver = entry.parameters.first;
    final value = cell.isLate
        ? entry.emit(TypeCast(entry.parameters.last, cell.content))
        : entry.parameters.last;
    var commit = entry;
    if (cell.isLate && cell.isFinal) {
      commit = Block();
      final assigned = Block();
      blocks.addAll([commit, assigned]);
      entry.finish(
        Branch(
          entry.emit(LoadField(storage.bound!, receiver, storageView: view)),
          Jump(assigned),
          Jump(commit),
        ),
      );
      fail(assigned, 'Local has already been initialized.');
    }
    commit.emit(StoreField(storage.value, receiver, value, storageView: view));
    if (storage.bound case final bound?) {
      commit.emit(
        StoreField(
          bound,
          receiver,
          const Constant.boolean(true),
          storageView: view,
        ),
      );
    }
    if (storage.thunk case final thunk?) {
      commit.emit(
        StoreField(
          thunk,
          receiver,
          const Constant.nullValue(),
          storageView: view,
        ),
      );
    }
    commit.finish(const Return());
    final body = IrFunction(target, blocks);
    _functions[target] = body;
    return body;
  });

  IrProgram lower(IrProgram program) {
    cellInitializationRequirements(program);
    for (final declaration in program.classes) {
      if (declaration.cellStorage case final storage?) {
        final payload = storage.slotShape.isReference
            ? ValueType.object.nullable
            : storage.value.type;
        final key = (storage.slotShape, payload, storage.isLate);
        final existing = _storage[key];
        if (existing != null && !identical(existing, storage)) {
          throw StateError('Conflicting persistent cell storage declarations.');
        }
        _storage[key] = storage;
        _classes[storage.type] = declaration;
      }
    }
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      final operations = <Instruction, Instruction>{};
      final lowered =
          <
            Instruction,
            ({
              IrFunction body,
              List<Value> arguments,
              Map<TypeParameterType, ValueType> environment,
              Jump? handler,
            })
          >{};
      final views = <Instruction, Instruction Function(Value)>{};
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          final cell = switch (operation) {
            NewCell() => operation.type as CellType,
            ReadCell(:final cell) ||
            WriteCell(:final cell) ||
            CopyCell(:final cell) => cell.type as CellType,
            _ => null,
          };
          if (cell == null) continue;
          if (_failure == null &&
              cell.isLate &&
              (operation is ReadCell ||
                  operation is WriteCell && cell.isFinal)) {
            final constructor = program.classes
                .where(
                  (declaration) =>
                      declaration.type.library == Uri.parse('dart:_internal') &&
                      declaration.type.name == 'LateError',
                )
                .firstOrNull
                ?.constructors['new'];
            if (constructor == null ||
                program.implementationOf(constructor) == null) {
              throw StateError(
                'Cell binding requires the actual SDK LateError constructor.',
              );
            }
            final target = _failure = FunctionTarget(
              null,
              'cellBindingFailure',
              .never,
              [.string],
            );
            final entry = Block(target.parameterTypes);
            entry.finish(
              Throw(entry.emit(Construct(constructor, entry.parameters))),
            );
            _functions[target] = IrFunction(target, [entry]);
          }
          final layout = storage(cell);
          final environment = {
            for (final parameter in cell.content.freeTypeParameters)
              parameter: parameter,
          };
          switch (operation) {
            case NewCell():
              lowered[operation] = (
                body: create(operation, layout),
                arguments: operation.inputs.toList(),
                environment: environment,
                handler: switch (block.end) {
                  Invoke(operation: final invoked, :final onThrow)
                      when identical(invoked, operation) =>
                    onThrow,
                  _ => null,
                },
              );
              views[operation] = (backing) =>
                  CellStorageView(backing, cell, layout);
            case CopyCell():
              final backing = CellStorageReference(operation.cell, layout);
              lowered[operation] = (
                body: copy(cell, layout),
                arguments: [backing],
                environment: environment,
                handler: switch (block.end) {
                  Invoke(operation: final invoked, :final onThrow)
                      when identical(invoked, operation) =>
                    onThrow,
                  _ => null,
                },
              );
              views[operation] = (backing) =>
                  CellStorageView(backing, cell, layout);
            case ReadCell() || WriteCell():
              final helper = operation is ReadCell
                  ? read(cell, layout)
                  : write(cell, layout);
              final arguments = <Value>[
                CellStorageReference(operation.inputs.first, layout),
                if (operation is WriteCell) operation.value,
              ];
              if (!cell.isLate) {
                lowered[operation] = (
                  body: helper,
                  arguments: arguments,
                  environment: environment,
                  handler: null,
                );
              } else {
                operations[operation] = DirectCall(
                  helper.target,
                  arguments,
                  typeArguments: helper.target.typeParameters,
                );
              }
            default:
              throw StateError('Unexpected cell operation.');
          }
        }
      }
      final rewritten = operations.isEmpty && lowered.isEmpty
          ? function
          : FunctionRewrite(
              function,
              executionShapes: program.executionShapes,
              operations: operations,
              lowered: lowered,
              resultViews: views,
            ).run();
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    if (!changed) return program;
    final present = functions.map((body) => body.target).toSet();
    for (final body in _functions.values) {
      if (present.add(body.target)) functions.add(body);
    }
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    return IrProgram(
      {for (final c in program.classes) c.type: c, ..._classes}.values,
      functions,
      globals: program.globals,
      externals: program.externals,
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: ExecutionShapes(
        entries: shapes.entries,
        slots: {
          ...shapes.slots,
          for (final storage in _storage.values)
            storage.value: storage.slotShape,
        },
      ),
    );
  }
}
