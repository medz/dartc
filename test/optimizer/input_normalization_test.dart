import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:input-normalization');

void main() {
  test('shared writers preserve each returned closure when inputs grow', () {
    final slot = GlobalVariable(_uri, 'slot', .integer, isLate: true);
    final factory = FunctionTarget(
      _uri,
      'factory',
      FunctionType(.integer, []),
      [.integer],
    );
    final cell = CellType(.integer);
    final closure = FunctionTarget(
      _uri,
      'get',
      .integer,
      [],
      kind: .closure,
      enclosing: factory,
      sourceOffset: 1,
      captures: [cell],
    );
    final get = Block(closure.parameterTypes);
    get.finish(Return(get.emit(ReadCell(get.parameters[1]))));
    final writer = Block(factory.parameterTypes);
    writer.emit(StoreGlobal(slot, writer.parameters.single));
    final storage = writer.emit(NewCell(cell, writer.parameters.single));
    writer.finish(Return(writer.emit(MakeClosure(closure, [storage]))));
    final functions = [
      IrFunction(factory, [writer]),
      IrFunction(closure, [get]),
    ];
    final roots = <FunctionTarget>[],
        calls = <FunctionCall>[],
        values = <Value>[];
    final loads = <LoadGlobal>[];
    for (var i = 0; i < 4; i++) {
      final root = FunctionTarget(_uri, 'root$i', .integer, [.integer]);
      final entry = Block(root.parameterTypes);
      final value = entry.emit(DirectCall(factory, [entry.parameters.single]));
      final call = entry.emit(FunctionCall(value, []));
      loads.add(entry.emit(LoadGlobal(slot)));
      entry.finish(Return(call));
      functions.add(IrFunction(root, [entry]));
      roots.add(root);
      calls.add(call);
      values.add(value);
    }
    List<FlowEntry> inputs(Iterable<FunctionTarget> targets, int value) => [
      for (final target in targets)
        (
          target: target,
          arguments: [FlowValue.constant(Constant.integer(value))],
        ),
    ];
    final flow = ProgramFlow(
      IrProgram([], functions, globals: [slot]),
      inputs(roots, 1),
    );
    expect(flow.facts.activationsOf(factory), hasLength(1));
    for (final upper in [2, 3]) {
      for (final (targets, complete) in [
        (roots.take(2), false),
        (roots.skip(2), true),
      ]) {
        flow.extend(entries: inputs(targets, upper));
        final facts = flow.facts;
        expect(facts.activationsOf(factory), hasLength(complete ? 1 : 2));
        final seen = <FlowObject>{};
        for (var i = 0; i < roots.length; i++) {
          final expected = FlowIntegerRange(
            1,
            complete || i < 2 ? upper : upper - 1,
          );
          expect(facts.valueOf(loads[i]).integers, expected);
          expect(facts.returnedBy(roots[i]).integers, expected);
          expect(facts.targetsOf(calls[i]), {closure});
          expect(facts.hasUnknownCall(calls[i]), isFalse);
          expect(seen.add(facts.valueOf(values[i]).objects.single), isTrue);
        }
      }
    }
  });

  test(
    'equivalent input graphs share a summary and restore caller identities',
    () {
      final fixture = _Fixture();
      final get = FunctionTarget(_uri, 'child', fixture.child, [fixture.box]);
      final body = Block(get.parameterTypes);
      body.finish(
        Return(body.emit(LoadField(fixture.link, body.parameters.single))),
      );
      final target = FunctionTarget(_uri, 'root', .integer, []);
      final entry = Block();
      final comparisons = <Instruction>[];
      Value sum = const Constant.integer(0);
      for (var i = 0; i < 16; i++) {
        final owner = entry.emit(
          DirectCall(fixture.make, [Constant.integer(i)]),
        );
        final original = entry.emit(LoadField(fixture.link, owner));
        final returned = entry.emit(DirectCall(get, [owner]));
        comparisons.add(entry.emit(Identical(original, returned)));
        sum = entry.emit(
          IntBinary(.add, sum, entry.emit(LoadField(fixture.value, returned))),
        );
      }
      entry.finish(Return(sum));
      final root = IrFunction(target, [entry]);
      final program = fixture.program([
        root,
        IrFunction(get, [body]),
      ]);
      final facts = ProgramFlow(program, [
        (target: target, arguments: []),
      ]).facts;
      expect(IrInterpreter(program, {}).run(root, []), 120);
      expect(_scalar(facts.returnedBy(target)), 120);
      expect(facts.activationsOf(fixture.make), hasLength(16));
      expect(facts.activationsOf(get), hasLength(1));
      for (final comparison in comparisons) {
        expect(_scalar(facts.valueOf(comparison)), true);
      }
    },
  );

  test('shared scalar reads restore the caller stored SSA equality', () {
    final fixture = _Fixture();
    final get = FunctionTarget(_uri, 'value', .integer, [fixture.box]);
    final body = Block(get.parameterTypes);
    final child = body.emit(LoadField(fixture.link, body.parameters.single));
    body.finish(Return(body.emit(LoadField(fixture.value, child))));
    final target = FunctionTarget(_uri, 'root', .integer, [.integer, .integer]);
    final entry = Block(target.parameterTypes);
    final comparisons = <Instruction>[];
    Value sum = const Constant.integer(0);
    for (final parameter in entry.parameters) {
      final owner = entry.emit(DirectCall(fixture.make, [parameter]));
      final returned = entry.emit(DirectCall(get, [owner]));
      comparisons.add(entry.emit(Equals(parameter, returned)));
      sum = entry.emit(IntBinary(.add, sum, returned));
    }
    entry.finish(Return(sum));
    final root = IrFunction(target, [entry]);
    final program = fixture.program([
      root,
      IrFunction(get, [body]),
    ]);
    final facts = ProgramFlow(program, [
      (
        target: target,
        arguments: [FlowValue.unknown(.integer), FlowValue.unknown(.integer)],
      ),
    ]).facts;
    expect(IrInterpreter(program, {}).run(root, [11, 42]), 53);
    expect(facts.activationsOf(get), hasLength(1));
    for (final comparison in comparisons) {
      expect(_scalar(facts.valueOf(comparison)), true);
    }
  });

  test('input sharing preserves aliases and distinct sibling storage', () {
    final fixture = _Fixture();
    final change = FunctionTarget(_uri, 'changeAndRead', .integer, [
      fixture.child,
      fixture.child,
    ]);
    final body = Block(change.parameterTypes);
    body.emit(
      StoreField(fixture.value, body.parameters[0], const Constant.integer(9)),
    );
    body.finish(
      Return(body.emit(LoadField(fixture.value, body.parameters[1]))),
    );
    final functions = <IrFunction>[
      IrFunction(change, [body]),
    ];
    final entries = <FlowEntry>[];
    for (final alias in [false, true]) {
      for (var i = 0; i < 3; i++) {
        final target = FunctionTarget(_uri, 'root${alias}_$i', .integer, []);
        final entry = Block();
        final firstBox = entry.emit(
          DirectCall(fixture.make, [const Constant.integer(1)]),
        );
        final secondBox = entry.emit(
          DirectCall(fixture.make, [const Constant.integer(1)]),
        );
        final first = entry.emit(LoadField(fixture.link, firstBox));
        final second = entry.emit(LoadField(fixture.link, secondBox));
        entry.finish(
          Return(
            entry.emit(DirectCall(change, [first, alias ? first : second])),
          ),
        );
        functions.add(IrFunction(target, [entry]));
        entries.add((target: target, arguments: []));
      }
    }
    final program = fixture.program(functions);
    final facts = ProgramFlow(program, entries).facts;
    expect(facts.activationsOf(change), hasLength(2));
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
    ]).run(program, entries).program;
    for (final (i, invocation) in entries.indexed) {
      final expected = i < 3 ? 1 : 9;
      expect(_scalar(facts.returnedBy(invocation.target)), expected);
      for (final graph in [program, optimized]) {
        expect(
          IrInterpreter(
            graph,
            {},
          ).run(graph.implementationOf(invocation.target) as IrFunction, []),
          expected,
        );
      }
    }
  });

  test('returned allocation identity survives a shared summary splitting', () {
    final fixture = _Fixture();
    final target = FunctionTarget(_uri, 'root', .integer, [.boolean]);
    final root = Block(target.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block([.integer]);
    root.finish(Branch(root.parameters.single, Jump(yes), Jump(no)));
    yes.finish(Jump(join, [const Constant.integer(2)]));
    no.finish(Jump(join, [const Constant.integer(1)]));
    final first = join.emit(DirectCall(fixture.make, join.parameters));
    final second = join.emit(
      DirectCall(fixture.make, [const Constant.integer(1)]),
    );
    final firstChild = join.emit(LoadField(fixture.link, first));
    final secondChild = join.emit(LoadField(fixture.link, second));
    join.finish(
      Return(
        join.emit(
          IntBinary(
            .subtract,
            join.emit(LoadField(fixture.value, firstChild)),
            join.emit(LoadField(fixture.value, secondChild)),
          ),
        ),
      ),
    );
    final program = fixture.program([
      IrFunction(target, [root, yes, no, join]),
    ]);
    final flow = ProgramFlow(program, [
      (
        target: target,
        arguments: [FlowValue.constant(const Constant.boolean(false))],
      ),
    ]);
    final original = flow.facts.valueOf(first).objects.single;
    expect(flow.facts.activationsOf(fixture.make), hasLength(1));
    flow.extend(
      entries: [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.boolean(true))],
        ),
      ],
    );
    final facts = flow.facts;
    expect(facts.activationsOf(fixture.make), hasLength(2));
    expect(facts.valueOf(first).objects, {original});
    expect(facts.valueOf(firstChild).objects, hasLength(1));
    expect(facts.valueOf(second).objects, hasLength(1));
    expect(facts.valueOf(secondChild).objects, hasLength(1));
    expect(
      facts.mayAliasAcrossSummaries(
        original,
        facts.valueOf(second).objects.single,
      ),
      isFalse,
    );
    final optimized = const ProgramStorageElimination().run(facts);
    for (final graph in [program, optimized]) {
      final body = graph.implementationOf(target) as IrFunction;
      expect(IrInterpreter(graph, {}).run(body, [false]), 0);
      expect(IrInterpreter(graph, {}).run(body, [true]), 1);
    }
  });

  test('mutual recursion preserves the caller input identity and storage', () {
    final fixture = _Fixture();
    final first = FunctionTarget(_uri, 'first', fixture.box, [
      fixture.box,
      .integer,
    ]);
    final second = FunctionTarget(
      _uri,
      'second',
      fixture.box,
      first.parameterTypes,
    );
    final begin = Block(first.parameterTypes), done = Block(), repeat = Block();
    begin.finish(
      Branch(
        begin.emit(
          IntBinary(
            .lessOrEqual,
            begin.parameters[1],
            const Constant.integer(0),
          ),
        ),
        Jump(done),
        Jump(repeat),
      ),
    );
    done.finish(Return(begin.parameters[0]));
    repeat.finish(
      Return(
        repeat.emit(
          DirectCall(second, [
            begin.parameters[0],
            repeat.emit(
              IntBinary(
                .subtract,
                begin.parameters[1],
                const Constant.integer(1),
              ),
            ),
          ]),
        ),
      ),
    );
    final relay = Block(second.parameterTypes);
    relay.finish(Return(relay.emit(DirectCall(first, relay.parameters))));
    final target = FunctionTarget(_uri, 'root', .integer, [.integer]);
    final root = Block(target.parameterTypes);
    final original = root.emit(
      DirectCall(fixture.make, [const Constant.integer(42)]),
    );
    final result = root.emit(
      DirectCall(first, [original, root.parameters.single]),
    );
    root.finish(
      Return(
        root.emit(
          LoadField(fixture.value, root.emit(LoadField(fixture.link, result))),
        ),
      ),
    );
    final program = fixture.program([
      IrFunction(target, [root]),
      IrFunction(first, [begin, done, repeat]),
      IrFunction(second, [relay]),
    ]);
    final facts = ProgramFlow(program, [
      (target: target, arguments: [FlowValue.unknown(.integer)]),
    ]).facts;
    expect(_scalar(facts.returnedBy(target)), 42);
    expect(facts.valueOf(result).objects, facts.valueOf(original).objects);
    for (final count in [0, 1, 5]) {
      expect(
        IrInterpreter(
          program,
          {},
        ).run(program.implementationOf(target) as IrFunction, [count]),
        42,
      );
    }
  });

  test(
    'a private input becoming globally anchored changes identity domain once',
    () {
      final fixture = _Fixture();
      final saved = GlobalVariable(_uri, 'saved', fixture.box.nullable);
      final get = FunctionTarget(_uri, 'anchored', fixture.child, [
        fixture.box,
      ]);
      final body = Block(get.parameterTypes);
      body.emit(LoadGlobal(saved));
      body.finish(
        Return(body.emit(LoadField(fixture.link, body.parameters.single))),
      );
      final root = FunctionTarget(_uri, 'root', .boolean, [.boolean]);
      final entry = Block(root.parameterTypes),
          save = Block(),
          plain = Block(),
          done = Block();
      final owner = entry.emit(
        DirectCall(fixture.make, [const Constant.integer(7)]),
      );
      entry.finish(Branch(entry.parameters.single, Jump(save), Jump(plain)));
      save.emit(StoreGlobal(saved, owner));
      save.finish(Jump(done));
      plain.finish(Jump(done));
      final original = done.emit(LoadField(fixture.link, owner));
      final returned = done.emit(DirectCall(get, [owner]));
      done.finish(Return(done.emit(Identical(original, returned))));
      final program = IrProgram(
        [
          IrClass(fixture.child, [fixture.value]),
          IrClass(fixture.box, [fixture.link, fixture.flag]),
        ],
        [
          fixture.factory,
          IrFunction(get, [body]),
          IrFunction(root, [entry, save, plain, done]),
        ],
        globals: [saved],
      );
      final flow = ProgramFlow(program, [
        (
          target: root,
          arguments: [FlowValue.constant(const Constant.boolean(false))],
        ),
      ]);
      expect(_scalar(flow.facts.returnedBy(root)), true);
      flow.extend(
        entries: [
          (
            target: root,
            arguments: [FlowValue.constant(const Constant.boolean(true))],
          ),
        ],
      );
      expect(_scalar(flow.facts.returnedBy(root)), true);
      expect(flow.facts.activationsOf(get), hasLength(1));
    },
  );

  for (final throwing in [false, true]) {
    test(
      'shared ${throwing ? 'exceptional' : 'normal'} writes restore each caller graph',
      () {
        final fixture = _Fixture();
        final change = FunctionTarget(_uri, 'change', fixture.box, [
          fixture.box,
        ]);
        final body = Block(change.parameterTypes);
        body.emit(
          StoreField(
            fixture.flag,
            body.parameters.single,
            const Constant.integer(2),
          ),
        );
        body.finish(
          throwing
              ? Throw(body.parameters.single)
              : Return(body.parameters.single),
        );
        final functions = <IrFunction>[
          IrFunction(change, [body]),
        ];
        final roots = <FunctionTarget>[];
        final observations = <(Instruction, Instruction, Instruction)>[];
        for (var i = 0; i < 8; i++) {
          final target = FunctionTarget(_uri, 'root$i', .integer, []);
          roots.add(target);
          final entry = Block(), done = Block(), caught = Block();
          final owner = entry.emit(
            DirectCall(fixture.make, [Constant.integer(i)]),
          );
          final call = DirectCall(change, [owner]);
          entry.finish(
            Invoke(call, onReturn: Jump(done), onThrow: Jump(caught)),
          );
          final selected = throwing ? caught : done;
          final flag = selected.emit(LoadField(fixture.flag, owner));
          final child = selected.emit(LoadField(fixture.link, owner));
          final value = selected.emit(LoadField(fixture.value, child));
          selected.finish(
            Return(
              selected.emit(
                IntBinary(.add, selected.emit(NullCheck(flag)), value),
              ),
            ),
          );
          (throwing ? done : caught).finish(const Return(Constant.integer(-1)));
          observations.add((owner, call, flag));
          functions.add(IrFunction(target, [entry, done, caught]));
        }
        final program = fixture.program(functions);
        final facts = ProgramFlow(program, [
          for (final target in roots)
            (target: target, arguments: <FlowValue>[]),
        ]).facts;
        expect(facts.activationsOf(change), hasLength(1));
        for (final (i, target) in roots.indexed) {
          expect(_scalar(facts.returnedBy(target)), i + 2);
          final (owner, call, flag) = observations[i];
          expect(_scalar(facts.valueOf(flag)), 2);
          expect(
            (throwing ? facts.failureOf(call).exception : facts.valueOf(call))
                .objects,
            facts.valueOf(owner).objects,
          );
        }
      },
    );
  }
}

final class _Fixture() {
  final child = ClassType(_uri, 'Child');
  final box = ClassType(_uri, 'Box');
  late final link = InstanceField(box, 'child', child);
  late final value = InstanceField(child, 'value', ValueType.integer);
  late final flag = InstanceField(box, 'flag', ValueType.integer.nullable);
  late final make = FunctionTarget(_uri, 'make', box, [.integer]);
  late final IrFunction factory = _factory();

  IrFunction _factory() {
    final body = Block(make.parameterTypes);
    final nested = body.emit(NewPayload(child, const Constant.integer(0)));
    body.emit(StoreField(value, nested, body.parameters.single));
    final owner = body.emit(NewPayload(box, const Constant.integer(0)));
    body.emit(StoreField(link, owner, nested));
    body.finish(Return(owner));
    return IrFunction(make, [body]);
  }

  IrProgram program(List<IrFunction> functions) => IrProgram(
    [
      IrClass(child, [value]),
      IrClass(box, [link, flag]),
    ],
    [factory, ...functions],
  );
}

Object? _scalar(FlowValue value) => (value.constant as ScalarConstant?)?.value;
