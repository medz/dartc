import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  test('a retained type value stores its projector without opening a call', () {
    final target = FunctionTarget(null, 'typeValue', .typeType, []);
    final entry = Block()..finish(Return(TypeConstant(.integer)));
    const platform = Target(.linux, .arm64);
    final prepared = Compiler(platform).prepare(
      IrProgram([], [
        IrFunction(target, [entry]),
      ]),
      roots: [target],
      runtime: heapRuntime,
    );
    expect(prepared.definitions, {target});
    expect(
      Arm64CodeGenerator(platform).generate(prepared).sections,
      isNotEmpty,
    );
  });

  test(
    'default preparation preserves statically safe values without a runtime',
    () {
      final target = FunctionTarget(null, 'convert', .voidType, [
        .object.nullable,
      ]);
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(entry.emit(TypeCast(entry.parameters.single, .voidType))),
      );
      final prepared = Compiler(const Target(.linux, .arm64)).prepare(
        IrProgram([], [
          IrFunction(target, [entry]),
        ]),
        roots: [target],
      );
      final body = prepared.program.implementationOf(target) as IrFunction;
      expect(IrInterpreter(prepared.program, {}).run(body, [42]), 42);
      expect(body.callees, isEmpty);
    },
  );

  test(
    'ordinary subtype implementations preserve both outcomes and refinements',
    () {
      final target = FunctionTarget(null, 'test', .integer, [.object.nullable]);
      final entry = Block(target.parameterTypes),
          yes = Block([.number]),
          no = Block();
      final predicate = entry.emit(TypeTest(entry.parameters.single, .number));
      entry.finish(
        Branch(predicate, Jump(yes, [predicate.refinement(true)!]), Jump(no)),
      );
      yes.finish(const Return(Constant.integer(42)));
      no.finish(const Return(Constant.integer(43)));
      final source = IrFunction(target, [entry, yes, no]);
      final (program, layout) = lower([source], target);
      final body = program.implementationOf(target) as IrFunction;
      expect(
        body.blocks.expand((block) => block.instructions).whereType<TypeTest>(),
        isEmpty,
      );
      expect(body.callees, contains(heapRuntime.types!.entry(.typeSubtype)));
      final interpreter = IrInterpreter(program, {}, typeLayout: layout);
      for (final input in [42, 2.5, 'value', null]) {
        expect(interpreter.run(body, [input]), input is num ? 42 : 43);
      }
    },
  );

  test(
    'checked void conversion preserves its dynamically observable value',
    () {
      final target = FunctionTarget(null, 'convert', .voidType, [
        .object.nullable,
      ]);
      final entry = Block(target.parameterTypes);
      entry.finish(
        Return(entry.emit(TypeCast(entry.parameters.single, .voidType))),
      );
      final (program, layout) = lower([
        IrFunction(target, [entry]),
      ], target);
      final interpreter = IrInterpreter(program, {}, typeLayout: layout);
      final body = program.implementationOf(target) as IrFunction;
      for (final input in [42, 'value', null]) {
        expect(interpreter.run(body, [input]), input);
      }
    },
  );

  test(
    'actual bound validation preserves earlier writes and the failure edge',
    () {
      final state = GlobalVariable(
        Uri.parse('memory:bound-lowering'),
        'state',
        .integer,
        isLate: true,
      );
      final t = TypeParameterType('T')..initializeBound(.number);
      final target = FunctionTarget(null, 'checked', .integer, [
        TypeMetadata.type,
      ]);
      final entry = Block(target.parameterTypes),
          normal = Block(),
          failed = Block();
      entry.emit(StoreGlobal(state, const Constant.integer(7)));
      final check = CheckedTypeArgument(t, entry.parameters.single, {
        t: entry.parameters.single,
      });
      entry.finish(
        Invoke(check, onReturn: Jump(normal), onThrow: Jump(failed)),
      );
      normal.emit(ReifyType(t));
      normal.finish(const Return(Constant.integer(42)));
      failed.finish(Return(failed.emit(LoadGlobal(state))));
      final source = IrFunction(
        target,
        [entry, normal, failed],
        typeBindings: [TypeBinding.checked(check)],
      );
      final (program, layout) = lower([source], target, globals: [state]);
      final body = program.implementationOf(target) as IrFunction;
      final lowered = body.typeBindings.single.check;
      expect(lowered.implementation, isNotNull);
      expect(body.entry.end, isA<Invoke>());
      final helper =
          program.implementationOf(lowered.implementation!) as IrFunction;
      expect(
        helper.callees,
        containsAll([
          heapRuntime.types!.entry(.typeSubtype),
          heapRuntime.typeCheckFailure,
        ]),
      );
      final interpreter = IrInterpreter(program, {}, typeLayout: layout);
      for (final (actual, expected) in [
        (ValueType.integer, 42),
        (ValueType.string, 7),
      ]) {
        final root = FunctionTarget(null, 'root', .integer, []);
        final block = Block();
        block.finish(
          Return(
            block.emit(
              DirectCall(target, [
                block.emit(
                  UncheckedCast(TypeConstant(actual), TypeMetadata.type),
                ),
              ]),
            ),
          ),
        );
        final invocation = IrFunction(root, [block]);
        expect(interpreter.run(invocation, []), expected);
      }
    },
  );

  test(
    'lowered F-bound uses the simultaneous actual descriptor environment',
    () {
      final element = TypeParameterType('E')..initializeBound(.object.nullable);
      final comparable = ClassType(
        null,
        'Comparable',
        typeParameters: [element],
        isAbstract: true,
      );
      final good = ClassType.declare(null, 'Good');
      good.initializeHierarchy(
        interfaces: [
          comparable.instantiate([good]),
        ],
      );
      final bad = ClassType.declare(null, 'Bad');
      bad.initializeHierarchy(
        interfaces: [
          comparable.instantiate([good]),
        ],
      );
      final t = TypeParameterType('T');
      t.initializeBound(comparable.instantiate([t]));
      final target = FunctionTarget(null, 'fBound', .typeType, [
        TypeMetadata.type,
      ]);
      final entry = Block(target.parameterTypes);
      final check = entry.emit(
        CheckedTypeArgument(t, entry.parameters.single, {
          t: entry.parameters.single,
        }),
      );
      entry.finish(Return(entry.emit(ReifyType(t))));
      final source = IrFunction(
        target,
        [entry],
        typeBindings: [TypeBinding.checked(check)],
      );
      final (program, layout) = lower(
        [source],
        target,
        classes: [IrClass(comparable, []), IrClass(good, []), IrClass(bad, [])],
      );
      final interpreter = IrInterpreter(program, {}, typeLayout: layout);
      for (final actual in [good, bad]) {
        final root = FunctionTarget(null, 'root', .boolean, []);
        final block = Block(),
            normal = Block([ValueType.typeType]),
            failed = Block();
        final call = DirectCall(target, [
          block.emit(UncheckedCast(TypeConstant(actual), TypeMetadata.type)),
        ]);
        block.finish(
          Invoke(call, onReturn: Jump(normal, [call]), onThrow: Jump(failed)),
        );
        normal.finish(
          Return(
            normal.emit(Equals(normal.parameters.single, TypeConstant(actual))),
          ),
        );
        failed.finish(const Return(Constant.boolean(false)));
        final invocation = IrFunction(root, [block, normal, failed]);
        expect(interpreter.run(invocation, []), actual == good);
      }
    },
  );

  test('receiver type arguments use actual projection calls', () {
    final parameter = TypeParameterType('T')..initializeBound(.object.nullable);
    final box = ClassType(null, 'Box', typeParameters: [parameter]);
    final method = FunctionTarget(
      null,
      'argument',
      .typeType,
      [],
      owner: box,
      kind: .method,
    );
    final body = Block(method.parameterTypes);
    body.finish(Return(body.emit(ReifyType(parameter))));
    final root = FunctionTarget(null, 'root', .boolean, []);
    final entry = Block();
    final type = box.instantiate([ValueType.integer]);
    final called = entry.emit(
      DirectCall(method, [ObjectConstant(type, {})], ownerType: type),
    );
    entry.finish(Return(entry.emit(Equals(called, TypeConstant(.integer)))));
    final (program, layout) = lower(
      [
        IrFunction(method, [body]),
        IrFunction(root, [entry]),
      ],
      root,
      classes: [
        IrClass(box, [], members: [method]),
      ],
    );
    final lowered = program.implementationOf(method) as IrFunction;
    expect(lowered.callees, isNotEmpty);
    expect(
      lowered.blocks
          .expand((block) => block.instructions)
          .whereType<ReifyType>(),
      isEmpty,
    );
    expect(
      IrInterpreter(
        program,
        {},
        typeLayout: layout,
      ).run(program.implementationOf(root) as IrFunction, []),
      isTrue,
    );
  });

  test('descriptor equality retains its real operands and both results', () {
    final target = FunctionTarget(null, 'equals', .boolean, [.object.nullable]);
    final body = Block(target.parameterTypes);
    body.finish(
      Return(body.emit(Equals(TypeConstant(.integer), body.parameters.single))),
    );
    final root = FunctionTarget(null, 'root', .boolean, []);
    final entry = Block();
    entry.finish(
      Return(entry.emit(DirectCall(target, [TypeConstant(.integer)]))),
    );
    final (program, layout) = lower([
      IrFunction(target, [body]),
      IrFunction(root, [entry]),
    ], root);
    final lowered = program.implementationOf(target) as IrFunction;
    expect(lowered.callees, contains(heapRuntime.types!.entry(.typeEquals)));
    expect(
      IrInterpreter(
        program,
        {},
        typeLayout: layout,
      ).run(program.implementationOf(root) as IrFunction, []),
      isTrue,
    );
    final interpreter = IrInterpreter(program, {}, typeLayout: layout);
    for (final input in [42, 'int', null]) {
      expect(interpreter.run(lowered, [input]), isFalse);
    }
  });
}

(IrProgram, ProgramLayout) lower(
  List<IrFunction> bodies,
  FunctionTarget root, {
  List<IrClass> classes = const [],
  List<GlobalVariable> globals = const [],
}) {
  final runtime = heapRuntime;
  final owner = TypeImplementations(runtime: runtime.types);
  final transform = TypeLowering(
    owner,
    failure: runtime.typeCheckFailure,
  ).bind();
  final program = transform.normalize(
    IrProgram(
      [...runtime.program.classes, ...classes],
      [...runtime.program.functions, ...bodies],
      globals: [...runtime.program.globals, ...globals],
      externals: runtime.program.externals,
    ),
  );
  final layout = ProgramLayout(
    program.classes,
    functions: program.functions,
    nativeLayout: NativeLayout(const Target(.linux, .arm64)),
    typeImplementations: owner,
  );
  final facts = ProgramFlow(
    program,
    [],
    openEntries: [root],
    memoryLayout: layout,
  ).facts;
  return (transform(facts), layout);
}
