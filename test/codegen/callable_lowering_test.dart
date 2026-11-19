import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/callable_implementations.dart';
import 'package:dartc/src/codegen/callable_lowering.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:callable-lowering');
  void check(
    IrProgram original,
    FunctionTarget root,
    int expected, {
    bool select = true,
  }) {
    final implementations = CallableImplementations();
    final sourceFacts = ProgramFlow(original, [
      (target: root, arguments: []),
    ]).facts;
    final lowered = CallableLowering(implementations).run(sourceFacts);
    final facts = ProgramFlow(lowered, [(target: root, arguments: [])]).facts;
    expect((facts.returnedBy(root).constant as ScalarConstant).value, expected);
    expect(
      IrInterpreter(
        lowered,
        {},
      ).run(lowered.implementationOf(root)! as IrFunction, []),
      expected,
    );
    expect(implementations.functions, isNotEmpty);
    expect(
      implementations.functions
          .expand((body) => body.blocks)
          .expand((block) => block.instructions)
          .whereType<FunctionCall>(),
      isEmpty,
    );
    if (select) {
      final storage = ClosureStorage(
        lowered.functions,
        callableImplementations: implementations,
        boundMethods: [
          for (final target in facts.definitions)
            if (target.kind.isVirtual) target,
        ],
      );
      final layouts = ProgramLayout(
        [...lowered.classes, ...storage.classes],
        closureStorage: storage,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      for (final body in implementations.functions) {
        final selected = FunctionRepresentation(
          body,
          layouts,
          CheckedCasts(),
          MemberCalls(lowered, facts.definitions, callTypes: facts),
          HeapPlan(),
        );
        expect(
          {
            ...selected.invocations.values,
            ...selected.instructions.values
                .expand((values) => values)
                .whereType<DirectCall>()
                .map((call) => call.target),
          },
          containsAll(
            body.blocks
                .expand((block) => block.instructions)
                .whereType<DirectCall>()
                .map((call) => call.target),
          ),
        );
        expect(selected.blocks.length, body.blocks.length);
      }
    }
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      ProgramBranchSpecialization(),
      ProgramLoopSpecialization(),
      DirectCallInlining(),
    ]).run(lowered, [(target: root, arguments: [])]);
    expect(
      (optimized.returnedBy(root).constant as ScalarConstant).value,
      expected,
    );
    expect(
      IrInterpreter(
        optimized.program,
        {},
      ).run(optimized.program.implementationOf(root)! as IrFunction, []),
      expected,
    );
  }

  test(
    'the actual adapter reads the original shared cell before source writes',
    () {
      final root = FunctionTarget(uri, 'root', .integer, []);
      final closure = FunctionTarget(
        uri,
        'write',
        .integer,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 1,
        captures: [CellType(.integer)],
      );
      final body = Block(closure.parameterTypes);
      body.emit(WriteCell(body.parameters[1], const Constant.integer(9)));
      body.finish(Return(body.emit(ReadCell(body.parameters[1]))));
      final entry = Block();
      final cell = entry.emit(
        NewCell(CellType(.integer), const Constant.integer(1)),
      );
      final fn = entry.emit(MakeClosure(closure, [cell]));
      entry.emit(FunctionCall(fn, []));
      entry.finish(Return(entry.emit(ReadCell(cell))));
      check(
        IrProgram([], [
          IrFunction(root, [entry]),
          IrFunction(closure, [body]),
        ]),
        root,
        9,
      );
    },
  );

  test('capture constants can specialize after the entry is explicit', () {
    final root = FunctionTarget(uri, 'scalarRoot', .integer, []);
    final closure = FunctionTarget(
      uri,
      'capture',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 2,
      captures: [.integer],
    );
    final body = Block(closure.parameterTypes);
    body.finish(Return(body.parameters[1]));
    final entry = Block();
    final fn = entry.emit(MakeClosure(closure, [const Constant.integer(42)]));
    entry.finish(Return(entry.emit(FunctionCall(fn, []))));
    check(
      IrProgram([], [
        IrFunction(root, [entry]),
        IrFunction(closure, [body]),
      ]),
      root,
      42,
    );
  });

  test('an environment source label cannot replace actual origin proof', () {
    final root = FunctionTarget(uri, 'wrongOrigin', .integer, []);
    final first = FunctionTarget(
      uri,
      'first',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 3,
      captures: [.integer],
    );
    final second = FunctionTarget(
      uri,
      'second',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 4,
      captures: [.integer],
    );
    IrFunction body(FunctionTarget target) {
      final block = Block(target.parameterTypes);
      block.finish(Return(block.parameters[1]));
      return IrFunction(target, [block]);
    }

    final entry = Block();
    final value = entry.emit(MakeClosure(first, [const Constant.integer(42)]));
    final read = entry.emit(ReadFunctionEnvironment(value, second, capture: 0));
    entry.finish(Return(read));
    final program = IrProgram([], [
      IrFunction(root, [entry]),
      body(first),
      body(second),
    ]);
    expect(
      () => ProgramFlow(program, [(target: root, arguments: [])]).facts,
      throwsStateError,
    );
    expect(
      () => IrInterpreter(
        program,
        {},
      ).run(program.implementationOf(root)! as IrFunction, []),
      throwsStateError,
    );
    expect(
      () => DirectCall(second, [value, const Constant.integer(42)]),
      throwsArgumentError,
    );
  });

  for (final wrongType in [false, true]) {
    test(
      'bound receiver ${wrongType ? 'preserves prior effects on covariant failure' : 'receives source side effects'}',
      () {
        final owner = ClassType(uri, 'Box');
        final field = InstanceField(owner, 'value', .integer);
        final init = FunctionTarget(
          uri,
          'new',
          .voidType,
          [],
          kind: .initializer,
          owner: owner,
        );
        final initializer = Block(init.parameterTypes);
        initializer.emit(
          StoreField(
            field,
            initializer.parameters.first,
            const Constant.integer(7),
          ),
        );
        initializer.finish(const Return());
        final method = FunctionTarget(
          uri,
          'set',
          .integer,
          [.integer],
          kind: .method,
          owner: owner,
          covariantParameters: [0],
        );
        final body = Block(method.parameterTypes);
        body.emit(
          StoreField(field, body.parameters.first, body.parameters.last),
        );
        body.finish(Return(body.emit(LoadField(field, body.parameters.first))));
        final root = FunctionTarget(uri, 'root', .integer, []);
        final entry = Block(), done = Block([.integer]), failed = Block();
        final receiver = entry.emit(Construct(init, []));
        final fn = entry.emit(BindMethod(method, receiver, direct: true));
        final view = wrongType
            ? entry.emit(TypeCast(fn, method.reifiedSignature))
            : fn;
        final call = FunctionCall(view, [
          wrongType ? const Constant.string('bad') : const Constant.integer(9),
        ]);
        entry.finish(
          Invoke(call, onReturn: Jump(done, [call]), onThrow: Jump(failed)),
        );
        done.finish(Return(done.emit(LoadField(field, receiver))));
        failed.finish(Return(failed.emit(LoadField(field, receiver))));
        final program = IrProgram(
          [
            IrClass(owner, [field], constructors: [init], members: [method]),
          ],
          [
            IrFunction(root, [entry, done, failed]),
            IrFunction(init, [initializer]),
            IrFunction(method, [body]),
          ],
        );
        check(program, root, wrongType ? 7 : 9, select: !wrongType);
      },
    );
  }
  test('generic operands reach a concrete function through its adapter', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final signature = FunctionType(
      .integer,
      [t, t],
      namedParameters: {'other': true},
    );
    final apply = FunctionTarget(
      uri,
      'apply',
      .integer,
      [signature, t, t],
      typeParameters: [t],
    );
    final caller = Block(apply.parameterTypes);
    caller.finish(
      Return(
        caller.emit(
          FunctionCall(
            caller.parameters[0],
            [caller.parameters[1]],
            {'other': caller.parameters[2]},
          ),
        ),
      ),
    );

    final add = FunctionTarget(
      uri,
      'add',
      .integer,
      [.integer, .integer],
      namedParameters: {'other': true},
    );
    final target = Block(add.parameterTypes);
    target.finish(
      Return(
        target.emit(
          IntBinary(.add, target.parameters.first, target.parameters.last),
        ),
      ),
    );
    final root = FunctionTarget(uri, 'root', .integer, []);
    final entry = Block();
    entry.finish(
      Return(
        entry.emit(
          DirectCall(
            apply,
            [
              FunctionConstant(add),
              const Constant.integer(29),
              const Constant.integer(13),
            ],
            typeArguments: const [ValueType.integer],
          ),
        ),
      ),
    );
    final graph = IrProgram([], [
      IrFunction(root, [entry]),
      IrFunction(apply, [caller]),
      IrFunction(add, [target]),
    ]);
    check(graph, root, 42, select: false);
  });
  test('generic function values enter a checked typed adapter', () {
    final t = TypeParameterType('T')..initializeBound(.number);
    final source = FunctionTarget(uri, 'identity', t, [t], typeParameters: [t]);
    final sourceBody = Block(source.parameterTypes);
    sourceBody.finish(Return(sourceBody.parameters.single));
    final root = FunctionTarget(uri, 'genericRoot', .integer, []);
    final entry = Block();
    entry.finish(
      Return(
        entry.emit(
          FunctionCall(
            FunctionConstant(source),
            const [Constant.integer(42)],
            const {},
            const [ValueType.integer],
          ),
        ),
      ),
    );
    final program = IrProgram(
      [
        for (final type in TypeMetadata.fields.entries)
          IrClass(type.key, type.value),
      ],
      [
        IrFunction(root, [entry]),
        IrFunction(source, [sourceBody]),
      ],
    );
    check(program, root, 42, select: false);
  });
  test('generic closure separates captured T from supplied U and preserves cell state', () {
    for (final (sameType, instantiated) in [
      (true, false),
      (false, false),
      (true, true),
      (false, true),
    ]) {
      final t = TypeParameterType('T')..initializeBound(.object);
      final u = TypeParameterType('U')..initializeBound(.object);
      final outer = FunctionTarget(uri, 'outer', t, [t], typeParameters: [t]);
      final cellType = CellType(t);
      final source = FunctionTarget(
        uri,
        'nested',
        t,
        [u],
        typeParameters: [u],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 1,
        captures: [cellType],
      );
      final nested = Block(source.parameterTypes);
      nested.emit(
        WriteCell(
          nested.parameters[1],
          nested.emit(TypeCast(nested.parameters.last, t)),
        ),
      );
      nested.finish(Return(nested.emit(ReadCell(nested.parameters[1]))));
      final entry = Block(outer.parameterTypes),
          normal = Block(),
          caught = Block();
      final cell = entry.emit(NewCell(cellType, entry.parameters.single));
      final closure = entry.emit(MakeClosure(source, [cell]));
      final actualType = sameType ? ValueType.integer : ValueType.string;
      final function = instantiated
          ? entry.emit(InstantiateFunction(closure, [actualType]))
          : closure;
      final call = FunctionCall(
        function,
        [sameType ? const Constant.integer(42) : const Constant.string('bad')],
        const {},
        instantiated ? const [] : [actualType],
      );
      entry.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)));
      normal.finish(Return(normal.emit(ReadCell(cell))));
      caught.finish(Return(caught.emit(ReadCell(cell))));
      final root = FunctionTarget(uri, 'nestedRoot', .integer, []);
      final start = Block();
      start.finish(
        Return(
          start.emit(
            DirectCall(
              outer,
              const [Constant.integer(7)],
              typeArguments: const [ValueType.integer],
            ),
          ),
        ),
      );
      final program = IrProgram(
        [
          for (final type in TypeMetadata.fields.entries)
            IrClass(type.key, type.value),
        ],
        [
          IrFunction(root, [start]),
          IrFunction(outer, [entry, normal, caught]),
          IrFunction(source, [nested]),
        ],
      );
      check(program, root, sameType ? 42 : 7, select: false);
    }
  });

  test('an instantiated constant reads its stored argument through the common entry', () {
    final t = TypeParameterType('T')..initializeBound(.number);
    final source = FunctionTarget(
      uri,
      'instantiated',
      t,
      [t],
      typeParameters: [t],
    );
    final sourceEntry = Block(source.parameterTypes);
    sourceEntry.finish(Return(sourceEntry.parameters.single));
    final root = FunctionTarget(uri, 'instantiatedRoot', .integer, []);
    final entry = Block();
    entry.finish(
      Return(
        entry.emit(
          FunctionCall(
            FunctionConstant(source, typeArguments: const [ValueType.integer]),
            const [Constant.integer(42)],
          ),
        ),
      ),
    );
    final program = IrProgram(
      [
        for (final type in TypeMetadata.fields.entries)
          IrClass(type.key, type.value),
      ],
      [
        IrFunction(root, [entry]),
        IrFunction(source, [sourceEntry]),
      ],
    );
    check(program, root, 42, select: false);
  });
  test('a fresh owner retains a bound adapter and its exceptional writes', () {
    final state = GlobalVariable(uri, 'adapterState', .integer, isLate: true);
    final source = FunctionTarget(uri, 'sourceIdentity', .integer, []);
    final sourceBlock = Block()..finish(const Return(Constant.integer(0)));
    final shape = CallEntryShape(3, .integer, []);
    final adapter = FunctionTarget(
      uri,
      'actualEntry',
      .integer,
      shape.signature.parameters,
    );
    final adapterBlock = Block(adapter.parameterTypes);
    adapterBlock.emit(StoreGlobal(state, const Constant.integer(9)));
    adapterBlock.finish(Throw(const Constant.string('failure')));
    final root = FunctionTarget(uri, 'rootBound', .integer, []);
    final entry = Block(), normal = Block(), caught = Block();
    final call = FunctionCall(
      FunctionConstant(source),
      const [],
      const {},
      const [],
      null,
      CallEntryBinding(shape, {source: adapter}),
    );
    entry.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)));
    normal.finish(const Return(Constant.integer(0)));
    caught.finish(Return(caught.emit(LoadGlobal(state))));
    var program = IrProgram(
      [],
      [
        IrFunction(source, [sourceBlock]),
        IrFunction(adapter, [adapterBlock]),
        IrFunction(root, [entry, normal, caught]),
      ],
      globals: [state],
    );
    for (var i = 0; i < 2; i++) {
      final owner = CallableImplementations();
      final facts = ProgramFlow(program, [
        (target: root, arguments: const []),
      ]).facts;
      program = CallableLowering(owner).run(facts);
      expect(owner.entriesFor(source)[shape], adapter);
      expect(
        IrInterpreter(
          program,
          {},
        ).run(program.implementationOf(root) as IrFunction, []),
        9,
      );
      expect(owner.functions.single.target, adapter);
    }
  });
  for (final widened in [false, true]) {
    test(
      'Never source preserves exceptional writes through ${widened ? 'int' : 'Never'} callable view',
      () {
        final state = GlobalVariable(uri, 'neverState', .integer, isLate: true);
        final source = FunctionTarget(uri, 'neverSource', .never, []);
        final sourceBlock = Block();
        sourceBlock.emit(StoreGlobal(state, const Constant.integer(73)));
        sourceBlock.finish(Throw(const Constant.string('stop')));
        final root = FunctionTarget(uri, 'neverRoot', .integer, []);
        final start = Block(), caught = Block(), normal = Block([.integer]);
        final function = widened
            ? start.emit(
                TypeView(FunctionConstant(source), FunctionType(.integer, [])),
              )
            : FunctionConstant(source);
        final call = FunctionCall(function, const []);
        start.finish(
          Invoke(
            call,
            onReturn: widened ? Jump(normal, [call]) : null,
            onThrow: Jump(caught),
          ),
        );
        caught.finish(Return(caught.emit(LoadGlobal(state))));
        if (widened) normal.finish(Return(normal.parameters.single));
        final body = IrFunction(root, [start, if (widened) normal, caught]);
        final original = IrProgram(
          [],
          [
            body,
            IrFunction(source, [sourceBlock]),
          ],
          globals: [state],
        );
        expect(IrInterpreter(original, {}).run(body, []), 73);
        final sourceFacts = ProgramFlow(original, [
          (target: root, arguments: const []),
        ]).facts;
        expect(
          (sourceFacts.returnedBy(root).constant as ScalarConstant).value,
          73,
        );
        final owner = CallableImplementations();
        final lowered = CallableLowering(owner).run(sourceFacts);
        final solved = ProgramFlow(lowered, [
          (target: root, arguments: const []),
        ]).facts;
        final bound =
            (lowered.implementationOf(root) as IrFunction).entry.end as Invoke;
        expect(solved.exitsOf(bound.operation), (
          normal: false,
          exceptional: true,
        ));
        expect(
          solved.returnedBy(owner.functions.single.target).isBottom,
          isTrue,
        );
        expect(
          IrInterpreter(
            lowered,
            {},
          ).run(lowered.implementationOf(root) as IrFunction, []),
          73,
        );
        // This also retains all seven optimization passes and checks selected calls.
        check(original, root, 73);
      },
    );
  }
  test('a generic result instantiated as Never has no normal adapter exit', () {
    final state = GlobalVariable(
      uri,
      'genericNeverState',
      .integer,
      isLate: true,
    );
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final source = FunctionTarget(
      uri,
      'genericNever',
      t,
      [],
      typeParameters: [t],
    );
    final sourceBlock = Block();
    sourceBlock.emit(StoreGlobal(state, const Constant.integer(73)));
    sourceBlock.finish(
      Return(sourceBlock.emit(TypeCast(const Constant.integer(1), t))),
    );
    final root = FunctionTarget(uri, 'genericNeverRoot', .integer, []);
    final start = Block(), caught = Block();
    final call = FunctionCall(
      FunctionConstant(source),
      const [],
      const {},
      const [ValueType.never],
    );
    start.finish(Invoke(call, onReturn: null, onThrow: Jump(caught)));
    caught.finish(Return(caught.emit(LoadGlobal(state))));
    final body = IrFunction(root, [start, caught]);
    final original = IrProgram(
      [
        for (final type in TypeMetadata.fields.entries)
          IrClass(type.key, type.value),
      ],
      [
        body,
        IrFunction(source, [sourceBlock]),
      ],
      globals: [state],
    );
    expect(IrInterpreter(original, {}).run(body, []), 73);
    check(original, root, 73, select: false);
  });
}
