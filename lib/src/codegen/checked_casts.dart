import 'package:dartc/ir.dart';

import 'program_layout.dart';

/// Generates checked conversions using ordinary type tests and exception edges.
final class CheckedCasts({final FunctionTarget? failure}) {
  final _functions = <FunctionTarget, IrFunction>{};
  final _checks =
      <
        (ValueType, ValueType, bool),
        ({IrFunction body, List<TypeParameterType> parameters})
      >{};
  IrFunction? _bounds;

  FunctionTarget bounds(ProgramLayout layouts) {
    if (_bounds case final body?) return body.target;
    final target = FunctionTarget(null, 'bound', .voidType, [
      TypeMetadata.type,
      TypeMetadata.type,
    ]);
    final entry = Block(target.parameterTypes),
        done = Block(),
        failed = Block();
    entry.finish(
      Branch(
        entry.emit(DirectCall(layouts.relations.test, entry.parameters)),
        Jump(done),
        Jump(failed),
      ),
    );
    done.finish(const Return());
    _fail(failed);
    _bounds = _functions[target] = IrFunction(target, [entry, done, failed]);
    return target;
  }

  Iterable<IrFunction> get functions => _functions.values;

  void _fail(Block block) => block.finish(
    Unreachable(
      block.emit(
        DirectCall(
          failure ??
              (throw StateError(
                'Checked conversions require a type failure entry.',
              )),
          const [],
        ),
      ),
    ),
  );

  ({FunctionTarget target, List<TypeParameterType> parameters}) targetFor(
    Instruction instruction,
  ) {
    final (operand, nullOnly) = switch (instruction) {
      TypeCast(:final operand) => (operand, false),
      NullCheck(:final operand) => (operand, true),
      _ => throw ArgumentError('Expected a checked conversion.'),
    };
    final check = _checks.putIfAbsent(
      (operand.type, instruction.type, nullOnly),
      () {
        final parameters = <TypeParameterType>[];
        void include(TypeParameterType parameter) {
          if (parameters.contains(parameter)) return;
          parameters.add(parameter);
          parameter.bound.freeTypeParameters.forEach(include);
        }

        operand.type.freeTypeParameters.forEach(include);
        instruction.type.freeTypeParameters.forEach(include);
        final environment = {
          for (final parameter in parameters)
            parameter: TypeParameterType(parameter.name),
        };
        for (final parameter in parameters) {
          environment[parameter]!.initializeBound(
            parameter.bound.substitute(environment),
          );
        }
        final source = operand.type.substitute(environment),
            result = instruction.type.substitute(environment);
        final target = FunctionTarget(null, 'check${_checks.length}', result, [
          source,
        ], typeParameters: environment.values);
        final entry = Block(target.parameterTypes), failed = Block();
        final blocks = [entry, failed];
        if (result == .never) {
          entry.finish(Jump(failed));
        } else {
          final operand = entry.parameters.single;
          final test = entry.emit(
            TypeTest(operand, nullOnly ? .object : result),
          );
          // FutureOr<int?> keeps its static type after a null assertion.
          final accepted = nullOnly && result == source
              ? operand
              : test.refinement(true) ?? operand;
          final done = Block([result]);
          entry.finish(Branch(test, Jump(done, [accepted]), Jump(failed)));
          done.finish(Return(done.parameters.single));
          blocks.add(done);
        }
        _fail(failed);
        final body = _functions[target] = IrFunction(target, blocks);
        return (body: body, parameters: parameters);
      },
    );
    return (target: check.body.target, parameters: check.parameters);
  }
}
