import 'dart:async';
import 'dart:collection';

import 'package:dartc/ir.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/suspension_normalization.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';
import 'fixtures/suspensions.dart' as source;

void main() {
  late IrProgram program;
  late IrInterpreter runner;
  IrFunction body(String name) => program.functions.singleWhere(
    (f) =>
        f.target.name == name &&
        f.target.kind == .function &&
        f.target.library.toString().endsWith(
          '/codegen/fixtures/suspensions.dart',
        ),
  );

  setUpAll(() async {
    final lowered = await prepareRuntime(
      'test/codegen/fixtures/suspensions.dart',
    );
    final normalized = SuspensionNormalization(
      lowered.program,
      heapRuntime,
    ).run();
    final async = heapRuntime.async!, sync = heapRuntime.sync!;
    final external = {
      async.create,
      async.start,
      async.awaitValue,
      async.complete,
      sync.create,
      sync.yieldValue,
    };
    program = IrProgram(
      normalized.classes,
      normalized.functions.where((body) => !external.contains(body.target)),
      globals: normalized.globals,
      externals: [...normalized.externals, ...external.map(IrExternal.new)],
    );
    runner = IrInterpreter(
      program,
      {},
      externalCalls: {
        async.create: (args) => _Task(args.single, runner),
        async.start: (args) {
          final task = args.single as _Task;
          task.resume(task.initial, null, null, null);
          return task.done.future;
        },
        async.awaitValue: (args) {
          final task = args[0] as _Task;
          Future<Object?>.value(args[1]).then<void>(
            (value) => task.resume(args[3], value, null, null),
            onError: (Object error, StackTrace trace) =>
                task.resume(args[3], null, error, trace),
          );
          return null;
        },
        async.complete: (args) {
          (args[0] as _Task).done.complete(args[1]);
          return null;
        },
        sync.create: (args) => _Iterations(args.single, runner),
        sync.yieldValue: (args) {
          final iterator = args[0] as _Iteration;
          iterator.current = args[1];
          iterator.step = args[2];
          return null;
        },
      },
    );
  });

  test(
    'all suspension bodies expose ordinary calls before program analysis',
    () {
      expect(
        program.functions.every((body) => body.bodyKind == .synchronous),
        isTrue,
      );
      expect(
        program.functions
            .expand((body) => body.blocks)
            .where(
              (block) =>
                  block.end is Await ||
                  block.end is Yield ||
                  block.end is YieldStream,
            ),
        isEmpty,
      );
    },
  );

  test(
    'ordinary closure storage carries suspended cells and lexical types',
    () {
      bool belongs(FunctionTarget target) =>
          target.library.toString().endsWith(
            '/codegen/fixtures/suspensions.dart',
          ) ||
          target.enclosing != null && belongs(target.enclosing!);
      final functions = program.functions
          .where((body) => belongs(body.target))
          .toList();
      final closures = ClosureStorage(functions);
      final layouts = ProgramLayout(
        [...program.classes, ...closures.classes],
        nativeLayout: NativeLayout(Target.host()),
        functions: functions,
        closureStorage: closures,
        typeRuntime: heapRuntime.types,
      );
      final members = MemberCalls(
        program,
        functions.map((f) => f.target).toSet(),
      );
      for (final function in functions) {
        final selected = FunctionRepresentation(
          function,
          layouts,
          CheckedCasts(),
          members,
          HeapPlan(runtime: heapRuntime),
        );
        FunctionLiveness(
          selected,
          selected.inputsOf,
          selected.invocations.keys.toSet(),
        );
      }
    },
  );

  test(
    'loop iterations carry the newly computed values through each await',
    () async {
      for (final (count, seed) in [(0, 7), (1, -2), (6, 11)]) {
        expect(
          await source.accumulated(count, seed),
          seed + count * (count - 1) ~/ 2,
        );
        expect(
          await (runner.run(body('accumulated'), [count, seed])
              as Future<Object?>),
          await source.accumulated(count, seed),
        );
      }
    },
  );

  test(
    'a resumed generic scope constructs the original nested closure',
    () async {
      final generic = body('nested');
      expect(
        await (runner.run(
          generic,
          [42],
          {generic.target.typeParameters.single: .integer},
        ) as Future<Object?>),
        await source.nested(42),
      );
      expect(
        await (runner.run(
          generic,
          ['kept'],
          {generic.target.typeParameters.single: .string},
        ) as Future<Object?>),
        await source.nested('kept'),
      );
    },
  );

  test(
    'type refinements and pending exception identity cross suspension',
    () async {
      for (final value in <Object>[4, 'other']) {
        expect(
          await (runner.run(body('refined'), [value]) as Future<Object?>),
          await source.refined(value),
        );
      }
      final token = Object();
      expect(
        await (runner.run(body('handled'), [token]) as Future<Object?>),
        same(token),
      );
      expect(await source.handled(token), same(token));
    },
  );

  test(
    'await failure enters the original handler with the same exception',
    () async {
      final token = Object();
      final future = Future<int>.error(token, StackTrace.current);
      expect(
        await (runner.run(body('caught'), [future]) as Future<Object?>),
        same(token),
      );
    },
  );

  test('each iterator owns its activation and retained mutable local', () {
    final values = runner.run(body('iterations'), [7]) as Iterable<Object?>;
    final a = values.iterator, b = values.iterator;
    expect(a.moveNext(), isTrue);
    expect(a.current, 8);
    expect(a.moveNext(), isTrue);
    expect(a.current, 9);
    expect(b.moveNext(), isTrue);
    expect(b.current, 8);
    expect(values.toList(), source.iterations(7).toList());
    expect(a.moveNext(), isTrue);
    expect(a.current, 10);
    expect(a.moveNext(), isFalse);
  });
}

final class _Task(final Object? initial, final IrInterpreter runner) {
  final done = Completer<Object?>();
  void resume(
    Object? callback,
    Object? value,
    Object? error,
    StackTrace? trace,
  ) {
    try {
      runner.call(callback, [value, error, trace]);
    } catch (error, trace) {
      done.completeError(error, trace);
    }
  }
}

final class _Iterations(final Object? factory, final IrInterpreter runner)
    extends IterableBase<Object?> {
  @override
  Iterator<Object?> get iterator =>
      _Iteration(runner.call(factory, []), runner);
}

final class _Iteration(Object? initial, final IrInterpreter runner)
    implements Iterator<Object?> {
  Object? step = initial;
  @override
  Object? current;
  @override
  bool moveNext() {
    if (step == null) return false;
    final moved = runner.call(step, [this]) as bool;
    if (!moved) step = null;
    return moved;
  }
}
