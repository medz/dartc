import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  late IrProgram program;
  late FunctionTarget asyncRecord;
  IrFunction function(String name) => program.functions.singleWhere(
    (body) =>
        body.target.name == name &&
        body.target.library.toString().endsWith(
          '/codegen/fixtures/error_storage.dart',
        ),
  );
  setUpAll(() async {
    final result = await prepareRuntime(
      'test/codegen/fixtures/error_storage.dart',
    );
    asyncRecord = result.runtime.aliases.entries
        .singleWhere((entry) => entry.value == heapRuntime.recordError)
        .key;
    program = heapRuntime.program;
  });

  for (final async in [false, true]) {
    for (final name in [
      'makeSub',
      'makeOwn',
      'makeArgument',
      'makeGetter',
      'makePlain',
    ]) {
      test(
        '$name preserves first trace and public getter behavior (async=$async)',
        () {
          final interpreter = IrInterpreter(program, {});
          final record = program.implementationOf(
            async ? asyncRecord : heapRuntime.recordError,
          ) as IrFunction;
          final first = StackTrace.fromString('first'),
              second = StackTrace.fromString('second');
          final value = interpreter.run(function(name), [])!;
          if (name != 'makePlain' && name != 'makeGetter') {
            expect(interpreter.run(function('readTrace'), [value]), isNull);
          }
          interpreter.run(record, [value, first]);
          interpreter.run(record, [value, second]);
          if (name == 'makeGetter') {
            expect(
              interpreter.run(function('readStored'), [value]),
              same(first),
            );
            expect(
              interpreter.run(function('readTrace'), [value]),
              isNot(same(first)),
            );
          } else if (name != 'makePlain') {
            expect(
              interpreter.run(function('readTrace'), [value]),
              name == 'makeSub' ? same(first) : isNull,
            );
          }
        },
      );
    }
  }

  for (final tearOff in [false, true]) {
    test(
      'ordinary state propagation retains the first trace without error storage (tearOff=$tearOff)',
      () {
        final target = FunctionTarget(
          Uri.parse('memory:record-trace'),
          'recordTwice',
          .stackTrace.nullable,
          [.stackTrace, .stackTrace],
        );
        final entry = Block(target.parameterTypes);
        final error = entry.emit(DirectCall(function('makeSub').target, []));
        for (final trace in entry.parameters) {
          entry.emit(
            tearOff
                ? FunctionCall(FunctionConstant(asyncRecord), [error, trace])
                : DirectCall(asyncRecord, [error, trace]),
          );
        }
        entry.finish(
          Return(entry.emit(DirectCall(function('readTrace').target, [error]))),
        );
        final input = IrProgram(
          program.classes,
          [
            ...program.functions,
            IrFunction(target, [entry]),
          ],
          globals: program.globals,
          externals: program.externals,
        );
        final facts =
            ProgramOptimizer(const [
              ProgramSimplification(),
              ProgramCallSpecialization(),
              ProgramStoragePromotion(),
              ProgramStorageElimination(),
              DirectCallInlining(),
            ]).run(input, [
              (
                target: target,
                arguments: target.parameterTypes
                    .map(FlowValue.unknown)
                    .toList(),
              ),
            ]);
        expect(facts.definitions, {target});
        final rewritten = facts.program.implementationOf(target) as IrFunction;
        expect(
          rewritten.blocks
              .expand((b) => b.instructions)
              .where((op) => op.effects.isNotEmpty),
          isEmpty,
        );
        for (final graph in [input, facts.program]) {
          for (final label in ['first', '', 'with\nframes']) {
            final first = StackTrace.fromString(label),
                second = StackTrace.fromString('second');
            expect(
              IrInterpreter(graph, {}).run(
                graph.implementationOf(target) as IrFunction,
                [first, second],
              ),
              same(first),
            );
          }
        }
      },
    );
  }
}
