import 'package:dartc/ir.dart';

import 'program_layout.dart';
import 'type_values.dart';

/// Generates checked conversions using ordinary type tests and exception edges.
final class CheckedCasts() {
  final _error = ClassType(null, '_TypeError', superclass: ValueType.typeError);
  late final _initializer = FunctionTarget(
    null,
    '_TypeError',
    .voidType,
    [],
    owner: _error,
    kind: .initializer,
  );
  final _checks =
      <
        (ValueType, ValueType, bool),
        ({IrFunction body, List<TypeParameterType> parameters})
      >{};
  IrFunction? _bounds;

  FunctionTarget bounds(ProgramLayout layouts) {
    if (_bounds case final body?) return body.target;
    final target = FunctionTarget(null, 'bound', .voidType, [
      TypeValues.type,
      TypeValues.type,
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
    failed.finish(Throw(failed.emit(Construct(_initializer, []))));
    _bounds = IrFunction(target, [entry, done, failed]);
    return target;
  }

  late final classes = [
    IrClass(ValueType.error, []),
    IrClass(ValueType.typeError, []),
    IrClass(_error, [], constructors: [_initializer]),
  ];

  Iterable<IrFunction> get functions sync* {
    if (_checks.isEmpty && _bounds == null) return;
    yield IrFunction(_initializer, [
      Block(_initializer.parameterTypes)..finish(const Return()),
    ]);
    yield* _checks.values.map((check) => check.body);
    if (_bounds case final body?) yield body;
  }

  ({FunctionTarget target, List<TypeParameterType> parameters}) targetFor(
    Instruction instruction,
    ProgramLayout layouts,
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
        final kind = layouts.typeTest(source, nullOnly ? .object : result);
        final target = FunctionTarget(null, 'check${_checks.length}', result, [
          source,
        ], typeParameters: environment.values);
        final entry = Block(target.parameterTypes), failed = Block();
        final blocks = [entry, failed];
        if (result == .never || kind == .constantFalse) {
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
          final done = Block(result == .voidType ? [] : [result]);
          entry.finish(
            Branch(
              test,
              Jump(done, result == .voidType ? [] : [accepted]),
              Jump(failed),
            ),
          );
          done.finish(
            Return(result == .voidType ? null : done.parameters.single),
          );
          blocks.add(done);
        }
        failed.finish(Throw(failed.emit(Construct(_initializer, []))));
        return (body: IrFunction(target, blocks), parameters: parameters);
      },
    );
    return (target: check.body.target, parameters: check.parameters);
  }
}
