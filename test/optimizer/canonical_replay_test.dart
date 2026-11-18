import 'package:dartc/codegen.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/optimizer/function_rewrite.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

Iterable<Instruction> _operations(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

void main() {
  test('type and carrier recipes consume the actual canonical operands', () {
    final root = FunctionTarget(null, 'typeAndCarrier', .object, [
      .boolean,
      .object.nullable,
    ]);
    final entry = Block(root.parameterTypes), yes = Block(), no = Block();
    entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    yes.finish(Return(yes.emit(TypeTest(entry.parameters.last, .nullType))));
    no.finish(const Return(Constant.string('dormant')));
    final source = IrProgram([], [
      IrFunction(root, [entry, yes, no]),
    ]);
    final type = TypeLowering(TypeImplementations(), failure: null).bind();
    final carrier = RepresentationLowering().bind();
    ProgramFlowFacts solve(IrProgram graph, bool? choice) =>
        ProgramFlow(graph, [
          (
            target: root,
            arguments: [
              choice == null
                  ? FlowValue.unknown(.boolean)
                  : FlowValue.constant(Constant.boolean(choice)),
              FlowValue.unknown(.object.nullable),
            ],
          ),
        ]).facts;
    final untouched = type(solve(source, false));
    expect(untouched, same(source));
    final canonical = carrier(solve(untouched, false));
    final known = {
      ...type.realizations.map((r) => r.key),
      ...carrier.realizations.map((r) => r.key),
    };
    final current = solve(canonical, null);
    type(current);
    carrier(current);
    var replayed = canonical;
    type.rebase(canonical);
    carrier.rebase(canonical);
    for (final recipe in [...type.realizations, ...carrier.realizations]) {
      if (!known.contains(recipe.key)) replayed = recipe.apply(replayed);
    }
    // Complete any boundary newly exposed by the type implementation itself.
    replayed = carrier(solve(replayed, null));
    final body = replayed.implementationOf(root) as IrFunction;
    expect(_operations(body).whereType<TypeTest>(), isEmpty);
    expect(
      _operations(body).whereType<Equals>().single.inputs.first,
      isA<BlockParameter>(),
    );
    replayed.executionShapes!.verify(body);
    for (final value in [null, 42, 'value']) {
      expect(
        IrInterpreter(replayed, {}).run(body, [true, value]),
        value == null,
      );
      expect(IrInterpreter(replayed, {}).run(body, [false, value]), 'dormant');
    }
  });

  for (final invalid in [false, true]) {
    test(
      'one immutable demand batch keeps each owner accountable ($invalid)',
      () {
        final first = FunctionTarget(null, 'first', .integer, [.integer]);
        final second = FunctionTarget(null, 'second', .integer, [.integer]);
        final root = FunctionTarget(null, 'root', .integer, [.integer]);
        final entry = Block(root.parameterTypes);
        final one = entry.emit(DirectCall(first, entry.parameters));
        entry.finish(Return(entry.emit(DirectCall(second, [one]))));
        IrFunction body(FunctionTarget target, int increment) {
          final block = Block(target.parameterTypes);
          block.finish(
            Return(
              block.emit(
                IntBinary(
                  .add,
                  block.parameters.single,
                  Constant.integer(increment),
                ),
              ),
            ),
          );
          return IrFunction(target, [block]);
        }

        final source = IrProgram(
          [],
          [
            IrFunction(root, [entry]),
          ],
          externals: [
            for (final target in [first, second])
              IrExternal(
                target,
                effects: const [],
                terminates: true,
                capturesArguments: false,
              ),
          ],
        );
        final seen = <IrProgram>[], analyzed = <IrProgram>[];
        final optimizer = ProgramOptimizer([
          _BatchImplementation(body(first, 1), seen),
          _BatchImplementation(body(second, 2), seen, invalid: invalid),
        ]);
        ProgramFlowFacts run() => optimizer.run(
          source,
          [
            (target: root, arguments: [FlowValue.unknown(.integer)]),
          ],
          memoryLayoutFor: (graph) {
            analyzed.add(graph);
            return ProgramLayout(
              graph.classes,
              nativeLayout: NativeLayout(const Target(.linux, .arm64)),
            );
          },
        );
        if (invalid) {
          expect(
            run,
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('canonical source recipe'),
              ),
            ),
          );
          expect(analyzed, [source]);
        } else {
          final result = run();
          expect(seen.take(2), [source, source]);
          expect(analyzed, hasLength(2));
          expect(
            IrInterpreter(
              result.program,
              {},
            ).run(result.program.implementationOf(root) as IrFunction, [39]),
            42,
          );
        }
      },
    );
  }
  for (final throwing in [false, true]) {
    test(
      'replay restores root, recursive callers and shared state ($throwing)',
      () {
        final fixture = _ReplayFixture(throwing);
        final lowerer = _DeferredImplementation(fixture.implementation);
        var bindings = 0, applications = 0, resets = 0;
        final expansion = _Pass(.expansion, () {
          bindings++;
          return ProgramTransform((facts) {
            applications++;
            return facts.program;
          }, rebase: (_) => resets++);
        });
        final graphs = <IrProgram>[];
        final result =
            ProgramOptimizer([
              const ProgramSimplification(),
              expansion,
              lowerer,
            ]).run(
              fixture.program,
              fixture.entries,
              memoryLayoutFor: (program) {
                graphs.add(program);
                return ProgramLayout(
                  program.classes,
                  nativeLayout: NativeLayout(const Target(.linux, .arm64)),
                );
              },
            );
        expect(lowerer.discoveries, 1);
        expect(lowerer.staleHelperResult, 65);
        expect(bindings, 1);
        expect(resets, 1);
        expect(applications, greaterThanOrEqualTo(2));
        expect(graphs.last, same(result.program));
        final runner = IrInterpreter(result.program, {});
        expect(
          runner.run(
            result.program.implementationOf(fixture.root) as IrFunction,
            [true, 2],
          ),
          throwing ? 66 : 2,
        );
        expect(
          runner.run(
            result.program.implementationOf(fixture.read) as IrFunction,
            [],
          ),
          66,
        );
        // The new call enters root(false, 2); it is not an unknown extra root.
        expect(
          result.definitions,
          containsAll([fixture.root, fixture.support]),
        );
        expect(result.coversEntry(fixture.root), isFalse);
      },
    );
  }

  for (final invalid in ['missing', 'repeated']) {
    test('an $invalid replay recipe cannot accept a specialized graph', () {
      final fixture = _ReplayFixture(false);
      expect(
        () => ProgramOptimizer([
          const ProgramSimplification(),
          _DeferredImplementation(fixture.implementation, invalid: invalid),
        ]).run(fixture.program, fixture.entries),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('canonical source recipe'),
          ),
        ),
      );
    });
  }

  test('callable recipe rebinds an inline demand using canonical operands', () {
    final first = FunctionTarget(null, 'first', .integer, [.integer]);
    final second = FunctionTarget(null, 'second', .integer, [.integer]);
    IrFunction source(FunctionTarget target, int increment) {
      final block = Block(target.parameterTypes);
      block.finish(
        Return(
          block.emit(
            IntBinary(
              .add,
              block.parameters.single,
              Constant.integer(increment),
            ),
          ),
        ),
      );
      return IrFunction(target, [block]);
    }

    final shared = FunctionTarget(null, 'shared', .integer, [
      first.signature,
      .integer,
    ]);
    final block = Block(shared.parameterTypes);
    final sourceCall = block.emit(
      FunctionCall(block.parameters.first, [block.parameters.last]),
    );
    block.finish(Return(sourceCall));
    final sourceBody = IrFunction(shared, [block]);
    final root = FunctionTarget(null, 'root', .integer, [.integer]);
    final probe = FunctionTarget(null, 'probe', .integer, [.integer]);
    IrFunction caller(FunctionTarget target, FunctionTarget callee) {
      final block = Block(target.parameterTypes);
      block.finish(
        Return(
          block.emit(
            DirectCall(shared, [
              FunctionConstant(callee),
              block.parameters.single,
            ]),
          ),
        ),
      );
      return IrFunction(target, [block]);
    }

    final original = IrProgram([], [
      source(first, 1),
      source(second, 2),
      sourceBody,
      caller(root, first),
      caller(probe, second),
    ]);
    ProgramFlowFacts solve(
      IrProgram program,
      FunctionTarget target,
      int argument,
    ) => ProgramFlow(program, [
      (
        target: target,
        arguments: [FlowValue.constant(Constant.integer(argument))],
      ),
    ]).facts;
    final lowering = CallableLowering(CallableImplementations()).bind();
    final canonical = lowering(solve(original, root, 17));
    final known = lowering.realizations.map((recipe) => recipe.key).toSet();
    final probeBody = canonical.implementationOf(probe) as IrFunction;
    final call = _operations(probeBody).whereType<DirectCall>().single;
    final expanded = FunctionRewrite(
      probeBody,
      inlined: {
        call: (
          body: canonical.implementationOf(shared) as IrFunction,
          arguments: call.inputs.toList(),
          environment: const {},
          handler: null,
        ),
      },
    ).run();
    final copiedCall = _operations(expanded).whereType<FunctionCall>().single;
    expect(
      expanded.originOf(copiedCall).source,
      sourceBody.originOf(sourceCall),
    );
    expect(expanded.originOf(copiedCall).path, isNotEmpty);
    final candidate = IrProgram(canonical.classes, [
      for (final body in canonical.functions)
        body.target == probe ? expanded : body,
    ], executionShapes: canonical.executionShapes);
    lowering(solve(candidate, probe, 41));
    final recipes = lowering.realizations
        .where((recipe) => !known.contains(recipe.key))
        .toList();
    expect(recipes, hasLength(1));
    lowering.rebase(canonical);
    final replayed = recipes.single.apply(canonical);
    expect(solve(replayed, root, 17).definitions, isNot(contains(second)));
    final actual = solve(replayed, probe, 73);
    expect(actual.pendingExecutionCalls, isEmpty);
    expect((actual.returnedBy(probe).constant as ScalarConstant).value, 75);
    expect(
      IrInterpreter(
        replayed,
        {},
      ).run(replayed.implementationOf(probe) as IrFunction, [73]),
      75,
    );
    final rebound = _operations(replayed.implementationOf(shared) as IrFunction)
        .whereType<FunctionCall>()
        .single;
    expect(rebound.positional.single, isA<BlockParameter>());
  });

  test(
    'branch copies replay for free without buying another incoming path',
    () {
      final target = FunctionTarget(null, 'branch', .integer, [
        .boolean,
        .boolean,
        .object,
      ]);
      final entry = Block(target.parameterTypes),
          choice = Block(),
          header = Block([ValueType.object]),
          yes = Block(),
          no = Block();
      entry.finish(
        Branch(
          entry.parameters.first,
          Jump(header, const [Constant.integer(7)]),
          Jump(choice),
        ),
      );
      choice.finish(
        Branch(
          entry.parameters[1],
          Jump(header, const [Constant.integer(8)]),
          Jump(header, [entry.parameters.last]),
        ),
      );
      final check = header.emit(TypeTest(header.parameters.single, .integer));
      header.finish(Branch(check, Jump(yes), Jump(no)));
      yes.finish(const Return(Constant.integer(1)));
      no.finish(const Return(Constant.integer(0)));
      final body = IrFunction(target, [entry, choice, header, yes, no]);
      final canonical = IrProgram([], [body]);
      final roots = [
        (
          target: target,
          arguments: target.parameterTypes.map(FlowValue.unknown).toList(),
        ),
      ];
      ProgramFlowFacts solve(IrProgram graph) =>
          ProgramFlow(graph, roots).facts;
      final pass = const ProgramBranchSpecialization(maxCodeGrowth: 5).bind();
      final first = pass(solve(canonical));
      expect(first, isNot(same(canonical)));
      expect(pass(solve(first)), same(first));
      pass.rebase(canonical);
      final replayed = pass(solve(canonical));
      expect(replayed, isNot(same(canonical)));
      expect(pass(solve(replayed)), same(replayed));
      Set<IrOrigin> copies(IrProgram graph) =>
          (graph.implementationOf(target) as IrFunction).originBindings.values
              .where((origin) => origin.path.isNotEmpty)
              .toSet();
      expect(copies(first), isNotEmpty);
      expect(copies(replayed), copies(first));
      // A fresh compilation has its own budget and can copy the second edge.
      expect(
        const ProgramBranchSpecialization(maxCodeGrowth: 5).run(solve(first)),
        isNot(same(first)),
      );
      for (final a in [false, true]) {
        for (final b in [false, true]) {
          for (final value in [9, 'text']) {
            expect(
              IrInterpreter(replayed, {}).run(
                replayed.implementationOf(target) as IrFunction,
                [a, b, value],
              ),
              a || b || value is int ? 1 : 0,
            );
          }
        }
      }
    },
  );

  test('loop copies keep stable origins and one compilation growth ledger', () {
    final target = FunctionTarget(null, 'loop', .integer, []);
    final entry = Block(),
        header = Block([ValueType.integer]),
        step = Block(),
        done = Block();
    entry.finish(Jump(header, const [Constant.integer(0)]));
    final index = header.parameters.single;
    header.finish(
      Branch(
        header.emit(IntBinary(.lessThan, index, const Constant.integer(4))),
        Jump(step),
        Jump(done),
      ),
    );
    step.finish(
      Jump(header, [
        step.emit(IntBinary(.add, index, const Constant.integer(1))),
      ]),
    );
    done.finish(Return(index));
    final canonical = IrProgram([], [
      IrFunction(target, [entry, header, step, done]),
    ]);
    ProgramFlowFacts solve(IrProgram graph) =>
        ProgramFlow(graph, [(target: target, arguments: <FlowValue>[])]).facts;
    int size(IrProgram graph) =>
        (graph.implementationOf(target) as IrFunction).blocks.fold(
          0,
          (n, block) =>
              n + block.parameters.length + block.instructions.length + 1,
        );
    final measured = const ProgramLoopSpecialization().run(solve(canonical));
    final cost = size(measured) - size(canonical);
    expect(cost, greaterThan(0));
    final pass = ProgramLoopSpecialization(maxCodeGrowth: cost).bind();
    final first = pass(solve(canonical));
    expect(first, isNot(same(canonical)));
    expect(pass(solve(first)), same(first));
    pass.rebase(canonical);
    final replayed = pass(solve(canonical));
    expect(replayed, isNot(same(canonical)));
    expect(pass(solve(replayed)), same(replayed));
    Set<IrOrigin> copies(IrProgram graph) =>
        (graph.implementationOf(target) as IrFunction).originBindings.values
            .where((origin) => origin.path.isNotEmpty)
            .toSet();
    expect(copies(replayed), copies(first));
    expect(
      ProgramLoopSpecialization(maxCodeGrowth: cost).run(solve(first)),
      isNot(same(first)),
    );
    expect(
      IrInterpreter(
        replayed,
        {},
      ).run(replayed.implementationOf(target) as IrFunction, []),
      4,
    );
  });
}

final class _ReplayFixture(final bool throwing) {
  final helper = FunctionTarget(null, 'sharedHelper', .integer, [.integer]);
  final root = FunctionTarget(null, 'recursiveRoot', .integer, [
    .boolean,
    .integer,
  ]);
  final support = FunctionTarget(null, 'materialization', .integer, [.integer]);
  final read = FunctionTarget(null, 'readState', .integer, []);
  final saved = GlobalVariable(
    Uri.parse('memory:replay'),
    'saved',
    .integer,
    isLate: true,
  );
  late final program = build();
  late final IrFunction implementation = _implementation();
  List<FlowEntry> get entries => [
    (
      target: root,
      arguments: [
        FlowValue.constant(const Constant.boolean(true)),
        FlowValue.constant(const Constant.integer(2)),
      ],
    ),
  ];

  IrProgram build() {
    final helperBlock = Block(helper.parameterTypes);
    helperBlock.finish(
      Return(
        helperBlock.emit(
          IntBinary(
            .add,
            helperBlock.parameters.single,
            const Constant.integer(64),
          ),
        ),
      ),
    );
    final entry = Block(root.parameterTypes),
        yes = Block(),
        no = Block(),
        normal = Block([ValueType.integer]),
        caught = Block();
    entry.finish(Branch(entry.parameters.first, Jump(yes), Jump(no)));
    yes.emit(
      StoreGlobal(
        saved,
        yes.emit(DirectCall(helper, [const Constant.integer(1)])),
      ),
    );
    final materialize = DirectCall(support, [entry.parameters.last]);
    yes.finish(
      Invoke(
        materialize,
        onReturn: Jump(normal, [materialize]),
        onThrow: Jump(caught),
      ),
    );
    normal.finish(Return(normal.parameters.single));
    caught.finish(Return(caught.emit(LoadGlobal(saved))));
    no.finish(Return(no.emit(DirectCall(helper, [entry.parameters.last]))));
    final readBlock = Block();
    readBlock.finish(Return(readBlock.emit(LoadGlobal(saved))));
    return IrProgram(
      [],
      [
        IrFunction(helper, [helperBlock]),
        IrFunction(root, [entry, yes, no, normal, caught]),
        IrFunction(read, [readBlock]),
      ],
      globals: [saved],
      externals: [
        IrExternal(
          support,
          effects: [
            Effect.writesStorage,
            Effect.callsUserCode,
            Effect.mayThrow,
          ],
          capturesArguments: false,
        ),
      ],
    );
  }

  IrFunction _implementation() {
    final supportBlock = Block(support.parameterTypes);
    final callback = supportBlock.emit(
      DirectCall(root, [
        const Constant.boolean(false),
        supportBlock.parameters.single,
      ]),
    );
    supportBlock.emit(StoreGlobal(saved, callback));
    supportBlock.finish(
      throwing
          ? Throw(const Constant.integer(123))
          : Return(supportBlock.parameters.single),
    );
    return IrFunction(support, [supportBlock]);
  }
}

// A supplied leaf implementation is deliberately discovered only after its
// actual input is exposed. This exercises the same late-call invalidation as a
// generated allocator/type/call bridge, without building an SDK runtime.
final class _DeferredImplementation(
  final IrFunction implementation, {
  final String? invalid,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;
  var discoveries = 0;
  Object? staleHelperResult;
  @override
  ProgramTransform bind() {
    final recipes = <Object, ProgramRealization>{};
    IrProgram install(IrProgram program) => IrProgram(
      program.classes,
      [
        ...program.functions.where(
          (body) => body.target != implementation.target,
        ),
        implementation,
      ],
      globals: program.globals,
      externals: program.externals.where(
        (body) => body.target != implementation.target,
      ),
      executionShapes: program.executionShapes,
    );
    return ProgramTransform((facts) {
      if (facts.program.implementationOf(implementation.target) is IrFunction)
        return facts.program;
      for (final body in facts.program.functions) {
        for (final op in _operations(body)) {
          if (op is! DirectCall ||
              op.target != implementation.target ||
              op.inputs.single is! Constant ||
              !facts.reachesOperation(op))
            continue;
          final key = (body.originOf(op).source, implementation.target);
          if (!recipes.containsKey(key)) {
            discoveries++;
            final helper = facts.program.functions.firstWhere(
              (f) => f.target.name == 'sharedHelper',
            );
            staleHelperResult = switch (helper.entry.end) {
              Return(value: ScalarConstant(:final value)) => value,
              _ => null,
            };
          }
          if (invalid != 'missing')
            recipes.putIfAbsent(
              key,
              () => ProgramRealization(
                key,
                invalid == 'repeated' ? (canonical) => canonical : install,
              ),
            );
          return install(facts.program);
        }
      }
      return facts.program;
    }, realizations: () => recipes.values);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _Pass(
  @override final ProgramPassKind kind,
  final ProgramTransform Function() binding,
) extends ProgramPass {
  @override
  ProgramTransform bind() => binding();
  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}

final class _BatchImplementation(
  final IrFunction body,
  final List<IrProgram> seen, {
  final bool invalid = false,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;
  @override
  ProgramTransform bind() {
    final recipes = <Object, ProgramRealization>{};
    IrProgram install(IrProgram graph) => IrProgram(
      graph.classes,
      [...graph.functions, body],
      externals: graph.externals.where(
        (external) => external.target != body.target,
      ),
    );
    return ProgramTransform((facts) {
      seen.add(facts.program);
      if (facts.program.implementationOf(body.target) is IrFunction)
        return facts.program;
      if (!invalid)
        recipes.putIfAbsent(
          body.target,
          () => ProgramRealization(body.target, install),
        );
      return install(facts.program);
    }, realizations: () => recipes.values);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);
}
