import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'callable_implementations.dart';

/// Makes demanded function-value execution entries part of the same program.
final class CallableLowering(final CallableImplementations implementations)
    extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final recipes = <Object, ProgramRealization>{};
    void construction(IrFunction body, Instruction operation) {
      final source = body.originOf(operation).source;
      final key = (CallableLowering, source, operation.runtimeType);
      recipes.putIfAbsent(
        key,
        () => ProgramRealization(
          key,
          (canonical) => _realizeConstruction(canonical, source),
        ),
      );
    }

    void remember(
      IrFunction body,
      Instruction operation,
      CallEntryBinding binding,
    ) {
      final source = body.originOf(operation).source;
      for (final target in binding.entries.keys) {
        final key = (source, target, binding.shape.execution);
        recipes.putIfAbsent(
          key,
          () => ProgramRealization(
            key,
            (canonical) => _realize(canonical, source, target),
          ),
        );
      }
    }

    return ProgramTransform(
      (facts) {
        final program = facts.program;
        implementations.extend(program);
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
          if (facts.definitions.contains(function.target)) {
            for (final block in function.blocks) {
              for (final operation in [
                ...block.instructions,
                if (block.end case Invoke(:final operation)) operation,
              ]) {
                if (operation case final MakeClosure closure
                    when facts.reachesOperation(operation)) {
                  construction(function, operation);
                  operations[operation] = implementations.createClosure(
                    closure,
                  );
                  continue;
                }
                if (operation case final InstantiateFunction instantiation
                    when implementations.types != null &&
                        facts.reachesOperation(operation)) {
                  construction(function, operation);
                  operations[operation] = implementations.instantiateFunction(
                    instantiation,
                  );
                  continue;
                }
                if (operation case final InstantiateFunctionFrom instantiation
                    when implementations.types != null &&
                        facts.reachesOperation(operation)) {
                  construction(function, operation);
                  operations[operation] = implementations
                      .instantiateFunctionFrom(instantiation);
                  continue;
                }
                if (operation case final BindMethod binding
                    when implementations.types != null &&
                        facts.reachesOperation(operation)) {
                  final targets = <ClassType, FunctionTarget>{};
                  for (final receiver in facts.receiverClassesOf(
                    binding.receiver,
                  )) {
                    final target = binding.direct
                        ? binding.method
                        : program
                              .lookupMember(receiver, binding.method.selector)
                              .target;
                    if (target == null || target.isAbstract) {
                      throw StateError(
                        'Method extraction requires its actual implementation.',
                      );
                    }
                    targets[receiver] = target;
                  }
                  final entries = _methodBinding(
                    function,
                    binding,
                    targets.values.toSet(),
                  );
                  final source = function.originOf(operation).source;
                  for (final target in entries.entries.keys) {
                    final key = (
                      CallableLowering,
                      source,
                      'bind',
                      target,
                      entries.execution,
                    );
                    recipes.putIfAbsent(
                      key,
                      () => ProgramRealization(
                        key,
                        (canonical) =>
                            _realizeBoundMethod(canonical, source, target),
                      ),
                    );
                  }
                  if (!_sameMethodBinding(binding.entryBinding, entries)) {
                    lowered[operation] = _methodRewrite(
                      function,
                      binding,
                      entries,
                      switch (block.end) {
                        Invoke(operation: final site, :final onThrow)
                            when identical(site, operation) =>
                          onThrow,
                        _ => null,
                      },
                    );
                  }
                  continue;
                }
                if (operation case final DynamicDispatch dispatch
                    when facts.reachesOperation(operation)) {
                  var binding = dispatch.entryBinding;
                  final methods = Map<FunctionTarget, FunctionTarget>.of(
                    dispatch.methodBindings,
                  );
                  if (dispatch.selector.name == 'call' &&
                      dispatch.selector.privateScope == null &&
                      dispatch.selector.kind == .method) {
                    final sources = facts.sourceTargetsOf(dispatch);
                    if (sources.isNotEmpty) {
                      binding = implementations.bindDynamic(
                        dispatch,
                        sources,
                        caller: function,
                      );
                      remember(function, dispatch, binding);
                    }
                  }
                  if (dispatch.selector.kind == .getter &&
                      implementations.types != null) {
                    for (final receiver in facts.receiverClassesOf(
                      dispatch.receiver,
                    )) {
                      if (program
                              .lookupMember(receiver, dispatch.selector)
                              .target !=
                          null) {
                        continue;
                      }
                      final method = program.lookupMember(receiver, (
                        kind: FunctionKind.method,
                        name: dispatch.selector.name,
                        privateScope: dispatch.selector.privateScope,
                      )).target;
                      if (method != null && !method.isAbstract) {
                        methods[method] = implementations.dynamicMethodBinding(
                          method,
                        );
                        final source = function.originOf(dispatch).source;
                        final key = (
                          CallableLowering,
                          source,
                          'method',
                          method,
                        );
                        recipes.putIfAbsent(
                          key,
                          () => ProgramRealization(
                            key,
                            (canonical) =>
                                _realizeMethod(canonical, source, method),
                          ),
                        );
                      }
                    }
                  }
                  final same =
                      identical(binding?.shape, dispatch.entryBinding?.shape) &&
                      (binding?.entries.length ?? 0) ==
                          (dispatch.entryBinding?.entries.length ?? 0) &&
                      (binding?.entries.entries.every(
                            (e) =>
                                dispatch.entryBinding?.entries[e.key] ==
                                e.value,
                          ) ??
                          true) &&
                      methods.length == dispatch.methodBindings.length &&
                      methods.entries.every(
                        (e) => dispatch.methodBindings[e.key] == e.value,
                      );
                  if (!same) {
                    operations[dispatch] = DynamicDispatch(
                      dispatch.receiver,
                      dispatch.selector,
                      dispatch.positional,
                      dispatch.named,
                      dispatch.typeArguments,
                      dispatch.failure,
                      dispatch.getterCalls,
                      binding,
                      methods,
                    );
                  }
                  continue;
                }
                if (operation is! FunctionCall ||
                    !facts.reachesOperation(operation)) {
                  continue;
                }
                final targets = facts.sourceTargetsOf(operation);
                if (facts.hasUnknownCall(operation) || targets.isEmpty) {
                  final source = function.originOf(operation).source;
                  final location = function.sourceLocations[operation]?.position;
                  throw StateError(
                    'Callable execution requires the actual function origins at '
                    '${source.owner.library}::${source.owner.name} ${location ?? ''}. '
                    'Producer ${operation.function.runtimeType} returns '
                    '${operation.function.type.dartName}; seen '
                    '${targets.map((t) => t.name).join(', ')}; '
                    'unknown=${facts.hasUnknownCall(operation)}.',
                  );
                }
                final binding = implementations.bind(
                  operation,
                  targets,
                  caller: function,
                );
                remember(function, operation, binding);
                if (operation.entryBinding case final old?
                    when identical(old.shape, binding.shape) &&
                        old.entries.length == binding.entries.length &&
                        old.entries.entries.every(
                          (entry) => binding.entries[entry.key] == entry.value,
                        )) {
                  continue;
                }
                operations[operation] = FunctionCall(
                  operation.function,
                  operation.positional,
                  operation.named,
                  operation.typeArguments,
                  operation.target,
                  binding,
                );
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
                ).run();
          changed |= !identical(rewritten, function);
          functions.add(rewritten);
        }
        return _install(program, functions, changed: changed);
      },
      realizations: () => recipes.values,
      rebase: implementations.extend,
    );
  }

  bool _sameMethodBinding(MemberEntryBinding? a, MemberEntryBinding b) =>
      a != null &&
      a.signature == b.signature &&
      a.execution == b.execution &&
      a.entries.length == b.entries.length &&
      a.entries.entries.every((e) => b.entries[e.key] == e.value);

  MemberEntryBinding _methodBinding(
    IrFunction body,
    BindMethod operation,
    Set<FunctionTarget> sources,
  ) {
    final parameters = {
      ...operation.receiver.type.freeTypeParameters,
      ...operation.type.freeTypeParameters,
    }.toList();
    ValueType closed(ValueType type) =>
        type.freeTypeParameters.isEmpty ? type : .object.nullable;
    final old = operation.entryBinding;
    final signature =
        old?.signature ??
        FunctionType(closed(operation.type), [
          closed(operation.receiver.type),
          for (final _ in parameters) TypeMetadata.type,
        ]);
    final shapes = implementations.executionShapes;
    final execution =
        old?.execution ??
        ExecutionSignature([
          shapes.shapeOf(body, operation.receiver),
          for (final _ in parameters) ExecutionShape.reference,
        ], ExecutionShape.reference);
    final entries = {...?old?.entries};
    for (final source in sources) {
      entries.putIfAbsent(
        source,
        () => implementations.methodEntry(
          operation,
          source,
          signature,
          execution,
        ),
      );
    }
    return MemberEntryBinding(
      signature,
      execution,
      0,
      const [],
      signature.parameters.length - 1,
      entries,
      executionShapes: implementations.executionShapes,
    );
  }

  ({
    IrFunction body,
    List<Value> arguments,
    Map<TypeParameterType, ValueType> environment,
    Jump? handler,
  })
  _methodRewrite(
    IrFunction owner,
    BindMethod operation,
    MemberEntryBinding binding,
    Jump? handler,
  ) {
    final inputs = operation.inputs.toList();
    final parameters = {
      ...operation.receiver.type.freeTypeParameters,
      ...operation.type.freeTypeParameters,
    }.toList();
    final target = FunctionTarget(
      null,
      'methodProducer',
      operation.type,
      inputs.map((v) => v.type),
      typeParameters: parameters,
    );
    final entry = Block(target.parameterTypes);
    final call = entry.emit(
      BindMethod(
        operation.method,
        entry.parameters.first,
        direct: operation.direct,
        ownerType: operation.ownerType,
        entryBinding: binding,
        executionTypes: operation.entryBinding == null
            ? [
                for (final parameter in parameters)
                  entry.emit(
                    UncheckedCast(
                      entry.emit(ReifyType(parameter)),
                      TypeMetadata.type,
                    ),
                  ),
              ]
            : entry.parameters.skip(1),
      ),
    );
    entry.finish(Return(call));
    return (
      body: IrFunction(
        target,
        [entry],
        origins: {call: owner.originOf(operation)},
      ),
      arguments: inputs,
      environment: {for (final parameter in parameters) parameter: parameter},
      handler: handler,
    );
  }

  IrProgram _realizeBoundMethod(
    IrProgram program,
    IrOrigin source,
    FunctionTarget target,
  ) {
    implementations.extend(program);
    var found = false, changed = false;
    final functions = <IrFunction>[];
    for (final body in program.functions) {
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
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation is! BindMethod ||
              body.originOf(operation).source != source)
            continue;
          found = true;
          final binding = _methodBinding(body, operation, {target});
          if (_sameMethodBinding(operation.entryBinding, binding)) continue;
          lowered[operation] = _methodRewrite(
            body,
            operation,
            binding,
            switch (block.end) {
              Invoke(operation: final site, :final onThrow)
                  when identical(site, operation) =>
                onThrow,
              _ => null,
            },
          );
        }
      }
      final next = lowered.isEmpty
          ? body
          : FunctionRewrite(body, executionShapes: program.executionShapes, lowered: lowered).run();
      changed |= !identical(next, body);
      functions.add(next);
    }
    if (!found)
      throw StateError('A method producer has no canonical extraction site.');
    return _install(program, functions, changed: changed);
  }

  IrProgram _realizeConstruction(IrProgram program, IrOrigin source) {
    implementations.extend(program);
    var found = false;
    final functions = <IrFunction>[];
    for (final body in program.functions) {
      final replacements = <Instruction, Instruction>{};
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (body.originOf(operation).source != source) continue;
          final replacement = switch (operation) {
            MakeClosure() => implementations.createClosure(operation),
            InstantiateFunction() => implementations.instantiateFunction(
              operation,
            ),
            InstantiateFunctionFrom() =>
              implementations.instantiateFunctionFrom(operation),
            _ => null,
          };
          if (replacement == null) continue;
          found = true;
          replacements[operation] = replacement;
        }
      }
      functions.add(
        replacements.isEmpty
            ? body
            : FunctionRewrite(body, executionShapes: program.executionShapes, operations: replacements).run(),
      );
    }
    if (!found)
      throw StateError(
        'Callable construction has no canonical source operation.',
      );
    return _install(program, functions, changed: true);
  }

  IrProgram _realizeMethod(
    IrProgram program,
    IrOrigin source,
    FunctionTarget method,
  ) {
    implementations.extend(program);
    var found = false;
    final functions = <IrFunction>[];
    for (final body in program.functions) {
      final replacements = <Instruction, Instruction>{};
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (operation is! DynamicDispatch ||
              body.originOf(operation).source != source)
            continue;
          found = true;
          replacements[operation] = DynamicDispatch(
            operation.receiver,
            operation.selector,
            operation.positional,
            operation.named,
            operation.typeArguments,
            operation.failure,
            operation.getterCalls,
            operation.entryBinding,
            {
              ...operation.methodBindings,
              method: implementations.dynamicMethodBinding(method),
            },
          );
        }
      }
      functions.add(
        replacements.isEmpty
            ? body
            : FunctionRewrite(body, executionShapes: program.executionShapes, operations: replacements).run(),
      );
    }
    if (!found)
      throw StateError('Method extraction has no canonical dynamic getter.');
    return _install(program, functions, changed: true);
  }

  IrProgram _realize(
    IrProgram program,
    IrOrigin source,
    FunctionTarget target,
  ) {
    implementations.extend(program);
    var found = false, changed = false;
    final functions = <IrFunction>[];
    for (final body in program.functions) {
      final replacements = <Instruction, Instruction>{};
      for (final block in body.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (body.originOf(operation).source != source) continue;
          // Entry alternatives can safely be made available at the shared
          // language call. Dispatch, operands, generic arguments and exception
          // edges still come from this canonical operation. Inlined constants
          // and caller-specific proofs are not copied into the shared body.
          final Instruction replacement;
          switch (operation) {
            case FunctionCall():
              final binding = implementations.bind(operation, {
                ...?operation.entryBinding?.entries.keys,
                target,
              }, caller: body);
              replacement = FunctionCall(
                operation.function,
                operation.positional,
                operation.named,
                operation.typeArguments,
                operation.target,
                binding,
              );
            case DynamicDispatch():
              final binding = implementations.bindDynamic(operation, {
                ...?operation.entryBinding?.entries.keys,
                target,
              }, caller: body);
              replacement = DynamicDispatch(
                operation.receiver,
                operation.selector,
                operation.positional,
                operation.named,
                operation.typeArguments,
                operation.failure,
                operation.getterCalls,
                binding,
                operation.methodBindings,
              );
            default:
              continue;
          }
          found = true;
          replacements[operation] = replacement;
        }
      }
      final next = replacements.isEmpty
          ? body
          : FunctionRewrite(body, executionShapes: program.executionShapes, operations: replacements).run();
      changed |= !identical(next, body);
      functions.add(next);
    }
    if (!found) {
      throw StateError(
        'A callable realization has no canonical language call site.',
      );
    }
    return _install(program, functions, changed: changed);
  }

  IrProgram _install(
    IrProgram program,
    List<IrFunction> functions, {
    required bool changed,
  }) {
    final present = functions.map((body) => body.target).toSet();
    for (final body in [
      ...implementations.functions,
      ...implementations.constructionFunctions,
      ...implementations.storage.functions,
      ...?implementations.types?.functions,
    ]) {
      if (present.add(body.target)) {
        functions.add(body);
        changed = true;
      }
    }
    final classes = {
      for (final declaration in program.classes) declaration.type: declaration,
    };
    for (final declaration in implementations.storage.classes) {
      if (!classes.containsKey(declaration.type)) {
        classes[declaration.type] = declaration;
        changed = true;
      }
    }
    if (implementations.storage.classes.isNotEmpty) {
      for (final entry in TypeMetadata.fields.entries) {
        if (!classes.containsKey(entry.key)) {
          classes[entry.key] = IrClass(entry.key, entry.value);
          changed = true;
        }
      }
    }
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    final entries = {...shapes.entries, ...implementations.entryExecutions};
    if (entries.length != shapes.entries.length ||
        entries.entries.any(
          (entry) => shapes.entries[entry.key] != entry.value,
        )) {
      changed = true;
    }
    final slots = Map<Object, ExecutionShape>.of(shapes.slots);
    for (final declaration in classes.values) {
      final storage = declaration.callableStorage;
      final source = storage?.source;
      if (storage == null ||
          source == null ||
          source.kind != FunctionKind.closure) {
        continue;
      }
      for (final (index, field) in storage.captures.indexed) {
        final expected = shapes.slotOf(CaptureSlot(source, index));
        if (shapes.slotOf(field) != expected) {
          slots[field] = expected;
          changed = true;
        }
      }
    }
    final executions =
        entries.length == shapes.entries.length &&
            entries.entries.every(
              (entry) => shapes.entries[entry.key] == entry.value,
            ) &&
            slots.length == shapes.slots.length &&
            slots.entries.every(
              (entry) => shapes.slots[entry.key] == entry.value,
            )
        ? program.executionShapes
        : ExecutionShapes(entries: entries, slots: slots);
    return changed
        ? IrProgram(
            classes.values,
            functions,
            globals: program.globals,
            externals: program.externals,
            nativeBoundaries: program.nativeBoundaries,
            executionShapes: executions,
          )
        : program;
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}
