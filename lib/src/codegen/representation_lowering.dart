import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Places physical carrier changes in their actual source control flow.
///
/// This pass does not add execution roots. Allocating adaptations retain an
/// existing Invoke's handler; ambiguous source scopes must contain an explicit
/// MaterializeValue before lowering instead of guessing another block's catch.
final class RepresentationLowering() extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final recipes = <Object, ProgramRealization>{};
    return ProgramTransform((facts) {
      for (final body in facts.program.functions) {
        if (!facts.definitions.contains(body.target) || body.execution != null)
          continue;
        final target = body.target;
        final key = (RepresentationLowering, target);
        recipes.putIfAbsent(
          key,
          () => ProgramRealization(
            key,
            (canonical) => _lower(canonical, [target], requested: const {}),
          ),
        );
      }
      return _lower(
        facts.program,
        facts.definitions,
        facts: facts,
        realized: (origin, actual, expected) {
          final source = origin.source;
          final key = (RepresentationLowering, source, actual, expected);
          recipes.putIfAbsent(
            key,
            () => ProgramRealization(
              key,
              (canonical) => _lower(
                canonical,
                canonical.functions
                    .where((body) => body.target == source.owner ||
                        body.origins.values.any((copy) => copy.source == source))
                    .map((body) => body.target),
                requested: {source},
              ),
            ),
          );
        },
      );
    }, realizations: () => recipes.values);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  /// Normalizes the complete supplied bodies without a reachability assumption.
  IrProgram lower(IrProgram program, Iterable<FunctionTarget> definitions) =>
      _lower(program, definitions);

  IrProgram _lower(
    IrProgram program,
    Iterable<FunctionTarget> definitions, {
    ProgramFlowFacts? facts,
    Set<IrOrigin>? requested,
    void Function(IrOrigin, ExecutionShape, ExecutionShape)? realized,
  }) {
    final selected = definitions.toSet();
    final shapes = program.executionShapes ?? ExecutionShapes.defaults;
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      final current = selected.contains(function.target)
          ? _Body(
              function,
              shapes,
              facts: facts,
              requested: requested,
              realized: realized,
            ).run()
          : function;
      changed |= !identical(current, function);
      functions.add(current);
    }
    if (!changed && program.executionShapes != null) return program;
    return IrProgram(
      program.classes,
      functions,
      globals: program.globals,
      externals: program.externals,
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: shapes,
    );
  }
}

final class _Body(
  final IrFunction source,
  final ExecutionShapes shapes, {
  final ProgramFlowFacts? facts,
  final Set<IrOrigin>? requested,
  final void Function(IrOrigin, ExecutionShape, ExecutionShape)? realized,
}) {
  final blocks = <Block>[];
  final values = <Value, Value>{};
  final carriers = <Value, ExecutionShape>{};
  final clones = <Instruction, Instruction>{};
  final locations = <Object, SourceLocation>{};
  final origins = <Object, IrOrigin>{};
  final demandedOperations = <Instruction>{};
  final demandedEdges = <Jump>{};
  final demandedEnds = <Block>{};
  late final targets = {
    for (final block in source.blocks)
      block: fresh(block.parameters.map((value) => value.type)),
  };
  late Block cursor;
  var changed = false;
  late final scoped = source.blocks.any(
    (block) => switch (block.end) {
      Invoke(:final operation) => facts?.reachesOperation(operation) ?? true,
      Throw(onThrow: != null) => reachesEnd(block),
      _ => false,
    },
  );

  bool selected(Object site) =>
      requested == null || requested!.contains(source.originOf(site).source);
  bool reachesOperation(Instruction operation) =>
      selected(operation) && (facts?.reachesOperation(operation) ?? true);
  bool reachesEdge(Jump edge) =>
      selected(edge) && (facts?.reachesEdge(edge) ?? true);
  bool reachesEnd(Block block) =>
      selected(block) &&
      (facts == null ||
          facts!.reachesBlock(block) &&
              (block.instructions.isEmpty ||
                  facts!.exitsOf(block.instructions.last).normal));
  bool get partial => facts != null || requested != null;

  Jump checkedEdge(Block target, Iterable<Value> arguments) {
    final edge = Jump(target, arguments);
    demandedEdges.add(edge);
    return edge;
  }

  void finish(Terminator end, {required bool demanded}) {
    if (demanded) demandedEnds.add(cursor);
    cursor.finish(end);
  }

  Block fresh([Iterable<ValueType> parameters = const []]) {
    final block = Block(parameters);
    blocks.add(block);
    return block;
  }

  void locate(Object original, Object mapped) {
    origins[mapped] = source.originOf(original);
    if (source.sourceLocations[original] case final location?) {
      locations[mapped] = location;
    }
  }

  ExecutionShape shape(Value value) =>
      shapes.shapeOf(source, value, values: carriers);

  Value scalarPayload(Value value) {
    final actual = shape(value);
    while (true) {
      final operand = switch (value) {
        TypeView(:final operand) || UncheckedCast(:final operand) => operand,
        _ => null,
      };
      if (operand == null) break;
      if (!value.type.accepts(operand.type) || shape(operand) != actual) break;
      value = operand;
    }
    return value;
  }

  Value read(Value value) => switch (value) {
    Constant() || UnwindValue() || CallFrameValue() => value,
    TestedValue(:final test, :final outcome) =>
      (clones[test] as TypeTest).refinement(outcome)!,
    _ =>
      values[value] ??
          (throw StateError('Execution rewrite used an unavailable value.')),
  };

  Value adapt(
    Value value,
    ExecutionShape expected,
    Object origin,
    Jump? handler,
  ) {
    final actual = shape(value);
    if (actual == expected) return value;
    realized?.call(source.originOf(origin), actual, expected);
    changed = true;
    final Instruction conversion;
    if (expected.isReference && actual.isScalar) {
      final payload = scalarPayload(value);
      if (payload is Constant) {
        conversion = ConstantCarrier(payload);
      } else {
        if (handler == null && scoped) {
          throw StateError(
            'Allocating execution conversion needs its original exception scope in ${source.target.name}.',
          );
        }
        conversion = MaterializeValue(payload);
      }
    } else if (actual.isReference && expected.isScalar) {
      conversion = ProjectValue(value, expected);
    } else {
      throw UnsupportedError(
        'Execution component adaptation requires an explicit implementation.',
      );
    }
    carriers[conversion] = expected;
    demandedOperations.add(conversion);
    locate(origin, conversion);
    if (conversion.mayThrow && handler != null) {
      final next = fresh([conversion.type]);
      carriers[next.parameters.single] = expected;
      cursor.finish(
        Invoke(
          conversion,
          onReturn: checkedEdge(next, [conversion]),
          onThrow: handler,
        ),
      );
      locate(origin, cursor);
      cursor = next;
      if (next.parameters.single.type == value.type) {
        return next.parameters.single;
      }
      final view = cursor.emit(TypeView(next.parameters.single, value.type));
      carriers[view] = expected;
      return view;
    }
    cursor.emit(conversion);
    if (conversion.type == value.type) return conversion;
    final view = cursor.emit(TypeView(conversion, value.type));
    carriers[view] = expected;
    return view;
  }

  Jump edge(Jump original, {Jump? handler}) {
    final arguments = original.arguments.map(read).toList();
    if (!reachesEdge(original)) {
      final mapped = Jump(targets[original.target]!, arguments);
      locate(original, mapped);
      return mapped;
    }
    final expected = original.target.parameters
        .map((value) => shapes.shapeOf(source, value))
        .toList();
    if (arguments.indexed.every(
      (entry) => shape(entry.$2) == expected[entry.$1],
    )) {
      final mapped = checkedEdge(targets[original.target]!, arguments);
      locate(original, mapped);
      return mapped;
    }
    // Preserve the scalar proof before crossing an adapting edge. A broad
    // language view is not a scalar payload type for the new block parameter.
    // The same value reaches the destination after its explicit conversion.
    for (final (index, argument) in arguments.indexed) {
      if (expected[index].isReference && shape(argument).isScalar) {
        arguments[index] = scalarPayload(argument);
      }
    }
    final previous = cursor;
    final bridge = fresh(arguments.map((value) => value.type));
    for (final (index, parameter) in bridge.parameters.indexed) {
      carriers[parameter] = shape(arguments[index]);
    }
    cursor = bridge;
    final converted = <Value>[
      for (final (index, parameter) in bridge.parameters.indexed)
        adapt(parameter, expected[index], original, handler),
    ];
    cursor.finish(checkedEdge(targets[original.target]!, converted));
    cursor = previous;
    final mapped = checkedEdge(bridge, arguments);
    locate(original, mapped);
    return mapped;
  }

  Instruction operation(Instruction original, Jump? handler) {
    final demanded = reachesOperation(original);
    final inputs = original.inputs.toList();
    final expected = shapes.inputShapesOf(source, original).toList();
    if (original is TypeView ||
        original is UncheckedCast ||
        original is TypeCast ||
        original is NullCheck ||
        original is KeepAlive) {
      expected[0] = shape(read(inputs.single));
    }
    if (inputs.length != expected.length) {
      throw StateError('Execution operand shape arity mismatch.');
    }
    final converted = <Value>[
      for (final (index, input) in inputs.indexed)
        demanded
            ? adapt(read(input), expected[index], original, handler)
            : read(input),
    ];
    var index = 0;
    final result = original.mapInputs((input) {
      if (index >= inputs.length || !identical(inputs[index], input)) {
        throw StateError(
          'Execution rewrite requires ordered operation inputs.',
        );
      }
      return converted[index++];
    });
    if (index != inputs.length) throw StateError('Unmapped execution operand.');
    clones[original] = result;
    if (demanded) demandedOperations.add(result);
    locate(original, result);
    carriers[result] = switch (result) {
      TypeView(:final operand) ||
      UncheckedCast(:final operand) ||
      TypeCast(:final operand) ||
      NullCheck(:final operand) => shape(operand),
      _ => shapes.shapeOf(source, original),
    };
    return result;
  }

  Value result(Instruction original, Value value, Jump? handler) {
    return value;
  }

  IrFunction run() {
    if (source.bodyKind != .synchronous) {
      throw StateError('Normalize suspension before execution shapes.');
    }
    for (final block in source.blocks) {
      final target = targets[block]!;
      for (final (index, parameter) in block.parameters.indexed) {
        values[parameter] = target.parameters[index];
        origins[target.parameters[index]] = source.originOf(parameter);
        carriers[target.parameters[index]] = block == source.entry
            ? shapes.entryOf(source.target).parameters[index]
            : shapes.shapeOf(source, parameter);
      }
    }
    // SSA source block ordering is not necessarily dominance ordering.
    final pending = source.blocks.toSet();
    final order = <Block>[];
    void visit(Block block) {
      if (!pending.remove(block)) return;
      order.add(block);
      for (final edge in block.successors) {
        visit(edge.target);
      }
    }

    visit(source.entry);
    // Dominating instruction values can be cloned lazily only after the source
    // block has been emitted; depth-first order respects ordinary dominance.
    for (final block in order) {
      cursor = targets[block]!;
      locate(block, cursor);
      for (final instruction in block.instructions) {
        final copied = operation(instruction, null);
        cursor.emit(copied);
        values[instruction] = result(instruction, copied, null);
      }
      final demanded = reachesEnd(block);
      switch (block.end) {
        case Return(:final value):
          finish(
            Return(
              demanded
                  ? adapt(
                      read(value ?? const Constant.nullValue()),
                      shapes.entryOf(source.target).result,
                      block,
                      null,
                    )
                  : read(value ?? const Constant.nullValue()),
            ),
            demanded: demanded,
          );
        case final Jump next:
          cursor.finish(edge(next));
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          final predicate = demanded
              ? adapt(read(condition), ExecutionShape.word, block, null)
              : read(condition);
          finish(
            Branch(predicate, edge(ifTrue), edge(ifFalse)),
            demanded: demanded,
          );
        case Invoke(:final operation, :final onReturn, :final onThrow):
          final handler = edge(onThrow);
          final copied = this.operation(operation, handler);
          if (copied.mayThrow) {
            if (onReturn == null) {
              cursor.finish(Invoke(copied, onReturn: null, onThrow: handler));
              break;
            }
            final next = fresh([copied.type]);
            carriers[next.parameters.single] = carriers[copied]!;
            cursor.finish(
              Invoke(
                copied,
                onReturn: reachesEdge(onReturn)
                    ? checkedEdge(next, [copied])
                    : Jump(next, [copied]),
                onThrow: handler,
              ),
            );
            cursor = next;
            values[operation] = result(
              operation,
              next.parameters.single,
              handler,
            );
          } else {
            changed = true;
            cursor.emit(copied);
            values[operation] = result(operation, copied, handler);
          }
          cursor.finish(
            onReturn == null
                ? Unreachable(values[operation]!)
                : edge(onReturn, handler: handler),
          );
        case Throw(
          :final exception,
          :final stackTrace,
          :final onThrow,
          :final isRecorded,
        ):
          final error = demanded
              ? adapt(
                  read(exception),
                  ExecutionShape.reference,
                  block,
                  onThrow == null ? null : edge(onThrow),
                )
              : read(exception);
          final trace = stackTrace == null ? null : read(stackTrace);
          final target = onThrow == null ? null : edge(onThrow);
          finish(
            isRecorded
                ? Throw.recorded(error, trace, onThrow: target)
                : Throw(error, stackTrace: trace, onThrow: target),
            demanded: demanded,
          );
        case Unreachable(:final cause):
          cursor.finish(Unreachable(read(cause)));
        case ExhaustivenessFailure(:final onThrow):
          cursor.finish(
            ExhaustivenessFailure(onThrow == null ? null : edge(onThrow)),
          );
        case Await() || Yield() || YieldStream():
          throw StateError('Normalize suspension before execution shapes.');
      }
    }
    if (!changed && source.execution != null) {
      shapes.verify(
        source,
        operationIncluded: partial ? reachesOperation : null,
        edgeIncluded: partial ? reachesEdge : null,
        endIncluded: partial ? reachesEnd : null,
      );
      return source;
    }
    final reachable = <Block>{};
    void retain(Block block) {
      if (!reachable.add(block)) return;
      for (final edge in block.successors) {
        retain(edge.target);
      }
    }

    retain(targets[source.entry]!);
    final owned = <Object>{
      for (final block in reachable) ...[
        block,
        ...block.parameters,
        ...block.instructions,
        ...block.successors,
        if (block.end case Invoke(:final operation)) operation,
      ],
    };
    final rewritten = IrFunction(
      source.target,
      blocks.where(reachable.contains),
      defaults: source.defaults,
      execution: FunctionExecution({
        for (final entry in carriers.entries)
          if (owned.contains(entry.key)) entry.key: entry.value,
      }),
      sourceLocations: {
        for (final entry in locations.entries)
          if (owned.contains(entry.key)) entry.key: entry.value,
      },
      origins: {
        for (final entry in origins.entries)
          if (owned.contains(entry.key)) entry.key: entry.value,
      },
      typeBindings: [
        for (final binding in source.typeBindings)
          binding.remap(
            clones[binding.check] as CheckedTypeArgument,
            read(binding.value),
          ),
      ],
    );
    shapes.verify(
      rewritten,
      operationIncluded: partial ? demandedOperations.contains : null,
      edgeIncluded: partial ? demandedEdges.contains : null,
      endIncluded: partial ? demandedEnds.contains : null,
    );
    return rewritten;
  }
}
