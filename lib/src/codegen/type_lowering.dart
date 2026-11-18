import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'checked_casts.dart';
import 'program_layout.dart';
import 'type_implementations.dart';

/// Introduces executable type checks and reification before specialization.
///
/// Generic calls already carry their lexical type arguments in IR. A bare
/// lexical reification reads that environment; projection, construction and
/// failure algorithms instead become ordinary calls with actual operands.
final class TypeLowering(
  final TypeImplementations implementations, {
  required final FunctionTarget? failure,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final state = _TypeLowering(
      implementations,
      CheckedCasts(failure: failure),
    );
    return ProgramTransform(
      state.lower,
      normalize: state.normalize,
      realizations: () => state.realizations.values,
    );
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _TypeLowering(
  final TypeImplementations implementations,
  final CheckedCasts casts,
) {
  final _installed = <FunctionTarget, IrFunction>{};
  final _boundChecks = <Object, IrFunction>{};
  final realizations = <Object, ProgramRealization>{};

  IrProgram normalize(IrProgram program) {
    implementations.rebind(implementations.values.runtime?.rebind(program));
    implementations.extend(program.classes.map((c) => c.type));
    return _install(program, program.functions);
  }

  IrProgram _install(IrProgram program, Iterable<IrFunction> functions) {
    final replacements = <FunctionTarget, IrFunction>{};
    for (final body in [...implementations.functions, ..._boundChecks.values]) {
      if (program.implementationOf(body.target) is! IrFunction ||
          !identical(_installed[body.target], body)) {
        replacements[body.target] = body;
        _installed[body.target] = body;
      }
    }
    if (replacements.isEmpty && identical(functions, program.functions)) {
      return program;
    }
    final result = IrProgram(
      program.classes,
      [
        for (final body in functions)
          if (!replacements.containsKey(body.target)) body,
        ...replacements.values,
      ],
      globals: program.globals,
      nativeBoundaries: program.nativeBoundaries,
      executionShapes: program.executionShapes,
      externals: program.externals.where(
        (e) => !replacements.containsKey(e.target),
      ),
    );
    implementations.rebind(implementations.values.runtime?.rebind(result));
    return result;
  }

  IrProgram lower(ProgramFlowFacts facts) =>
      _lower(facts.program, facts: facts);

  IrProgram _lower(
    IrProgram program, {
    ProgramFlowFacts? facts,
    Set<IrOrigin>? requested,
  }) {
    implementations.rebind(implementations.values.runtime?.rebind(program));
    final functions = <IrFunction>[];
    var changed = false;
    for (final function in program.functions) {
      if (facts != null && !facts.definitions.contains(function.target)) {
        functions.add(function);
        continue;
      }
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
      final replaced = <Value, Value>{};
      final discarded = <Instruction>{};
      final operations = <Instruction, Instruction>{};
      final nonThrowing = <Instruction>{};
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          // Keep an unrequested source operation intact. If implementation
          // closure later reaches it, fresh facts will request its own body.
          if (facts != null && !facts.reachesOperation(operation)) continue;
          final origin = function.originOf(operation).source;
          if (requested != null && !requested.contains(origin)) continue;
          void remember() {
            // Another expansion may introduce a new copy of this same
            // semantic check after an earlier copy was already lowered.
            final key = (
              TypeLowering,
              function.originOf(operation),
              operation.runtimeType,
            );
            realizations.putIfAbsent(
              key,
              () => ProgramRealization(
                key,
                (canonical) => _lower(canonical, requested: {origin}),
              ),
            );
          }

          final _Implementation? implementation;
          switch (operation) {
            case CheckedTypeArgument(implementation: null):
              remember();
              operations[operation] = CheckedTypeArgument(
                operation.parameter,
                operation.argument,
                operation.environment,
                implementation: _boundCheck(operation).target,
              );
              continue;
            case Equals(
              left: final TypeConstant left,
              right: final TypeConstant right,
              :final negated,
            ):
              remember();
              replaced[operation] = Constant.boolean(
                (left.structuralKey == right.structuralKey) != negated,
              );
              discarded.add(operation);
              continue;
            case Equals(:final left) when left.isTypeDescriptor:
              implementation = _equals(operation);
            case TypeTest():
              implementation = _test(operation);
            case TypeCast() || NullCheck():
              final operand = operation.inputs.single;
              if (typeTestKind(
                    operand.type,
                    operation is NullCheck ? .object : operation.type,
                  ) ==
                  .constantTrue) {
                remember();
                operations[operation] = UncheckedCast(operand, operation.type);
                nonThrowing.add(operation);
                continue;
              }
              final check = casts.targetFor(operation);
              final body = casts.functions.singleWhere(
                (body) => body.target == check.target,
              );
              implementation = (
                body: body,
                arguments: operation.inputs.toList(),
                environment: {
                  for (final (i, parameter)
                      in body.target.typeParameters.indexed)
                    parameter: check.parameters[i],
                },
              );
            case ReifyType(:final template):
              final type = template.reify();
              if (type.freeTypeParameters.isEmpty) {
                remember();
                replaced[operation] = TypeConstant(type);
                discarded.add(operation);
                continue;
              }
              implementation = _reify(function, type);
            default:
              continue;
          }
          if (implementation == null) continue;
          remember();
          lowered[operation] = (
            body: implementation.body,
            arguments: implementation.arguments,
            environment: implementation.environment,
            handler: switch (block.end) {
              Invoke(operation: final invoked, :final onThrow)
                  when identical(invoked, operation) =>
                onThrow,
              _ => null,
            },
          );
        }
      }
      final rewritten =
          lowered.isEmpty && replaced.isEmpty && operations.isEmpty
          ? function
          : FunctionRewrite(
              function,
              executionShapes: program.executionShapes,
              lowered: lowered,
              replacements: replaced,
              operations: operations,
              nonThrowing: nonThrowing,
              discardable: discarded,
            ).run();
      changed |= !identical(rewritten, function);
      functions.add(rewritten);
    }
    return _install(program, changed ? functions : program.functions);
  }

  IrFunction _boundCheck(CheckedTypeArgument check) {
    final parameters = check.environment.keys.toList();
    final key = (
      check.parameter,
      parameters.fold<Object>((), (key, value) => (key, value)),
    );
    return _boundChecks.putIfAbsent(key, () {
      final target = FunctionTarget(
        null,
        'typeArgument${_boundChecks.length}',
        TypeMetadata.type,
        [for (final _ in check.inputs) TypeMetadata.type],
      );
      final entry = Block(target.parameterTypes),
          success = Block(),
          failed = Block();
      final values = implementations.values;
      final bound = values.build(
        entry,
        check.parameter.bound,
        {
          for (final (index, parameter) in parameters.indexed)
            parameter: entry.parameters[index + 1],
        },
        shift: (value, amount) => entry.emit(
          DirectCall(values.entry(.typeShift), [
            value,
            Constant.integer(amount),
            const Constant.integer(0),
          ]),
        ),
      );
      final accepts = entry.emit(
        DirectCall(implementations.relations.test, [
          entry.parameters.first,
          bound,
        ]),
      );
      entry.finish(Branch(accepts, Jump(success), Jump(failed)));
      success.finish(Return(entry.parameters.first));
      failed.finish(
        Unreachable(
          failed.emit(
            DirectCall(
              casts.failure ??
                  (throw StateError(
                    'Type argument validation requires the real failure entry.',
                  )),
              [],
            ),
          ),
        ),
      );
      return IrFunction(target, [entry, success, failed]);
    });
  }

  _Implementation _equals(Equals operation) {
    final scope = _Scope(operation.inputs.map((value) => value.type));
    final target = FunctionTarget(null, 'typeEquals', .boolean, [
      scope.type(operation.left.type),
      scope.type(operation.right.type),
    ], typeParameters: scope.parameters);
    final entry = Block(target.parameterTypes);
    final result = entry.emit(
      DirectCall(implementations.values.equality, [
        entry.emit(UncheckedCast(entry.parameters.first, TypeMetadata.type)),
        entry.emit(UncheckedCast(entry.parameters.last, .object.nullable)),
      ]),
    );
    entry.finish(
      Return(
        operation.negated
            ? entry.emit(Equals(result, const Constant.boolean(false)))
            : result,
      ),
    );
    return (
      body: IrFunction(target, [entry]),
      arguments: operation.inputs.toList(),
      environment: scope.environment,
    );
  }

  _Implementation _test(TypeTest operation) {
    final scope = _Scope([operation.operand.type, operation.testedType]);
    final target = FunctionTarget(null, 'typeTest', .boolean, [
      scope.type(operation.operand.type),
    ], typeParameters: scope.parameters);
    final entry = Block(target.parameterTypes), done = Block([.boolean]);
    final blocks = [entry, done];
    final input = entry.parameters.single;
    void check(Block block, ValueType tested, Jump yes, Jump no) {
      tested = tested.runtimeCheckType;
      final source = input.type.runtimeValueBound;
      final constraints = switch (tested.nullableBase ?? tested) {
        NonNullableTypeParameterType(:final parameter) => [
          parameter,
          ValueType.object,
        ],
        PromotedType(:final lexicalType, :final bound, :final isNonNullable) =>
          [lexicalType, bound, if (isNonNullable) ValueType.object],
        _ => null,
      };
      if ((tested.nullableBase ?? tested)
          case FutureOrType(:final argument, :final futureType)
          when tested != tested.reify()) {
        final alternatives = [
          if (tested.nullableBase != null) ValueType.nullType,
          argument,
          futureType,
        ];
        for (final (i, alternative) in alternatives.indexed) {
          final next = i + 1 == alternatives.length ? null : Block();
          if (next != null) blocks.add(next);
          check(block, alternative, yes, next == null ? no : Jump(next));
          if (next != null) block = next;
        }
        return;
      }
      if (constraints != null) {
        if (tested.nullableBase != null) {
          final next = Block();
          blocks.add(next);
          check(block, .nullType, yes, Jump(next));
          block = next;
        }
        for (final (i, constraint) in constraints.indexed) {
          final next = i + 1 == constraints.length ? null : Block();
          if (next != null) blocks.add(next);
          check(block, constraint, next == null ? yes : Jump(next), no);
          if (next != null) block = next;
        }
        return;
      }
      final kind = typeTestKind(source, tested);
      switch (kind) {
        case .constantTrue:
          block.finish(yes);
        case .constantFalse:
          block.finish(no);
        case .isNull || .isNotNull:
          final isNull = block.emit(Equals(input, const Constant.nullValue()));
          block.finish(
            Branch(
              isNull,
              kind == .isNull ? yes : no,
              kind == .isNull ? no : yes,
            ),
          );
        case .subtype:
          final actual = block.emit(
            UncheckedCast(
              block.emit(ObjectRuntimeType(input, direct: true)),
              TypeMetadata.type,
            ),
          );
          final expected = block.emit(
            UncheckedCast(block.emit(ReifyType(tested)), TypeMetadata.type),
          );
          final result = block.emit(
            DirectCall(implementations.relations.test, [actual, expected]),
          );
          block.finish(Branch(result, yes, no));
      }
    }

    check(
      entry,
      scope.type(operation.testedType),
      Jump(done, [Constant.boolean(!operation.negated)]),
      Jump(done, [Constant.boolean(operation.negated)]),
    );
    done.finish(Return(done.parameters.single));
    return (
      body: IrFunction(target, blocks),
      arguments: [operation.operand],
      environment: scope.environment,
    );
  }

  _Implementation? _reify(IrFunction function, ValueType type) {
    final owner = function.target.owner;
    final factory = function.target.kind == .factory && owner != null;
    // The factory's existing lexical owner argument is a physical input.
    if (factory && type == owner) return null;
    if (type is TypeParameterType &&
        (owner == null ||
            !owner.typeParameters.contains(type) ||
            !factory && !function.target.kind.hasReceiver)) {
      return null;
    }
    final receiver = type is TypeParameterType && !factory
        ? function.entry.parameters.first
        : null;
    final scope = _Scope([
      type,
      if (receiver != null) receiver.type,
      if (factory) owner,
    ]);
    final target = FunctionTarget(null, 'typeValue', .typeType, [
      if (receiver != null) scope.type(receiver.type),
    ], typeParameters: scope.parameters);
    final entry = Block(target.parameterTypes);
    final Value result;
    if (type is TypeParameterType) {
      final actual = entry.emit(
        UncheckedCast(
          factory
              ? entry.emit(ReifyType(scope.type(owner)))
              : entry.emit(
                  ObjectRuntimeType(entry.parameters.single, direct: true),
                ),
          TypeMetadata.type,
        ),
      );
      result = entry.emit(
        NullCheck(
          entry.emit(
            DirectCall(
              implementations.relations.argumentOf(
                owner!,
                owner.typeParameters.indexOf(type),
              ),
              [actual],
            ),
          ),
        ),
      );
    } else {
      final helper = implementations.values.instantiate(type);
      result = entry.emit(
        DirectCall(helper.target, [
          for (final parameter in helper.parameters)
            entry.emit(
              UncheckedCast(
                entry.emit(ReifyType(scope.type(parameter))),
                TypeMetadata.type,
              ),
            ),
        ]),
      );
    }
    entry.finish(Return(result));
    return (
      body: IrFunction(target, [entry]),
      arguments: [?receiver],
      environment: scope.environment,
    );
  }
}

typedef _Implementation = ({
  IrFunction body,
  List<Value> arguments,
  Map<TypeParameterType, ValueType> environment,
});

final class _Scope(Iterable<ValueType> types) {
  final _parameters = <TypeParameterType>[];
  final _mapping = <TypeParameterType, TypeParameterType>{};
  this {
    void include(TypeParameterType parameter) {
      if (_parameters.contains(parameter)) return;
      _parameters.add(parameter);
      parameter.bound.freeTypeParameters.forEach(include);
    }

    for (final type in types) {
      type.freeTypeParameters.forEach(include);
    }
    for (final parameter in _parameters) {
      _mapping[parameter] = TypeParameterType(parameter.name);
    }
    for (final parameter in _parameters) {
      _mapping[parameter]!.initializeBound(
        parameter.bound.substitute(_mapping),
      );
    }
  }
  Iterable<TypeParameterType> get parameters => _mapping.values;
  Map<TypeParameterType, ValueType> get environment => {
    for (final entry in _mapping.entries) entry.value: entry.key,
  };
  ValueType type(ValueType type) => type.substitute(_mapping);
}
