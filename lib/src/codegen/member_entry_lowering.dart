import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'type_implementations.dart';

/// Exposes member parameter, default and result adaptation as ordinary IR.
final class MemberEntryLowering(final TypeImplementations types)
    extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final entries = _MemberEntries(types);
    return ProgramTransform(
      entries.lower,
      realizations: () => entries.realizations.values,
      rebase: entries.rebase,
    );
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _MemberEntries(final TypeImplementations types) {
  // A machine signature determines carriers; the source argument binding
  // determines which formal is written and which default still runs.
  Object _entryKey(
    FunctionTarget source,
    FunctionType signature,
    ExecutionSignature execution,
    int positionalCount,
    Iterable<String> names,
    int typeCount,
  ) => (
    source,
    signature,
    execution,
    positionalCount,
    names.fold<Object>((), (key, name) => (key, name)),
    typeCount,
  );

  final _entries = <Object, IrFunction>{};
  final _entryTargets = <Object, FunctionTarget>{};
  final _bodies = <FunctionTarget, IrFunction>{};
  final _bodyTargets = <FunctionTarget, FunctionTarget>{};
  final _variants = <(FunctionTarget, FunctionType), IrFunction>{};
  final _variantTargets = <(FunctionTarget, FunctionType), FunctionTarget>{};
  final _executions = <FunctionTarget, ExecutionSignature>{};
  final realizations = <Object, ProgramRealization>{};

  void rebase(IrProgram program) {
    _entries.clear();
    _bodies.clear();
    _variants.clear();
    _executions.clear();
    _adopt(program);
  }

  void _adopt(IrProgram program) {
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    for (final body in program.functions) {
      if (body.target.executionSource case final source?) {
        if (!source.kind.isVirtual) continue;
        final expected = FunctionType(
          source.returnType,
          source.parameterTypes,
          typeParameters: [
            ...source.owner!.typeParameters,
            ...source.typeParameters,
          ],
        );
        if (body.target.signature != expected) {
          final key = (source, body.target.signature);
          if (_variants[key] case final previous?
              when previous.target != body.target) {
            throw StateError('Conflicting concrete member execution bodies.');
          }
          _variants[key] = body;
          _variantTargets[key] = body.target;
          _executions[body.target] = shapes.entryOf(body.target);
          continue;
        }
        if (shapes.entryOf(body.target) != shapes.entryOf(source)) continue;
        if (_bodies[source] case final existing?
            when existing.target != body.target) {
          throw StateError(
            'Conflicting ordinary bodies for one member execution contract.',
          );
        }
        _bodies[source] = body;
        _bodyTargets[source] = body.target;
        _executions[body.target] = shapes.entryOf(body.target);
      }
      for (final block in body.blocks) {
        for (final op in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (op case InstanceCall(entryBinding: final binding?)) {
            for (final entry in binding.entries.entries) {
              final implementation = program.implementationOf(entry.value);
              if (implementation is! IrFunction) {
                throw StateError(
                  'A member execution entry needs its actual body.',
                );
              }
              final key = _entryKey(
                entry.key,
                binding.signature,
                binding.execution,
                binding.positionalCount,
                binding.names,
                binding.typeArgumentCount,
              );
              _entries[key] = implementation;
              _entryTargets[key] = entry.value;
              _executions[entry.value] = binding.execution;
            }
          }
        }
      }
    }
  }

  IrProgram lower(ProgramFlowFacts facts) =>
      _rewrite(facts.program, facts: facts);

  IrProgram _rewrite(
    IrProgram program, {
    ProgramFlowFacts? facts,
    Map<IrOrigin, Set<FunctionTarget>> requested = const {},
  }) {
    _adopt(program);
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    final found = <IrOrigin>{};
    var changed = false;
    final functions = <IrFunction>[];
    for (final body in program.functions) {
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
      if (facts == null || facts.definitions.contains(body.target)) {
        for (final block in body.blocks) {
          for (final site in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            final origin = body.originOf(site).source;
            if (facts == null
                ? !requested.containsKey(origin)
                : !facts.reachesOperation(site)) {
              continue;
            }
            final direct =
                site is DirectCall &&
                site.target.kind.isVirtual &&
                program.implementationOf(site.target) is IrFunction;
            if (site is! InstanceCall && !direct) continue;
            found.add(origin);
            var op = site is InstanceCall
                ? site
                : () {
                    final call = site as DirectCall;
                    final signature = call.target.signature;
                    return InstanceCall(
                      call.target,
                      call.inputs.first,
                      call.inputs.skip(1).take(signature.positionalCount),
                      {
                        for (final e in signature.named.entries)
                          e.key: call.inputs[e.value.slot + 1],
                      },
                      call.ownerType,
                      call.typeArguments,
                    );
                  }();
            final sources = <FunctionTarget>{
              ...?op.entryBinding?.entries.keys,
              if (direct) site.target else ...?facts?.sourceTargetsOf(site),
              ...?requested[origin],
            };
            if (sources.isEmpty || (facts?.hasUnknownCall(site) ?? false)) {
              throw StateError(
                'Member execution needs its actual dispatch targets.',
              );
            }
            ValueType closed(ValueType type) => type.freeTypeParameters.isEmpty
                ? type
                : ValueType.object.nullable;
            if (op.entryBinding == null) {
              Value payload(Value value) {
                final physical = shapes.shapeOf(body, value);
                if (!physical.isScalar) return value;
                while (true) {
                  final input = switch (value) {
                    TypeView(:final operand) ||
                    UncheckedCast(:final operand) => operand,
                    _ => null,
                  };
                  if (input == null ||
                      !value.type.accepts(input.type) ||
                      shapes.shapeOf(body, input) != physical) {
                    return value;
                  }
                  value = input;
                }
              }

              op = InstanceCall(
                op.member,
                payload(op.receiver),
                op.positional.map(payload),
                {for (final e in op.named.entries) e.key: payload(e.value)},
                op.ownerType,
                op.typeArguments,
                null,
                const [],
                op.type,
              );
            }
            final names = op.named.keys.toList()..sort();
            final old = op.entryBinding;
            final signature =
                old?.signature ??
                FunctionType(closed(op.type), [
                  closed(op.receiver.type),
                  ...op.positional.map((v) => closed(v.type)),
                  for (final name in names) closed(op.named[name]!.type),
                  for (final _ in op.typeArguments) TypeMetadata.type,
                ]);
            final execution =
                old?.execution ??
                ExecutionSignature([
                  shapes.shapeOf(body, op.receiver),
                  for (final value in op.positional)
                    shapes.shapeOf(body, value),
                  for (final name in names)
                    shapes.shapeOf(body, op.named[name]!),
                  for (final _ in op.typeArguments) ExecutionShape.reference,
                ], shapes.shapeOf(body, site));
            final targets = <FunctionTarget, FunctionTarget>{};
            for (final source in sources) {
              final key = _entryKey(
                source,
                signature,
                execution,
                op.positional.length,
                names,
                op.typeArguments.length,
              );
              targets[source] = (_entries[key] ??= _build(
                program,
                source,
                signature,
                execution,
                op.positional.length,
                names,
                op.typeArguments.length,
              )).target;
              if (facts != null) {
                final key = (origin, source, execution);
                realizations.putIfAbsent(
                  key,
                  () => ProgramRealization(
                    key,
                    (canonical) => _rewrite(
                      canonical,
                      requested: {
                        origin: {source},
                      },
                    ),
                  ),
                );
              }
            }
            if (old != null &&
                old.entries.length == targets.length &&
                targets.entries.every((e) => old.entries[e.key] == e.value)) {
              continue;
            }
            final binding = MemberEntryBinding(
              signature,
              execution,
              op.positional.length,
              names,
              op.typeArguments.length,
              targets,
              executionShapes: ExecutionShapes(
                entries: {...shapes.entries, ..._executions},
                slots: shapes.slots,
              ),
            );
            if (old != null) {
              operations[site] = InstanceCall(
                op.member,
                op.receiver,
                op.positional,
                op.named,
                op.ownerType,
                op.typeArguments,
                binding,
                op.executionTypes,
                op.resultView,
              );
              continue;
            }
            // Evaluate descriptors and any caller-scoped result check at the
            // source Invoke, where its operands and original handler dominate.
            final inputs = op.inputs.toList();
            final parameters = <TypeParameterType>{
              ...op.type.freeTypeParameters,
              ...?op.ownerType?.freeTypeParameters,
              for (final input in inputs) ...input.type.freeTypeParameters,
              for (final type in op.typeArguments) ...type.freeTypeParameters,
            };
            final target = FunctionTarget(
              null,
              'memberInvocation',
              op.type,
              inputs.map((v) => v.type),
              typeParameters: parameters,
            );
            final entry = Block(target.parameterTypes);
            final mapped = {
              for (final (index, input) in inputs.indexed)
                input: entry.parameters[index],
            };
            final descriptors = [
              for (final type in op.typeArguments)
                entry.emit(
                  UncheckedCast(entry.emit(ReifyType(type)), TypeMetadata.type),
                ),
            ];
            final call = entry.emit(
              direct
                  ? DirectCall(targets.values.single, [
                      mapped[op.receiver]!,
                      ...op.positional.map((v) => mapped[v]!),
                      for (final name in names) mapped[op.named[name]!]!,
                      ...descriptors,
                    ])
                  : InstanceCall(
                      op.member,
                      mapped[op.receiver]!,
                      op.positional.map((v) => mapped[v]!),
                      {
                        for (final e in op.named.entries)
                          e.key: mapped[e.value]!,
                      },
                      op.ownerType,
                      op.typeArguments,
                      binding,
                      descriptors,
                      signature.result,
                    ),
            );
            final result = call.type == op.type
                ? call
                : entry.emit(TypeCast(call, op.type));
            entry.finish(
              result.type == .never ? Unreachable(result) : Return(result),
            );
            final implementation = IrFunction(
              target,
              [entry],
              origins: {call: body.originOf(site)},
              execution: FunctionExecution({
                for (final (index, input) in inputs.indexed)
                  entry.parameters[index]: shapes.shapeOf(body, input),
                call: execution.result,
              }),
            );
            lowered[site] = (
              body: implementation,
              arguments: inputs,
              environment: {for (final p in parameters) p: p},
              handler: switch (block.end) {
                Invoke(operation: final invoked, :final onThrow)
                    when identical(invoked, site) =>
                  onThrow,
                _ => null,
              },
            );
          }
        }
      }
      final rewritten = operations.isEmpty && lowered.isEmpty
          ? body
          : FunctionRewrite(
              body,
              executionShapes: shapes,
              operations: operations,
              lowered: lowered,
            ).run();
      changed |= !identical(rewritten, body);
      functions.add(rewritten);
    }
    if (!found.containsAll(requested.keys)) {
      throw StateError(
        'A member realization has no canonical language call site.',
      );
    }
    if (!changed) return program;
    final present = functions.map((f) => f.target).toSet();
    for (final body in [
      ..._entries.values,
      ..._bodies.values,
      ..._variants.values,
      ...types.functions,
    ]) {
      if (present.add(body.target)) functions.add(body);
    }
    return IrProgram(
      program.classes,
      functions,
      globals: program.globals,
      externals: program.externals.where((e) => !present.contains(e.target)),
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: ExecutionShapes(
        entries: {...shapes.entries, ..._executions},
        slots: shapes.slots,
      ),
    );
  }

  IrFunction _build(
    IrProgram program,
    FunctionTarget source,
    FunctionType signature,
    ExecutionSignature execution,
    int positionalCount,
    List<String> names,
    int typeCount,
  ) {
    final body = program.implementationOf(source);
    if (body == null ||
        source.isAbstract ||
        !source.signature.acceptsShape(positionalCount, names) ||
        source.typeParameters.length != typeCount) {
      throw StateError('A member entry needs its actual complete declaration.');
    }
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    final destination = shapes.entryOf(source);
    final target = _entryTargets.putIfAbsent(
      _entryKey(
        source,
        signature,
        execution,
        positionalCount,
        names,
        typeCount,
      ),
      () => FunctionTarget(
        null,
        'memberEntry${_entries.length}',
        signature.result,
        signature.parameters,
      ),
    );
    _executions[target] = execution;
    final entry = Block(target.parameterTypes);
    final raw = <TypeParameterType, Value>{};
    if (source.owner!.typeParameters.isNotEmpty) {
      if (types.values.runtime == null) {
        throw UnsupportedError(
          'Member owner arguments need the shared type runtime.',
        );
      }
      final actual = entry.emit(
        UncheckedCast(
          entry.emit(ObjectRuntimeType(entry.parameters.first, direct: true)),
          TypeMetadata.type,
        ),
      );
      for (final (index, parameter) in source.owner!.typeParameters.indexed) {
        raw[parameter] = entry.emit(
          NullCheck(
            entry.emit(
              DirectCall(types.relations.argumentOf(source.owner!, index), [
                actual,
              ]),
            ),
          ),
        );
      }
    }
    for (final (index, parameter) in source.typeParameters.indexed) {
      raw[parameter] =
          entry.parameters[1 + positionalCount + names.length + index];
    }
    final bindings = [
      for (final p in raw.keys)
        TypeBinding.checked(entry.emit(CheckedTypeArgument(p, raw[p]!, raw))),
    ];
    final inputShapes = {
      for (final (i, value) in entry.parameters.indexed)
        value: execution.parameters[i],
    };
    Value argument(
      Block block,
      Value value,
      ValueType type,
      ExecutionShape expected,
    ) {
      final actual = inputShapes[value] ?? shapes.shapeOf(null, value);
      if (actual.isScalar && expected.isReference) {
        value = block.emit(
          value is Constant ? ConstantCarrier(value) : MaterializeValue(value),
        );
      }
      if (!type.accepts(value.type)) value = block.emit(TypeCast(value, type));
      if (actual.isReference && expected.isScalar) {
        value = block.emit(ProjectValue(value, expected));
      }
      return value;
    }

    final supplied = source.signature.bind<Value>(
      entry.parameters.skip(1).take(positionalCount).toList(),
      {
        for (final (i, name) in names.indexed)
          name: entry.parameters[1 + positionalCount + i],
      },
      (index) => body.defaults[index]!,
    );
    final implementation = body is IrFunction
        ? _bodies.putIfAbsent(source, () {
            final target = _bodyTargets.putIfAbsent(
              source,
              () => FunctionTarget(
                null,
                source.name,
                source.returnType,
                source.parameterTypes,
                typeParameters: [
                  ...source.owner!.typeParameters,
                  ...source.typeParameters,
                ],
                declarationLocation: source.declarationLocation,
                executionSource: source,
              ),
            );
            _executions[target] = destination;
            return IrFunction(
              target,
              body.blocks,
              sourceLocations: body.sourceLocations,
              origins: body.originBindings.map(
                (site, origin) => MapEntry(
                  site,
                  origin.copiedAt(('execution-entry', target)),
                ),
              ),
              typeBindings: body.typeBindings,
              execution: body.execution,
              bodyKind: body.bodyKind,
              yieldType: body.yieldType,
              completionType: body.completionType,
            );
          }).target
        : source;
    final blocks = [entry];
    // Variable types alone do not establish a physical carrier. Only consider
    // an entry where a real scalar operand would otherwise be materialized,
    // and prove its exact runtime binder before executing a concrete body.
    final actualTypes = <TypeParameterType, ValueType>{};
    var compatible = true;
    for (final (i, value) in supplied.indexed) {
      final formal = source.signature.parameters[i];
      final carrier = inputShapes[value] ?? shapes.shapeOf(null, value);
      if (formal is! TypeParameterType ||
          !raw.containsKey(formal) ||
          !destination.parameters[i + 1].isReference ||
          !carrier.isScalar ||
          carrier != ExecutionShapes.forType(value.type) ||
          value.type.freeTypeParameters.isNotEmpty) {
        continue;
      }
      final concrete = value.type;
      compatible &= actualTypes.putIfAbsent(formal, () => concrete) == concrete;
    }
    // A finite set of actually demanded, closed scalar signatures. Lexical
    // closures still use their original captured environment and shared body.
    final concreteEntry =
        body is IrFunction &&
            body.bodyKind == FunctionBodyKind.synchronous &&
            body.closures.isEmpty &&
            body.execution == null &&
            !shapes.entries.containsKey(source) &&
            compatible &&
            raw.isNotEmpty &&
            actualTypes.length == raw.length &&
            actualTypes.entries.every(
              (e) => e.key.bound.substitute(actualTypes).accepts(e.value),
            )
        ? _concreteBody(body, actualTypes, shapes)
        : null;
    void invoke(
      Block block,
      FunctionTarget implementation,
      ExecutionSignature entryShape,
      Map<TypeParameterType, ValueType> environment,
    ) {
      final call = block.emit(
        DirectCall(
          implementation,
          [
            block.emit(
              UncheckedCast(
                entry.parameters.first,
                source.parameterTypes.first.substitute(environment),
              ),
            ),
            for (final (i, value) in supplied.indexed)
              argument(
                block,
                value,
                source.signature.parameters[i].substitute(environment),
                entryShape.parameters[i + 1],
              ),
          ],
          ownerType: implementation == source ? source.owner : null,
          typeArguments: [
            if (environment.isEmpty) ...[
              if (implementation != source) ...source.owner!.typeParameters,
              ...source.typeParameters,
            ],
          ],
        ),
      );
      if (call.type == .never) {
        block.finish(Unreachable(call));
      } else {
        final result = signature.result.accepts(call.type)
            ? call.type == signature.result
                  ? call
                  : block.emit(TypeView(call, signature.result))
            : block.emit(TypeCast(call, signature.result));
        block.finish(Return(result));
      }
    }

    if (concreteEntry == null) {
      invoke(entry, implementation, destination, const {});
    } else {
      final shared = Block();
      blocks.add(shared);
      var checked = entry;
      for (final binding in bindings) {
        final matched = Block();
        blocks.add(matched);
        checked.finish(
          Branch(
            checked.emit(
              Equals(
                binding.value,
                TypeConstant(actualTypes[binding.parameter]!),
              ),
            ),
            Jump(matched),
            Jump(shared),
          ),
        );
        checked = matched;
      }
      invoke(
        checked,
        concreteEntry.target,
        shapes.entryOf(concreteEntry.target),
        actualTypes,
      );
      invoke(shared, implementation, destination, const {});
    }
    return IrFunction(target, blocks, typeBindings: bindings);
  }

  IrFunction _concreteBody(
    IrFunction source,
    Map<TypeParameterType, ValueType> environment,
    ExecutionShapes shapes,
  ) {
    final declaration = source.target;
    final owner = declaration.owner!.substitute(environment) as ClassType;
    final signature = FunctionType(
      declaration.returnType.substitute(environment),
      declaration.parameterTypes.map((type) => type.substitute(environment)),
    );
    final key = (declaration, signature);
    return _variants.putIfAbsent(key, () {
      final target = _variantTargets.putIfAbsent(
        key,
        () => FunctionTarget(
          null,
          declaration.name,
          signature.result,
          signature.parameters,
          executionSource: declaration,
          declarationLocation: declaration.declarationLocation,
        ),
      );
      final entry = Block(target.parameterTypes);
      final call = entry.emit(
        DirectCall(
          declaration,
          entry.parameters,
          ownerType: owner,
          typeArguments: declaration.typeParameters.map((p) => environment[p]!),
        ),
      );
      entry.finish(call.type == .never ? Unreachable(call) : Return(call));
      final wrapper = IrFunction(
        target,
        [entry],
        origins: {
          call: source.originOf(source.entry).copiedAt((
            'concrete-body',
            target,
          )),
        },
      );
      return FunctionRewrite(
        wrapper,
        executionShapes: shapes,
        lowered: {
          call: (
            body: source,
            arguments: entry.parameters,
            environment: environment,
            handler: null,
          ),
        },
      ).run();
    });
  }
}
