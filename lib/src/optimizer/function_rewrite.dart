import 'package:dartc/ir.dart';

/// Rebuilds a function after proven value replacements or direct-call expansion.
///
/// Proven values do not erase the effects of their defining operations.
/// The unchanged function is returned by identity.
final class FunctionRewrite(
  final IrFunction function, {
  final Map<Value, Value> replacements = const {},

  /// Rebinds immutable constants, including nested defaults, before their uses.
  final Constant Function(Constant)? constants,

  /// New operations using source values and pure, nonthrowing input templates.
  /// Fresh inputs are evaluated at each replacement's original program point.
  final Map<Instruction, Instruction> operations = const {},

  /// Replaces an owned block's final transfer, admitting new successor blocks.
  /// New operations use source SSA values and inherit the replaced source origin.
  final Map<Block, Terminator> terminators = const {},

  /// Source sites for new instructions and blocks introduced by [terminators].
  /// Each origin belongs to the original function and preserves its inline chain.
  final Map<Object, Object> origins = const {},

  /// New block parameters, with a value supplied by each retained incoming edge.
  final Map<BlockParameter, ({Block block, Map<Jump, Value> incoming})> phis =
      const {},
  final Set<Instruction> nonReturning = const {},

  /// Operations that may disappear entirely when their results are unused.
  final Set<Instruction> discardable = const {},

  /// Retained operations proven unable to reach their exception handler.
  final Set<Instruction> nonThrowing = const {},

  /// Local throws proven not to record implicit state on their exception value.
  /// A newly captured trace is still required while its handler observes it.
  final Set<Throw> directThrows = const {},

  /// Checked entry values and type bindings for each expanded invocation.
  /// Bodies observing their caller frame cannot cross this boundary.
  /// Call-bound frame arguments are allowed only for unused entry parameters.
  final Map<
        Instruction,
        ({
          IrFunction body,
          List<Value> arguments,
          Map<TypeParameterType, ValueType> environment,
          Jump? handler,
        })
      >
      inlined =
      const {},
}) {
  final _origins = <Object, Object>{};
  late final _blocks = _sourceBlocks();

  Terminator _end(Block block) => terminators[block] ?? block.end;

  List<Block> _sourceBlocks() {
    final owned = function.blocks.toSet();
    if (terminators.keys.any((block) => !owned.contains(block))) {
      throw ArgumentError('A replacement terminator requires an owned block.');
    }
    final blocks = [...function.blocks];
    for (final MapEntry(key: origin, value: end) in terminators.entries) {
      if (end case Invoke(:final operation)) _origins[operation] = origin;
      final pending = end.successors.map((edge) => edge.target).toList();
      while (pending.isNotEmpty) {
        final block = pending.removeLast();
        if (!owned.add(block)) continue;
        blocks.add(block);
        _origins[block] = origin;
        for (final operation in block.instructions) {
          _origins[operation] = origin;
        }
        if (block.end case Invoke(:final operation)) {
          _origins[operation] = origin;
        }
        pending.addAll(block.successors.map((edge) => edge.target));
      }
    }
    if (origins.isEmpty) return blocks;
    Set<Object> sites(Iterable<Block> blocks) => {
      for (final block in blocks) ...[
        block,
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    };
    final original = sites(function.blocks),
        introduced = {
          ...sites(blocks),
          for (final end in terminators.values)
            if (end case Invoke(:final operation)) operation,
        };
    if (origins.entries.any(
      (entry) =>
          original.contains(entry.key) ||
          !introduced.contains(entry.key) ||
          !original.contains(entry.value),
    )) {
      throw ArgumentError(
        'New graph sites require an original function source site.',
      );
    }
    _origins.addAll(origins);
    return blocks;
  }

  /// Applies the replacements, removes dead paths and preserves source origins.
  /// [instructionSources] receives copied instructions' original function sites.
  IrFunction run({Map<Instruction, Instruction>? instructionSources}) {
    final (blocks: liveBlocks, :needed, :parameterSlots, :templates) =
        _demand();
    final added = <Block, List<BlockParameter>>{
      for (final block in liveBlocks)
        block: [
          for (final entry in phis.entries)
            if (entry.value.block == block && needed.contains(entry.key))
              entry.key,
        ],
    };
    var changed =
        inlined.isNotEmpty ||
        terminators.isNotEmpty ||
        added.values.any((values) => values.isNotEmpty);
    final blocks = <Block, Block>{
      for (final block in _blocks)
        if (liveBlocks.contains(block))
          block: Block([
            for (final i in parameterSlots[block]!) block.parameters[i].type,
            for (final parameter in added[block]!) parameter.type,
          ]),
    };
    final values = <Value, Value>{
      for (final block in liveBlocks)
        for (final (newIndex, oldIndex) in parameterSlots[block]!.indexed)
          block.parameters[oldIndex]: blocks[block]!.parameters[newIndex],
      for (final block in liveBlocks)
        for (final (i, parameter) in added[block]!.indexed)
          parameter:
              blocks[block]!.parameters[parameterSlots[block]!.length + i],
    };
    final instructions = <Block, List<Instruction>>{};
    final discardedEffects = <Instruction>{};
    final constantViews = <(ValueType, Object), TypeView>{};
    final localViews = <(Block, ValueType, Value), TypeView>{};
    final replacing = <Value>{};
    final copying = <Instruction>{};
    late Block current;
    final ends = <Block, Terminator>{};
    final locations = <Object, SourceLocation>{};
    final expansions = <Instruction, ({Block entry, Block exit})>{};
    late Value Function(Value) value;
    late Value Function(Value, Value) viewed;
    late Jump Function(Jump, {bool collapsed}) jump;

    void locate(
      Object source,
      Object copy,
      IrFunction owner, [
      Object? callSite,
    ]) {
      if (source is Instruction && copy is Instruction && owner == function) {
        instructionSources?[copy] = source;
      }
      final location =
          owner.sourceLocations[source] ??
          (identical(owner, function)
              ? owner.sourceLocations[_origins[source]]
              : null);
      if (identical(owner, function)) {
        if (location != null) locations[copy] = location;
      } else {
        locations[copy] = (location ?? SourceLocation(null)).inlinedAt(
          owner.target,
          function.sourceLocations[callSite] ?? SourceLocation(null),
        );
      }
    }

    Unreachable impossible(Value result, Block block) {
      if (result.type == .never || result is Instruction) {
        return Unreachable(result);
      }
      // The call site proves infeasible returns, including remaining callee arms.
      final proof = TypeView(result, result.type);
      instructions[block]!.add(proof);
      return Unreachable(proof);
    }

    Value expand(Instruction call) {
      final site = inlined[call]!;
      final body = site.body;
      final environment = site.environment;
      final live = ValueLiveness.source(body).liveIn[body.entry]!;
      final handler = site.handler == null ? null : jump(site.handler!);
      final allocation = call is Construct
          ? NewPayload(call.instantiatedType, const Constant.integer(0))
          : null;
      final linear = body.blocks.length == 1 && body.entry.end is Return;
      final copiedBlocks = {
        for (final block in body.blocks)
          block: Block(
            block == body.entry
                ? [if (allocation != null && handler != null) call.type]
                : block.parameters.map((p) => p.type.substitute(environment)),
          ),
      };
      final entry = copiedBlocks[body.entry]!;
      final start = allocation != null && handler != null ? Block() : entry;
      final join = linear ? null : Block([call.type]);
      for (final block in {...copiedBlocks.values, start, ?join}) {
        instructions[block] = [];
      }
      final resumed = {
        if (handler != null)
          for (final block in body.blocks)
            for (final operation in block.instructions)
              if (operation.mayThrow && operation.type != .never)
                operation: Block([operation.type.substitute(environment)]),
      };
      for (final block in resumed.values) {
        instructions[block] = [];
      }
      if (allocation != null) {
        locate(call, allocation, function);
        if (handler == null) {
          instructions[entry]!.add(allocation);
        } else {
          ends[start] = Invoke(
            allocation,
            onReturn: Jump(entry, [allocation]),
            onThrow: handler,
          );
        }
      }
      final Value? receiver = allocation == null
          ? null
          : handler == null
          ? allocation
          : entry.parameters.single;
      final locals = <Value, Value>{
        for (final block in body.blocks)
          if (block != body.entry)
            for (final (i, parameter) in block.parameters.indexed)
              parameter: copiedBlocks[block]!.parameters[i],
      };
      if (receiver != null) locals[body.entry.parameters.first] = receiver;
      final copied = <Instruction, Instruction>{};
      late Value Function(Value) read;
      Instruction clone(Instruction source) => copied.putIfAbsent(source, () {
        final result = source.mapInputs(read, environment: environment);
        locate(source, result, body, call);
        return result;
      });
      read = (source) {
        if (source is Constant ||
            source is UnwindValue ||
            source is CallFrameValue) {
          return source;
        }
        if (locals[source] case final result?) return result;
        if (source is Instruction) {
          return resumed[source]?.parameters.single ?? clone(source);
        }
        if (source is TestedValue) {
          return (clone(source.test) as TypeTest).refinement(source.outcome)!;
        }
        throw StateError('Unexpected value in an inlined graph.');
      };
      for (final (i, parameter)
          in body.entry.parameters.skip(allocation == null ? 0 : 1).indexed) {
        final argument = value(site.arguments[i]);
        final type = parameter.type.substitute(environment);
        if (argument.type == type || !live.contains(parameter)) {
          locals[parameter] = argument;
        } else {
          final view = TypeView(argument, type);
          instructions[entry]!.add(view);
          locals[parameter] = view;
        }
      }
      Jump edge(Jump source) {
        final casts = <Instruction>[];
        final arguments = <Value>[];
        for (final argument in source.arguments) {
          if (argument is TestedValue && resumed.containsKey(argument.test)) {
            final cast = UncheckedCast(
              read(argument.test.operand),
              argument.type.substitute(environment),
            );
            casts.add(cast);
            arguments.add(cast);
            locate(argument.test, cast, body, call);
          } else {
            arguments.add(read(argument));
          }
        }
        final next = Jump(copiedBlocks[source.target]!, arguments);
        if (casts.isEmpty) return next;
        // The invoked test's boolean crosses a block; narrow only on its selected edge.
        final narrowed = Block();
        instructions[narrowed] = casts;
        ends[narrowed] = next;
        return Jump(narrowed);
      }

      late Block exit;
      late Value result;
      for (final source in body.blocks) {
        var cursor = copiedBlocks[source]!;
        var stopped = false;
        for (final original in source.instructions) {
          final mapped = clone(original);
          if (handler != null && mapped.mayThrow) {
            final next = resumed[original];
            ends[cursor] = Invoke(
              mapped,
              onReturn: next == null ? null : Jump(next, [mapped]),
              onThrow: handler,
            );
            if (next == null) {
              stopped = true;
              break;
            }
            cursor = next;
          } else {
            instructions[cursor]!.add(mapped);
          }
        }
        locate(source, cursor, body, call);
        if (stopped) continue;
        switch (source.end) {
          case Return(:final value):
            var returned =
                receiver ??
                (value == null ? const Constant.nullValue() : read(value));
            if (body.target.requiresResultCheck) {
              final cast = TypeCast(returned, call.type);
              locate(source, cast, body, call);
              if (handler == null) {
                instructions[cursor]!.add(cast);
                returned = cast;
              } else {
                final next = Block([call.type]);
                instructions[next] = [];
                ends[cursor] = Invoke(
                  cast,
                  onReturn: Jump(next, [cast]),
                  onThrow: handler,
                );
                cursor = next;
                returned = next.parameters.single;
              }
            }
            if (linear) {
              exit = cursor;
              if (returned.type != call.type) {
                final view = TypeView(returned, call.type);
                locate(source, view, body, call);
                instructions[cursor]!.add(view);
                returned = view;
              }
              result = returned;
            } else {
              ends[cursor] = Jump(join!, [returned]);
            }
          case final Jump next:
            ends[cursor] = edge(next);
          case Branch(:final condition, :final ifTrue, :final ifFalse):
            ends[cursor] = Branch(read(condition), edge(ifTrue), edge(ifFalse));
          case Invoke(:final operation, :final onReturn, :final onThrow):
            ends[cursor] = Invoke(
              clone(operation),
              onReturn: onReturn == null ? null : edge(onReturn),
              onThrow: edge(onThrow),
            );
          case Throw(
            :final exception,
            :final stackTrace,
            :final onThrow,
            :final isRecorded,
          ):
            final error = read(exception);
            final trace = stackTrace == null ? null : read(stackTrace);
            final caught = onThrow == null ? handler : edge(onThrow);
            ends[cursor] = isRecorded
                ? Throw.recorded(error, trace, onThrow: caught)
                : Throw(error, stackTrace: trace, onThrow: caught);
          case ExhaustivenessFailure(:final onThrow):
            ends[cursor] = ExhaustivenessFailure(
              onThrow == null ? handler : edge(onThrow),
            );
          case Unreachable(:final cause):
            ends[cursor] = impossible(read(cause), cursor);
          case Await() || Yield() || YieldStream():
            throw ArgumentError('Normalize suspension before inlining.');
        }
      }
      if (!linear) {
        exit = join!;
        result = join.parameters.single;
      }
      expansions[call] = (entry: start, exit: exit);
      return result;
    }

    Instruction copy(Instruction original) {
      if (values[original] case final Instruction copied) return copied;
      if (!copying.add(original)) {
        throw ArgumentError('Cyclic operation templates.');
      }
      final template = operations[original] ?? original;
      final inputs = <Instruction, Instruction>{};
      Value input(Value operand) {
        if (operand is Instruction && templates.contains(operand)) {
          return inputs.putIfAbsent(operand, () {
            final result = operand.mapInputs(input);
            instructions[current]!.add(result);
            locate(original, result, function);
            return result;
          });
        }
        return viewed(operand, value(operand));
      }

      final result = template.mapInputs(input);
      copying.remove(original);
      changed |= !identical(template, original);
      values[original] = result;
      if (discardable.contains(original)) discardedEffects.add(result);
      locate(original, result, function);
      return result;
    }

    viewed = (original, actual) {
      if (original.type == actual.type) return actual;
      if (!original.type.accepts(actual.type)) {
        throw ArgumentError('Rewritten value violates its source type.');
      }
      if (actual is Constant) {
        return constantViews.putIfAbsent(
          (original.type, actual.structuralKey),
          () {
            final view = TypeView(actual, original.type);
            instructions[blocks[function.entry]!]!.insert(0, view);
            return view;
          },
        );
      }
      return localViews.putIfAbsent((current, original.type, actual), () {
        final view = TypeView(actual, original.type);
        instructions[current]!.add(view);
        return view;
      });
    };

    value = (original) {
      if (original is Constant) {
        final result = constants?.call(original) ?? original;
        if (!original.type.accepts(result.type)) {
          throw ArgumentError('A rewritten constant must preserve its type.');
        }
        changed |= !identical(result, original);
        return result;
      }
      if (original is UnwindValue || original is CallFrameValue) {
        return original;
      }
      final replacement = _replacement(original);
      if (!identical(original, replacement)) {
        if (!replacing.add(original)) {
          throw ArgumentError('Cyclic SSA replacements.');
        }
        final actual = value(replacement);
        replacing.remove(original);
        changed = true;
        return actual;
      }
      if (values[original] case final known?) return known;
      final Value result;
      if (original is Instruction && inlined.containsKey(original)) {
        result = expand(original);
      } else if (original is Instruction) {
        result = copy(original);
      } else if (original is AwaitResult) {
        result = AwaitResult(original.type);
      } else if (original is TestedValue) {
        result = (value(original.test) as TypeTest).refinement(
          original.outcome,
        )!;
      } else {
        throw StateError('Unexpected value in an IR graph.');
      }
      values[original] = result;
      return result;
    };
    Value refined(TestedValue refinement) {
      final operand = value(refinement.test.operand);
      if (refinement.type.accepts(operand.type)) return operand;
      final cast = UncheckedCast(operand, refinement.type);
      instructions[current]!.add(cast);
      locate(refinement.test, cast, function);
      return cast;
    }

    jump = (edge, {collapsed = false}) {
      Value argument(Value original) => collapsed && original is TestedValue
          ? refined(original)
          : value(original);
      return Jump(blocks[edge.target]!, [
        for (final i in parameterSlots[edge.target]!)
          argument(edge.arguments[i]),
        for (final parameter in added[edge.target]!)
          argument(phis[parameter]!.incoming[edge]!),
      ]);
    };

    Terminator branchEnd(Branch branch) {
      if (_sameEdge(branch.ifTrue, branch.ifFalse)) {
        changed = true;
        return jump(branch.ifTrue);
      }
      final condition = value(branch.condition);
      if (condition case ScalarConstant(value: final bool takeTrue)) {
        changed = true;
        final edge = takeTrue ? branch.ifTrue : branch.ifFalse;
        return jump(edge, collapsed: true);
      }
      return Branch(condition, jump(branch.ifTrue), jump(branch.ifFalse));
    }

    Terminator invokeEnd(Invoke invocation) {
      if (!needed.contains(invocation.operation)) {
        final normal = invocation.onReturn;
        if (normal == null || _never(invocation.operation)) {
          throw StateError('A non-returning operation cannot be discarded.');
        }
        changed = true;
        return jump(normal);
      }
      final template = operations[invocation.operation] ?? invocation.operation;
      if (!template.mayThrow || nonThrowing.contains(invocation.operation)) {
        changed = true;
        final operation = copy(invocation.operation);
        instructions[current]!.add(operation);
        final normal = invocation.onReturn;
        return normal == null || _never(invocation.operation)
            ? Unreachable(operation)
            : jump(normal);
      }
      final returns =
          invocation.onReturn != null && !_never(invocation.operation);
      changed |= invocation.onReturn != null && !returns;
      return Invoke(
        copy(invocation.operation),
        onReturn: returns ? jump(invocation.onReturn!) : null,
        onThrow: jump(invocation.onThrow),
      );
    }

    Terminator throwEnd(Throw original) {
      final handler = original.onThrow == null ? null : jump(original.onThrow!);
      if (directThrows.contains(original) &&
          handler != null &&
          (original.stackTrace != null ||
              !handler.arguments.contains(UnwindValue.stackTrace))) {
        changed = true;
        return Jump(handler.target, [
          for (final argument in handler.arguments)
            switch (argument) {
              UnwindValue.exception => value(original.exception),
              UnwindValue.stackTrace => value(original.stackTrace!),
              _ => argument,
            },
        ]);
      }
      final exception = value(original.exception);
      final trace = original.stackTrace == null
          ? null
          : value(original.stackTrace!);
      return original.isRecorded
          ? Throw.recorded(exception, trace, onThrow: handler)
          : Throw(exception, stackTrace: trace, onThrow: handler);
    }

    Terminator end(Terminator original) => switch (original) {
      Return(value: final returned) => Return(
        returned == null ? null : value(returned),
      ),
      final Jump edge => jump(edge),
      final Branch branch => branchEnd(branch),
      final Invoke invocation => invokeEnd(invocation),
      final Throw throwing => throwEnd(throwing),
      ExhaustivenessFailure(:final onThrow) => ExhaustivenessFailure(
        onThrow == null ? null : jump(onThrow),
      ),
      Unreachable(:final cause) => impossible(value(cause), current),
      Await(:final operand, :final result, :final onResume, :final onThrow) =>
        Await(
          value(operand),
          value(result) as AwaitResult,
          onResume: onResume == null ? null : jump(onResume),
          onThrow: onThrow == null ? null : jump(onThrow),
        ),
      Yield(value: final element, :final onResume, :final onCancel) => Yield(
        value(element),
        jump(onResume),
        onCancel: onCancel == null ? null : jump(onCancel),
      ),
      YieldStream(
        :final stream,
        :final onResume,
        :final onCancel,
        :final onThrow,
      ) =>
        YieldStream(
          value(stream),
          jump(onResume),
          onCancel: jump(onCancel),
          onThrow: onThrow == null ? null : jump(onThrow),
        ),
    };

    changed |=
        liveBlocks.length != _blocks.length ||
        parameterSlots.entries.any(
          (entry) => entry.value.length != entry.key.parameters.length,
        );
    for (final original in _blocks) {
      if (!liveBlocks.contains(original)) continue;
      current = blocks[original]!;
      instructions[current] = [];
      void emit(Instruction operation) {
        if (inlined.containsKey(operation)) {
          if (!expansions.containsKey(operation)) {
            values[operation] = expand(operation);
          }
          final fragment = expansions[operation]!;
          instructions[current]!.addAll(instructions.remove(fragment.entry)!);
          if (fragment.exit != fragment.entry) {
            ends[current] = ends.remove(fragment.entry)!;
            final source = inlined[operation]!.body;
            locate(source.entry, current, source, operation);
            current = fragment.exit;
          }
        } else {
          instructions[current]!.add(copy(operation));
        }
      }

      Instruction? last;
      for (final operation in original.instructions) {
        if (needed.contains(operation)) {
          emit(operation);
        } else {
          changed = true;
        }
        if (_never(operation)) {
          last = operation;
          break;
        }
      }
      if (last != null) {
        changed |=
            _end(original) is! Unreachable ||
            (_end(original) as Unreachable).cause != last;
        ends[current] = impossible(value(last), current);
        locate(original, current, function);
        continue;
      }
      final terminal = _end(original);
      if (terminal is Invoke && inlined.containsKey(terminal.operation)) {
        emit(terminal.operation);
        ends[current] = terminal.onReturn == null
            ? impossible(value(terminal.operation), current)
            : jump(terminal.onReturn!);
      } else {
        ends[current] = end(terminal);
      }
      locate(original, current, function);
    }

    final parameterOwners = {
      for (final block in instructions.keys)
        for (final parameter in block.parameters) parameter: block,
    };
    final usedOutside = <Value>{};
    for (final block in instructions.keys) {
      final terminal = ends[block]!;
      for (final operand in [
        for (final operation in [
          ...instructions[block]!,
          if (terminal case Invoke(:final operation)) operation,
        ])
          ...operation.inputs,
        ..._endValues(terminal),
      ]) {
        if (parameterOwners[operand] case final owner? when owner != block) {
          usedOutside.add(operand);
        }
      }
    }

    Jump thread(Jump original, {Value? condition, bool outcome = false}) {
      Value known(Value value) =>
          identical(value, condition) ? Constant.boolean(outcome) : value;
      var edge = original;
      if (condition != null &&
          edge.arguments.any((value) => identical(value, condition))) {
        edge = Jump(edge.target, edge.arguments.map(known));
      }
      final visited = <Block>{};
      while (instructions[edge.target]!.isEmpty &&
          !edge.target.parameters.any(usedOutside.contains)) {
        if (!visited.add(edge.target)) return original;
        Value bind(Value value) {
          final index = value is BlockParameter
              ? edge.target.parameters.indexOf(value)
              : -1;
          return known(index < 0 ? value : edge.arguments[index]);
        }

        final terminal = ends[edge.target]!;
        final Jump next;
        if (terminal is Jump) {
          next = terminal;
        } else if (terminal is Branch) {
          if (bind(terminal.condition) case ScalarConstant(
            value: final bool yes,
          )) {
            next = yes ? terminal.ifTrue : terminal.ifFalse;
          } else {
            break;
          }
        } else {
          break;
        }
        edge = Jump(next.target, next.arguments.map(bind));
      }
      changed |= !identical(edge, original);
      return edge;
    }

    for (final entry in ends.entries.toList()) {
      ends[entry.key] = switch (entry.value) {
        final Jump edge => thread(edge),
        Branch(:final condition, :final ifTrue, :final ifFalse) => Branch(
          condition,
          thread(ifTrue, condition: condition, outcome: true),
          thread(ifFalse, condition: condition, outcome: false),
        ),
        Invoke(:final operation, :final onReturn, :final onThrow) => Invoke(
          operation,
          onReturn: onReturn == null ? null : thread(onReturn),
          onThrow: thread(onThrow),
        ),
        Throw(
          isRecorded: true,
          :final exception,
          stackTrace: final trace,
          :final onThrow,
        ) =>
          Throw.recorded(
            exception,
            trace,
            onThrow: onThrow == null ? null : thread(onThrow),
          ),
        Throw(:final exception, :final stackTrace, :final onThrow) => Throw(
          exception,
          stackTrace: stackTrace,
          onThrow: onThrow == null ? null : thread(onThrow),
        ),
        ExhaustivenessFailure(:final onThrow) => ExhaustivenessFailure(
          onThrow == null ? null : thread(onThrow),
        ),
        Await(:final operand, :final result, :final onResume, :final onThrow) =>
          Await(
            operand,
            result,
            onResume: onResume == null ? null : thread(onResume),
            onThrow: onThrow == null ? null : thread(onThrow),
          ),
        Yield(:final value, :final onResume, :final onCancel) => Yield(
          value,
          thread(onResume),
          onCancel: onCancel == null ? null : thread(onCancel),
        ),
        YieldStream(
          :final stream,
          :final onResume,
          :final onCancel,
          :final onThrow,
        ) =>
          YieldStream(
            stream,
            thread(onResume),
            onCancel: thread(onCancel),
            onThrow: onThrow == null ? null : thread(onThrow),
          ),
        final terminal => terminal,
      };
    }

    final predecessors = <Block, int>{};
    for (final terminal in ends.values) {
      for (final edge in terminal.successors) {
        predecessors.update(
          edge.target,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final block in instructions.keys.toList()) {
      if (!instructions.containsKey(block)) continue;
      while (ends[block] is Jump) {
        final target = (ends[block]! as Jump).target;
        if (target == block ||
            target.parameters.isNotEmpty ||
            predecessors[target] != 1 ||
            target == blocks[function.entry]) {
          break;
        }
        instructions[block]!.addAll(instructions.remove(target)!);
        ends[block] = ends.remove(target)!;
        if (locations[target] case final location?) locations[block] = location;
        changed = true;
      }
    }

    final reachable = <Block>{}, pending = [blocks[function.entry]!];
    while (pending.isNotEmpty) {
      final block = pending.removeLast();
      if (reachable.add(block)) {
        pending.addAll(ends[block]!.successors.map((edge) => edge.target));
      }
    }
    changed |= reachable.length != instructions.length;
    final used = <Value>{};
    void retain(Value operand) {
      if (!used.add(operand)) return;
      if (operand is Instruction) operand.inputs.forEach(retain);
      if (operand is TestedValue) retain(operand.test);
    }

    for (final block in reachable) {
      for (final operation in instructions[block]!) {
        if (operation.effects.isNotEmpty &&
            !discardedEffects.contains(operation)) {
          retain(operation);
        }
      }
      _endValues(ends[block]!).forEach(retain);
    }
    final owned = <Object>{...reachable};
    for (final block in reachable) {
      for (final operation in instructions[block]!) {
        if (used.contains(operation)) {
          block.emit(operation);
          owned.add(operation);
        } else {
          changed = true;
        }
      }
      block.finish(ends[block]!);
      if (block.end case Invoke(:final operation)) owned.add(operation);
    }
    final defaults = {
      for (final entry in function.defaults.entries)
        entry.key: value(entry.value) as Constant,
    };
    if (!changed) return function;
    return IrFunction(
      function.target,
      reachable,
      defaults: defaults,
      bodyKind: function.bodyKind,
      yieldType: function.yieldType,
      completionType: function.completionType,
      sourceLocations: {
        for (final e in locations.entries)
          if (owned.contains(e.key)) e.key: e.value,
      },
    );
  }

  bool _never(Instruction operation) =>
      nonReturning.contains(operation) ||
      (operations[operation] ?? operation).type == .never;

  Value _replacement(Value value) {
    final visited = <Value>{};
    var replacement = replacements[value];
    while (replacement != null && !identical(value, replacement)) {
      if (!visited.add(value)) throw ArgumentError('Cyclic SSA replacements.');
      if (value is TypeView &&
          (identical(value.operand, replacement) ||
              value.operand is Constant &&
                  replacement is Constant &&
                  (value.operand as Constant).structuralKey ==
                      replacement.structuralKey)) {
        break;
      }
      value = replacement;
      replacement = replacements[value];
    }
    return value;
  }

  ({
    Set<Block> blocks,
    Set<Value> needed,
    Map<Block, List<int>> parameterSlots,
    Set<Instruction> templates,
  })
  _demand() {
    final sourceValues = <Value>{
      for (final block in _blocks) ...[
        ...block.parameters,
        ...block.instructions,
        if (_end(block) case Invoke(:final operation)) operation,
        if (_end(block) case Await(:final result)) result,
      ],
    };
    bool owns(Value value) =>
        sourceValues.contains(value) ||
        value is TestedValue && sourceValues.contains(value.test);
    final templates = <Instruction>{};
    for (final entry in operations.entries) {
      final visiting = <Instruction>{};
      bool available(Value value) {
        if (value == entry.key) return false;
        if (value is Constant ||
            value is CallFrameValue ||
            owns(value) ||
            phis.containsKey(value)) {
          return true;
        }
        if (value is! Instruction ||
            value.effects.isNotEmpty ||
            !visiting.add(value)) {
          return false;
        }
        final valid = value.inputs.every(available);
        visiting.remove(value);
        if (valid) templates.add(value);
        return valid;
      }

      if (!owns(entry.key) ||
          !entry.key.type.accepts(entry.value.type) ||
          inlined.containsKey(entry.key) ||
          !entry.value.inputs.every(available)) {
        throw ArgumentError(
          'Operation templates require available SSA inputs or pure input expressions.',
        );
      }
    }
    if (inlined.isNotEmpty) {
      final dominance = ValueDominance(function);
      for (final MapEntry(key: call, value: site) in inlined.entries) {
        if (site.body.observesCallerFrame) {
          throw ArgumentError(
            'Inlined bodies cannot observe their caller frame.',
          );
        }
        late final live = ValueLiveness.source(site.body)
            .liveIn[site.body.entry]!;
        if ((call is! DirectCall &&
                call is! FunctionCall &&
                call is! Construct) ||
            !owns(call) ||
            site.arguments.indexed.any((entry) {
              final (index, value) = entry;
              if (value is CallFrameValue) {
                return call is! DirectCall ||
                    !call.inputs.contains(value) ||
                    index >= site.body.entry.parameters.length ||
                    live.contains(site.body.entry.parameters[index]);
              }
              return value is! Constant && !dominance.before(value, call);
            })) {
          throw ArgumentError(
            'Inlined entries require dominating caller arguments.',
          );
        }
        if (call
            case DirectCall(:final target) ||
                Construct(initializer: final target) ||
                FunctionCall(target: final target?)
            when target.implementation != site.body.target) {
          throw ArgumentError(
            'Inlined body differs from the proven call target.',
          );
        }
        if (call is Construct &&
            call.instantiatedType.freeTypeParameters.isNotEmpty) {
          throw ArgumentError(
            'Inlined construction requires its actual instance type.',
          );
        }
        final parameters = site.body.target.parameterTypes
            .skip(call is Construct ? 1 : 0)
            .toList();
        if (parameters.length != site.arguments.length ||
            parameters.indexed.any(
              (entry) => !entry.$2
                  .substitute(site.environment)
                  .accepts(site.arguments[entry.$1].type),
            )) {
          throw ArgumentError('Inlined arguments violate the entry types.');
        }
      }
    }
    final edges = {for (final block in _blocks) ..._end(block).successors};
    for (final MapEntry(key: parameter, value: phi) in phis.entries) {
      if (sourceValues.contains(parameter) ||
          phi.block == function.entry ||
          !_blocks.contains(phi.block)) {
        throw ArgumentError(
          'A new phi must define a fresh parameter in a non-entry block.',
        );
      }
      for (final MapEntry(key: edge, value: value) in phi.incoming.entries) {
        if (!edges.contains(edge) ||
            edge.target != phi.block ||
            !parameter.type.accepts(value.type) ||
            value is! Constant &&
                value is! UnwindValue &&
                !owns(value) &&
                !phis.containsKey(value)) {
          throw ArgumentError(
            'Phi inputs must belong to their incoming edge and match the parameter type.',
          );
        }
      }
    }
    for (final MapEntry(key: original, value: replacement)
        in replacements.entries) {
      if (!owns(original) ||
          replacement is! Constant &&
              !owns(replacement) &&
              !phis.containsKey(replacement) ||
          !original.type.accepts(replacement.type)) {
        throw ArgumentError(
          'Replacement must belong to this function and preserve its type contract.',
        );
      }
    }
    if ([
      ...discardable,
      ...nonReturning,
      ...nonThrowing,
      ...inlined.keys,
    ].any((value) => !owns(value))) {
      throw ArgumentError('A rewrite obligation belongs to another function.');
    }
    if (directThrows.any(
      (throwing) =>
          throwing.onThrow == null ||
          !_blocks.any((block) => identical(_end(block), throwing)),
    )) {
      throw ArgumentError('A direct throw requires an owned local handler.');
    }
    final needed = <Value>{};
    Iterable<Jump> outgoing(Block block) {
      if (block.instructions.any(_never)) return const [];
      final end = _end(block);
      if (end is Branch) {
        if (_sameEdge(end.ifTrue, end.ifFalse)) return [end.ifTrue];
        if (_replacement(end.condition) case ScalarConstant(
          value: final bool test,
        )) {
          return [test ? end.ifTrue : end.ifFalse];
        }
      }
      if (end is Invoke) {
        if (!(operations[end.operation] ?? end.operation).mayThrow ||
            nonThrowing.contains(end.operation)) {
          return _never(end.operation) ? const [] : [?end.onReturn];
        }
        if (_never(end.operation)) return [end.onThrow];
        if (discardable.contains(end.operation) &&
            !needed.contains(end.operation)) {
          return [?end.onReturn];
        }
      }
      return end.successors;
    }

    final liveBlocks = <Block>{};
    int previousDemand;
    do {
      previousDemand = needed.length;
      liveBlocks.clear();
      final queued = [function.entry];
      final incoming = <BlockParameter, List<Value>>{};
      while (queued.isNotEmpty) {
        final block = queued.removeLast();
        if (!liveBlocks.add(block)) continue;
        for (final edge in outgoing(block)) {
          queued.add(edge.target);
          for (final (i, argument) in edge.arguments.indexed) {
            (incoming[edge.target.parameters[i]] ??= []).add(argument);
          }
          for (final entry in phis.entries) {
            if (entry.value.block != edge.target) continue;
            final argument = entry.value.incoming[edge];
            if (argument == null) {
              throw ArgumentError(
                'A phi is missing an executable predecessor.',
              );
            }
            (incoming[entry.key] ??= []).add(argument);
          }
        }
      }
      final uses = <Value>[
        for (final parameter in needed.whereType<BlockParameter>())
          ...?incoming[parameter],
      ];
      final requiredOperations = <Instruction>{};
      for (final block in liveBlocks) {
        Instruction? stop;
        for (final operation in block.instructions) {
          if ((operations[operation] ?? operation).effects.isNotEmpty &&
                  !discardable.contains(operation) ||
              _never(operation)) {
            uses.add(operation);
            requiredOperations.add(operation);
          }
          if (_never(operation)) {
            stop = operation;
            break;
          }
        }
        if (stop != null) continue;
        final end = _end(block);
        switch (end) {
          case Return(:final value?):
            uses.add(value);
          case Branch(:final condition, :final ifTrue, :final ifFalse):
            if (!_sameEdge(ifTrue, ifFalse)) uses.add(condition);
          case Invoke(:final operation):
            if (!discardable.contains(operation) || _never(operation)) {
              uses.add(operation);
              requiredOperations.add(operation);
            }
          case Throw(:final exception, :final stackTrace):
            uses.add(exception);
            if (stackTrace != null) uses.add(stackTrace);
          case Unreachable(:final cause):
            uses.add(cause);
          case Await(:final operand):
            uses.add(operand);
          case Yield(:final value):
            uses.add(value);
          case YieldStream(:final stream):
            uses.add(stream);
          default:
            break;
        }
      }
      while (uses.isNotEmpty) {
        final original = uses.removeLast();
        final operand = _replacement(original);
        if (!identical(original, operand) &&
            !requiredOperations.contains(original)) {
          uses.add(operand);
          continue;
        }
        if (!needed.add(original)) continue;
        if (!identical(original, operand)) uses.add(operand);
        if (original is Instruction) {
          uses.addAll((operations[original] ?? original).inputs);
          uses.addAll(inlined[original]?.arguments ?? const []);
        }
        if (original is BlockParameter) {
          uses.addAll(incoming[original] ?? const []);
        }
        if (original is TestedValue) {
          uses.addAll([original.test, original.test.operand]);
        }
      }
    } while (needed.length != previousDemand);
    final parameterSlots = {
      for (final block in liveBlocks)
        block: [
          for (final (i, parameter) in block.parameters.indexed)
            if (block == function.entry || needed.contains(parameter)) i,
        ],
    };
    for (final value in replacements.keys) {
      _replacement(value);
    }
    return (
      blocks: liveBlocks,
      needed: needed,
      parameterSlots: parameterSlots,
      templates: templates,
    );
  }
}

Iterable<Value> _endValues(Terminator terminal) => [
  for (final edge in terminal.successors) ...edge.arguments,
  ...switch (terminal) {
    Return(:final value) => [?value],
    Branch(:final condition) => [condition],
    Invoke(:final operation) => [operation],
    Throw(:final exception, :final stackTrace) => [exception, ?stackTrace],
    Unreachable(:final cause) => [cause],
    Await(:final operand) => [operand],
    Yield(:final value) => [value],
    YieldStream(:final stream) => [stream],
    _ => const <Value>[],
  },
];

bool _sameEdge(Jump left, Jump right) =>
    left.target == right.target &&
    left.arguments.length == right.arguments.length &&
    left.arguments.indexed.every(
      (entry) => entry.$2 == right.arguments[entry.$1],
    );
