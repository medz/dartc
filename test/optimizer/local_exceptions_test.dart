import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/local_exceptions.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    await prepareRuntime('test/optimizer/fixtures/local_exceptions.dart');
    program = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  for (final (name, evaluate) in [
    ('caughtValue', source.caughtValue),
    ('caughtObject', source.caughtObject),
    ('ignoredObject', source.ignoredObject),
    ('caughtRethrow', source.caughtRethrow),
    ('caughtFinally', source.caughtFinally),
  ]) {
    test(
      '$name retains computation without exception storage or unwinding',
      () {
        final function = program.functions.singleWhere(
          (f) => f.target.name == name,
        );
        final facts =
            ProgramOptimizer(const [
              ProgramSimplification(),
              ProgramCallSpecialization(),
              ProgramStoragePromotion(),
              ProgramStorageElimination(),
              DirectCallInlining(),
              ProgramBranchSpecialization(),
            ]).run(program, [
              (
                target: function.target,
                arguments: [FlowValue.unknown(.integer)],
              ),
            ], allocationFailure: heapRuntime.allocationFailure);
        final body =
            facts.program.implementationOf(function.target) as IrFunction;
        for (final input in [
          FlowIntegerRange.minimum,
          -4,
          0,
          41,
          FlowIntegerRange.maximum,
        ]) {
          expect(
            IrInterpreter(program, {}).run(function, [input]),
            evaluate(input),
          );
          expect(
            IrInterpreter(facts.program, {}).run(body, [input]),
            evaluate(input),
          );
        }
        expect(facts.definitions, {function.target});
        expect(body.blocks.map((b) => b.end).whereType<Throw>(), isEmpty);
        expect([
          for (final block in body.blocks)
            for (final operation in [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ])
              ...operation.effects,
        ], isEmpty);
      },
    );
  }

  for (final type in [ValueType.error, ValueType.object]) {
    test('a caught ${type.dartName} preserves the first Error trace', () {
      final target = FunctionTarget(_uri, 'ignore', .integer, [type]);
      final entry = Block(target.parameterTypes), handler = Block();
      entry.finish(Throw(entry.parameters.single, onThrow: Jump(handler)));
      handler.finish(const Return(Constant.integer(7)));
      final original = IrFunction(target, [entry, handler]);
      final graph = IrProgram([], [original]);
      final facts = ProgramFlow(graph, [
        (target: target, arguments: [FlowValue.unknown(type)]),
      ]).facts;
      final optimized = const ProgramSimplification().run(facts);
      for (final program in [graph, optimized]) {
        final error = StateError('first throw');
        expect(error.stackTrace, isNull);
        expect(
          IrInterpreter(
            program,
            {},
          ).run(program.implementationOf(target) as IrFunction, [error]),
          7,
        );
        final first = error.stackTrace;
        expect(first, isNotNull);
        IrInterpreter(
          program,
          {},
        ).run(program.implementationOf(target) as IrFunction, [error]);
        expect(error.stackTrace, same(first));
      }
      expect(
        (optimized.implementationOf(target) as IrFunction).blocks
            .map((b) => b.end)
            .whereType<Throw>(),
        hasLength(1),
      );
    });
  }

  for (final explicit in [false, true]) {
    test('a caught trace is preserved with explicit=$explicit', () {
      final target = FunctionTarget(_uri, 'trace', .stackTrace, [
        .integer,
        if (explicit) .stackTrace,
      ]);
      final entry = Block(target.parameterTypes),
          handler = Block([.stackTrace]);
      entry.finish(
        Throw(
          entry.parameters.first,
          stackTrace: explicit ? entry.parameters.last : null,
          onThrow: Jump(handler, [UnwindValue.stackTrace]),
        ),
      );
      handler.finish(Return(handler.parameters.single));
      final original = IrFunction(target, [entry, handler]);
      final graph = IrProgram([], [original]);
      final facts = ProgramFlow(graph, [
        (
          target: target,
          arguments: target.parameterTypes.map(FlowValue.unknown).toList(),
        ),
      ]).facts;
      final optimized = const ProgramSimplification().run(facts);
      final supplied = StackTrace.fromString('original trace');
      for (final program in [graph, optimized]) {
        final trace = IrInterpreter(program, {}).run(
          program.implementationOf(target) as IrFunction,
          [42, if (explicit) supplied],
        );
        expect(trace, isA<StackTrace>());
        expect(trace.toString(), explicit ? supplied.toString() : isNotEmpty);
      }
      expect(
        (optimized.implementationOf(target) as IrFunction).blocks
            .map((b) => b.end)
            .whereType<Throw>(),
        explicit ? isEmpty : hasLength(1),
      );
    });
  }
}

final _uri = Uri.parse('memory:local-exceptions');
