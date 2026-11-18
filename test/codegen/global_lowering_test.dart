import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../frontend/lowering/fixture_comparison.dart';
import '../frontend/lowering/fixtures/effects.dart' as effects;

void main() {
  final uri = Uri.parse('memory:global-lowering');
  final error = ClassType(uri, 'BindingError', superclass: ValueType.error);
  final errorConstructor = FunctionTarget(
    uri,
    'new',
    .voidType,
    [.string],
    owner: error,
    kind: .initializer,
  );
  final errorBody = IrFunction(errorConstructor, [
    Block(errorConstructor.parameterTypes)..finish(const Return()),
  ]);
  final errorClass = IrClass(error, [], constructors: [errorConstructor]);

  test('closure growth replaces one holder everywhere and lowers later known-slot consumers', () {
    final first = GlobalVariable(uri, 'first', .integer.nullable);
    final second = GlobalVariable(uri, 'second', .integer.nullable);
    IrFunction reader(String name, GlobalVariable global) {
      final target = FunctionTarget(uri, name, global.type, []);
      final entry = Block();
      entry.finish(Return(entry.emit(LoadGlobal(global))));
      return IrFunction(target, [entry]);
    }

    final a = reader('readFirst', first),
        b = reader('readSecond', second),
        unreachable = reader('unreachableFirst', first);
    final initial = IrProgram(
      [],
      [a, b, unreachable],
      globals: [first, second],
    );
    final transform = GlobalLowering().bind();
    ProgramFlowFacts facts(IrProgram program, Iterable<FunctionTarget> roots) =>
        ProgramFlow(program, [], openEntries: roots).facts;
    final once = transform(facts(initial, [a.target]));
    final oldHolder = once.functions
        .expand((f) => f.moduleObjects)
        .toSet()
        .single;
    final getter =
        (once.implementationOf(a.target) as IrFunction).callees.single;
    expect(
      (once.implementationOf(unreachable.target) as IrFunction).globals,
      isEmpty,
    );
    expect(once.globals, [second]);
    final twice = transform(facts(once, [a.target, b.target]));
    final holder = twice.functions
        .expand((f) => f.moduleObjects)
        .toSet()
        .single;
    expect(holder, isNot(same(oldHolder)));
    expect((twice.implementationOf(a.target) as IrFunction).callees, {getter});
    expect(twice.globals, isEmpty);
    expect(twice.classes.single.fields, hasLength(2));
    expect(transform(facts(twice, [a.target, b.target])), same(twice));

    final later = reader('laterFirst', first);
    final withLater = IrProgram(
      twice.classes,
      [...twice.functions, later],
      globals: [first],
    );
    final closed = transform(facts(withLater, [later.target]));
    expect(
      (closed.implementationOf(later.target) as IrFunction).globals,
      isEmpty,
    );
    expect((closed.implementationOf(later.target) as IrFunction).callees, {
      getter,
    });
    expect(closed.functions.expand((f) => f.moduleObjects).toSet(), {holder});
    expect(closed.globals, isEmpty);
    expect(transform(facts(closed, [later.target])), same(closed));
  });

  test('module getters and setters share state across entries and runners stay isolated', () {
    final global = GlobalVariable(uri, 'shared', .integer.nullable);
    final write = FunctionTarget(uri, 'write', .voidType, [.integer]);
    final store = Block(write.parameterTypes);
    store.emit(StoreGlobal(global, store.parameters.single));
    store.finish(const Return());
    final read = FunctionTarget(uri, 'read', .integer.nullable, []);
    final load = Block();
    load.finish(Return(load.emit(LoadGlobal(global))));
    final source = IrProgram(
      [],
      [
        IrFunction(write, [store]),
        IrFunction(read, [load]),
      ],
      globals: [global],
    );
    final program = GlobalLowering().lower(source, [read, write]);
    final first = IrInterpreter(program, {}),
        second = IrInterpreter(program, {});
    final reader = program.implementationOf(read) as IrFunction,
        writer = program.implementationOf(write) as IrFunction;
    expect(first.run(reader, []), isNull);
    first.run(writer, [37]);
    expect(first.run(reader, []), 37);
    expect(second.run(reader, []), isNull);
    first.run(writer, [-8]);
    expect(first.run(reader, []), -8);
    expect(program.globals, isEmpty);
  });

  test('a throwing initializer retains its writes and the next read does not retry', () {
    final init = FunctionTarget(uri, 'initializeThrowing', .integer, []);
    final global = GlobalVariable(uri, 'throwing', .integer, initializer: init);
    final initializer = Block();
    initializer.emit(StoreGlobal(global, const Constant.integer(37)));
    initializer.finish(Throw.recorded(const Constant.integer(23), null));
    final root = FunctionTarget(uri, 'readThrowing', .integer, []);
    final entry = Block(), success = Block([.integer]), caught = Block();
    final read = LoadGlobal(global);
    entry.finish(
      Invoke(read, onReturn: Jump(success, [read]), onThrow: Jump(caught)),
    );
    success.finish(Return(success.parameters.single));
    caught.finish(Return(caught.emit(LoadGlobal(global))));
    final source = IrProgram(
      [],
      [
        IrFunction(init, [initializer]),
        IrFunction(root, [entry, success, caught]),
      ],
      globals: [global],
    );
    final program = GlobalLowering().lower(source, [init, root]);
    final runner = IrInterpreter(program, {});
    final body = program.implementationOf(root) as IrFunction;
    expect(runner.run(body, []), 37);
    expect(runner.run(body, []), 37);
  });

  test('default frontend void and Never globals keep observable values and non-completion', () async {
    final fixture = await FixtureComparison.load('global_storage');
    final source = IrProgram(
      [...fixture.program.classes, errorClass],
      [...fixture.program.functions, errorBody],
      globals: fixture.program.globals,
      externals: fixture.program.externals,
    );
    final names = {
      'throwingNeverRead',
      'unboundNeverRead',
      'observableVoidRead',
      'voidGlobalResult',
    };
    final roots = source.functions
        .where((f) => f.target.owner == null && names.contains(f.target.name))
        .toList();
    // The frontend fixture intentionally leaves tick as a host-interpreted
    // dependency. Follow all supplied source bodies, including implicit static
    // getters and lazy initializers, without inventing a compiler external.
    final definitions = <FunctionTarget>{};
    final pending = roots.map((f) => f.target).toList();
    while (pending.isNotEmpty) {
      final target = pending.removeLast();
      if (!definitions.add(target)) continue;
      if (source.implementationOf(target) case final IrFunction body) {
        pending.addAll(body.callees);
        pending.addAll(body.globals.expand((g) => [?g.initializer]));
      }
    }
    final program = GlobalLowering(lateError: errorBody)
        .lower(source, definitions);
    final runner = IrInterpreter(program, {
      (
        Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
        'tick',
      ): effects.tick,
    });
    Object? run(String name) => runner.run(
      program.functions.singleWhere(
        (f) => f.target.owner == null && f.target.name == name,
      ),
      [],
    );
    expect(run('observableVoidRead'), 42);
    expect(run('observableVoidRead'), 42);
    effects.calls.clear();
    expect(() => run('throwingNeverRead'), throwsA(185));
    expect(() => run('throwingNeverRead'), throwsA(185));
    expect(effects.calls, [185, 185]);
    expect(
      () => run('unboundNeverRead'),
      throwsA(
        predicate((e) => IrInterpreter.exceptionType(e as Object) == error),
      ),
    );
    final holder = program.functions
        .expand((f) => f.moduleObjects)
        .toSet()
        .single;
    final fields = program.classes
        .singleWhere((c) => c.type == holder.type)
        .fields;
    expect(fields.map((f) => f.type), contains(ValueType.voidType));
    expect(fields.map((f) => f.type), isNot(contains(ValueType.never)));
    expect(fields, hasLength(2));
    for (final root in roots) {
      expect(
        (program.implementationOf(root.target) as IrFunction).globals,
        isEmpty,
      );
    }
  });

  test('final Never initialization has no fictitious commit or late-error dependency', () {
    final init = FunctionTarget(uri, 'neverInitializer', .never, []);
    final global = GlobalVariable(
      uri,
      'neverFinal',
      .never,
      isFinal: true,
      initializer: init,
    );
    final source = Block()
      ..finish(Throw.recorded(const Constant.integer(8), null));
    final read = FunctionTarget(uri, 'neverRead', .never, []);
    final entry = Block();
    entry.finish(Unreachable(entry.emit(LoadGlobal(global))));
    final program = GlobalLowering().lower(
      IrProgram(
        [],
        [
          IrFunction(init, [source]),
          IrFunction(read, [entry]),
        ],
        globals: [global],
      ),
      [read, init],
    );
    expect(
      () => IrInterpreter(
        program,
        {},
      ).run(program.implementationOf(read) as IrFunction, []),
      throwsA(8),
    );
    expect(program.functions.expand((f) => f.moduleObjects), isEmpty);
    expect(program.functions.expand((f) => f.fields), isEmpty);
  });

  for (final finalBinding in [false, true]) {
    test(
      '${finalBinding ? 'final' : 'mutable'} recursive initialization commits in source order',
      () {
        final depth = GlobalVariable(uri, 'depth', .integer.nullable);
        final init = FunctionTarget(uri, 'recursiveInitializer', .integer, []);
        final global = GlobalVariable(
          uri,
          'recursive',
          .integer,
          isFinal: finalBinding,
          initializer: init,
        );
        final entry = Block(), nested = Block(), done = Block();
        final current = entry.emit(LoadGlobal(depth));
        entry.finish(
          Branch(
            entry.emit(Equals(current, const Constant.nullValue())),
            Jump(nested),
            Jump(done),
          ),
        );
        nested.emit(StoreGlobal(depth, const Constant.integer(1)));
        final inner = nested.emit(LoadGlobal(global));
        nested.finish(
          Return(
            nested.emit(IntBinary(.add, inner, const Constant.integer(1))),
          ),
        );
        done.finish(const Return(Constant.integer(6)));
        final root = FunctionTarget(uri, 'recursiveRead', .integer, []);
        final call = Block(), success = Block([.integer]), caught = Block();
        final read = LoadGlobal(global);
        call.finish(
          Invoke(read, onReturn: Jump(success, [read]), onThrow: Jump(caught)),
        );
        success.finish(Return(success.parameters.single));
        caught.finish(Return(caught.emit(LoadGlobal(global))));
        final source = IrProgram(
          [errorClass],
          [
            errorBody,
            IrFunction(init, [entry, nested, done]),
            IrFunction(root, [call, success, caught]),
          ],
          globals: [depth, global],
        );
        final program = GlobalLowering(lateError: errorBody)
            .lower(source, [init, root]);
        final runner = IrInterpreter(program, {});
        final body = program.implementationOf(root) as IrFunction;
        expect(runner.run(body, []), finalBinding ? 6 : 7);
        expect(runner.run(body, []), finalBinding ? 6 : 7);
      },
    );
  }
}
