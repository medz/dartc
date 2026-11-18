import 'package:dartc/ir.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);

  int execute(
    FunctionType generic,
    List<ValueType> arguments,
    FunctionType expected, {
    List<IrClass> classes = const [],
  }) {
    final source = heapRuntime.program;
    final owner = TypeImplementations(
      runtime: heapRuntime.types,
      declarations: [
        ...source.classes.map((c) => c.type),
        ...classes.map((c) => c.type),
      ],
    );
    final values = owner.values;
    final state = GlobalVariable(
      Uri.parse('memory:function-instantiation'),
      'state',
      .integer,
      isLate: true,
    );
    final root = FunctionTarget(null, 'instantiate', .integer, []);
    final entry = Block(),
        success = Block([TypeMetadata.type]),
        failed = Block();
    entry.emit(StoreGlobal(state, const Constant.integer(7)));
    final instantiate = DirectCall(values.entry(.typeInstantiate), [
      values.constant(generic),
      values.argumentConstants(arguments),
    ]);
    entry.finish(
      Invoke(
        instantiate,
        onReturn: Jump(success, [instantiate]),
        onThrow: Jump(failed),
      ),
    );
    final same = success.emit(
      DirectCall(values.equality, [
        success.parameters.single,
        values.constant(expected),
      ]),
    );
    final yes = Block()..finish(const Return(Constant.integer(42)));
    final no = Block()..finish(const Return(Constant.integer(-1)));
    success.finish(Branch(same, Jump(yes), Jump(no)));
    failed.finish(Return(failed.emit(LoadGlobal(state))));
    final body = IrFunction(root, [entry, success, failed, yes, no]);
    final layout = ProgramLayout(
      [...source.classes, ...classes],
      nativeLayout: NativeLayout(Target.host()),
      typeImplementations: owner,
    );
    final program = IrProgram(
      [...source.classes, ...classes],
      [...source.functions, ...owner.functions, body],
      globals: [...source.globals, state],
      externals: source.externals,
    );
    return IrInterpreter(program, {}, typeLayout: layout).run(body, []) as int;
  }

  test(
    'actual runtime descriptor validates num bounds and retains prior writes',
    () {
      final t = TypeParameterType('T')..initializeBound(.number);
      final generic = FunctionType(t, [t], typeParameters: [t]);
      expect(
        execute(generic, [.integer], FunctionType(.integer, [.integer])),
        42,
      );
      expect(
        execute(generic, [.string], FunctionType(.integer, [.integer])),
        7,
      );
      expect(execute(generic, [], FunctionType(.integer, [.integer])), 7);
      expect(
        execute(generic, [
          .integer,
          .integer,
        ], FunctionType(.integer, [.integer])),
        7,
      );
    },
  );

  test(
    'actual runtime substitutes mutually referring F-bounds simultaneously',
    () {
      final element = TypeParameterType('E')..initializeBound(.object.nullable);
      final comparable = ClassType(
        null,
        'Comparable',
        typeParameters: [element],
      );
      final good = ClassType.declare(null, 'Good');
      good.initializeHierarchy(
        interfaces: [
          comparable.instantiate([good]),
        ],
      );
      final wrong = ClassType(
        null,
        'Wrong',
        interfaces: [
          comparable.instantiate([good]),
        ],
      );
      final t = TypeParameterType('T'), u = TypeParameterType('U');
      t.initializeBound(comparable.instantiate([u]));
      u.initializeBound(comparable.instantiate([t]));
      final generic = FunctionType(t, [], typeParameters: [t, u]);
      final declarations = [
        IrClass(comparable, []),
        IrClass(good, []),
        IrClass(wrong, []),
      ];
      expect(
        execute(
          generic,
          [good, good],
          FunctionType(good, []),
          classes: declarations,
        ),
        42,
      );
      expect(
        execute(
          generic,
          [good, wrong],
          FunctionType(good, []),
          classes: declarations,
        ),
        7,
      );
    },
  );

  test(
    'runtime substitution retains nested binders while replacing captured T',
    () {
      final t = TypeParameterType('T')..initializeBound(.number);
      final u = TypeParameterType('U')..initializeBound(t);
      final nested = FunctionType(t, [u], typeParameters: [u]);
      final generic = FunctionType(nested, [], typeParameters: [t]);
      final v = TypeParameterType('V')..initializeBound(.integer);
      final expected = FunctionType(
        FunctionType(.integer, [v], typeParameters: [v]),
        [],
      );
      expect(execute(generic, [.integer], expected), 42);
    },
  );
  test('explicit instantiation producer executes the actual runtime and shared fields', () {
    final source = heapRuntime.program;
    final types = TypeImplementations(
      runtime: heapRuntime.types,
      declarations: source.classes.map((c) => c.type),
    );
    final t = TypeParameterType('T')..initializeBound(.number);
    final target = FunctionTarget(
      null,
      'identity',
      t,
      [t],
      typeParameters: [t],
    );
    final sourceEntry = Block(target.parameterTypes);
    sourceEntry.finish(Return(sourceEntry.parameters.single));
    final root = FunctionTarget(null, 'applied', .integer, []);
    final entry = Block();
    final operation = InstantiateFunction(FunctionConstant(target), [.integer]);
    final owner = CallableImplementations(types: types);
    owner.extend(
      IrProgram(
        source.classes,
        [
          ...source.functions,
          IrFunction(target, [sourceEntry]),
        ],
        globals: source.globals,
        externals: source.externals,
      ),
    );
    final call = entry.emit(owner.instantiateFunction(operation));
    entry.finish(
      Return(entry.emit(FunctionCall(call, [const Constant.integer(42)]))),
    );
    final rootBody = IrFunction(root, [entry]);
    final classes = [...source.classes, ...owner.storage.classes];
    final program = IrProgram(
      classes,
      [
        ...source.functions,
        IrFunction(target, [sourceEntry]),
        ...types.functions,
        ...owner.constructionFunctions,
        ...owner.storage.functions,
        rootBody,
      ],
      globals: source.globals,
      externals: source.externals,
    );
    final layout = ProgramLayout(
      classes,
      nativeLayout: NativeLayout(Target.host()),
      typeImplementations: types,
    );
    expect(
      IrInterpreter(program, {}, typeLayout: layout).run(rootBody, []),
      42,
    );
    expect(owner.instantiateFunction(operation).target, call.target);
  });

  test('instance-driven instantiation uses the actual nominal argument', () {
    final source = heapRuntime.program;
    final e = TypeParameterType('E')..initializeBound(.number);
    final box = ClassType(null, 'Box', typeParameters: [e]);
    final initializer = FunctionTarget(
      null,
      'new',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    final init = Block(initializer.parameterTypes)..finish(const Return());
    final declaration = IrClass(box, [], constructors: [initializer]);
    final types = TypeImplementations(
      runtime: heapRuntime.types,
      declarations: [...source.classes.map((c) => c.type), box],
    );
    final t = TypeParameterType('T')..initializeBound(.number);
    final target = FunctionTarget(
      null,
      'actualArgument',
      .typeType,
      [],
      typeParameters: [t],
    );
    final sourceEntry = Block(target.parameterTypes);
    sourceEntry.finish(Return(sourceEntry.emit(ReifyType(t))));
    final root = FunctionTarget(null, 'fromInstance', .boolean, []);
    final entry = Block();
    final object = entry.emit(
      Construct(initializer, [], instantiatedType: box.instantiate([.integer])),
    );
    final view = entry.emit(TypeView(object, box.instantiate([.number])));
    final operation = InstantiateFunctionFrom(
      FunctionConstant(target),
      view,
      box,
    );
    final owner = CallableImplementations(types: types);
    owner.extend(
      IrProgram(
        [...source.classes, declaration],
        [
          ...source.functions,
          IrFunction(target, [sourceEntry]),
          IrFunction(initializer, [init]),
        ],
        globals: source.globals,
        externals: source.externals,
      ),
    );
    final applied = entry.emit(owner.instantiateFunctionFrom(operation));
    final callable = entry.emit(TypeCast(applied, FunctionType(.typeType, [])));
    final actual = entry.emit(FunctionCall(callable, []));
    entry.finish(Return(entry.emit(Equals(actual, TypeConstant(.integer)))));
    final rootBody = IrFunction(root, [entry]);
    final classes = [...source.classes, declaration, ...owner.storage.classes];
    final program = IrProgram(
      classes,
      [
        ...source.functions,
        IrFunction(target, [sourceEntry]),
        IrFunction(initializer, [init]),
        ...types.functions,
        ...owner.constructionFunctions,
        ...owner.storage.functions,
        rootBody,
      ],
      globals: source.globals,
      externals: source.externals,
    );
    final layout = ProgramLayout(
      classes,
      nativeLayout: NativeLayout(Target.host()),
      typeImplementations: types,
    );
    expect(
      IrInterpreter(program, {}, typeLayout: layout).run(rootBody, []),
      isTrue,
    );
  });

  test('method producer retains receiver writes and equality through actual fields', () {
    final source = heapRuntime.program;
    final counter = ClassType(null, 'Counter');
    final value = InstanceField(counter, 'value', .integer);
    final initializer = FunctionTarget(
      null,
      'new',
      .voidType,
      [],
      owner: counter,
      kind: .initializer,
    );
    final init = Block(initializer.parameterTypes);
    init.emit(
      StoreField(value, init.parameters.single, const Constant.integer(1)),
    );
    init.finish(const Return());
    final method = FunctionTarget(
      null,
      'bump',
      .integer,
      [],
      owner: counter,
      kind: .method,
    );
    final body = Block(method.parameterTypes);
    body.emit(
      StoreField(value, body.parameters.single, const Constant.integer(9)),
    );
    body.finish(Return(body.emit(LoadField(value, body.parameters.single))));
    final declaration = IrClass(
      counter,
      [value],
      constructors: [initializer],
      members: [method],
    );
    final types = TypeImplementations(
      runtime: heapRuntime.types,
      declarations: [...source.classes.map((c) => c.type), counter],
    );
    final owner = CallableImplementations(types: types);
    owner.extend(
      IrProgram(
        [...source.classes, declaration],
        [
          ...source.functions,
          IrFunction(method, [body]),
          IrFunction(initializer, [init]),
        ],
        globals: source.globals,
        externals: source.externals,
      ),
    );
    final root = FunctionTarget(null, 'bindReceiver', .integer, []);
    final entry = Block();
    final object = entry.emit(Construct(initializer, []));
    final first = entry.emit(
      owner.bindMethod(BindMethod(method, object), {counter: method}),
    );
    final second = entry.emit(
      owner.bindMethod(BindMethod(method, object), {counter: method}),
    );
    final same = entry.emit(Equals(first, second));
    final yes = Block(),
        no = Block()..finish(const Return(Constant.integer(-1)));
    entry.finish(Branch(same, Jump(yes), Jump(no)));
    yes.emit(FunctionCall(first, []));
    yes.finish(Return(yes.emit(LoadField(value, object))));
    final rootBody = IrFunction(root, [entry, yes, no]);
    final classes = [...source.classes, declaration, ...owner.storage.classes];
    final program = IrProgram(
      classes,
      [
        ...source.functions,
        IrFunction(method, [body]),
        IrFunction(initializer, [init]),
        ...types.functions,
        ...owner.constructionFunctions,
        ...owner.storage.functions,
        rootBody,
      ],
      globals: source.globals,
      externals: source.externals,
    );
    final layout = ProgramLayout(
      classes,
      nativeLayout: NativeLayout(Target.host()),
      typeImplementations: types,
    );
    expect(IrInterpreter(program, {}, typeLayout: layout).run(rootBody, []), 9);
  });

  for (final mode in ['default', 'bound', 'invalid']) {
    test('dynamic generic $mode uses checked actual descriptors', () {
      final runtime = heapRuntime.program;
      final types = TypeImplementations(
        runtime: heapRuntime.types,
        declarations: runtime.classes.map((c) => c.type),
      );
      final t = TypeParameterType('T')
        ..initializeBound(.number)
        ..initializeDefaultType(.number);
      final target = FunctionTarget(
        null,
        'generic',
        .typeType,
        [],
        typeParameters: [t],
      );
      final state = GlobalVariable(
        Uri.parse('memory:dynamic-calls'),
        'state',
        .integer,
        isLate: true,
      );
      final source = Block(target.parameterTypes);
      source.emit(StoreGlobal(state, const Constant.integer(99)));
      source.finish(Return(source.emit(ReifyType(t))));
      final failureType = TypeParameterType('FailureT')
        ..initializeBound(.object.nullable);
      final failure = FunctionTarget(null, 'missing', .dynamicType, [
        .dynamicType,
      ], typeParameters: mode == 'invalid' ? [failureType] : const []);
      final failing = Block(failure.parameterTypes)
        ..finish(Throw(const Constant.integer(-1)));
      final root = FunctionTarget(null, 'root', .boolean, []);
      final entry = Block(),
          result = Block([ValueType.dynamicType]),
          caught = Block();
      entry.emit(StoreGlobal(state, const Constant.integer(7)));
      final function = mode == 'bound'
          ? FunctionConstant(target, typeArguments: [.integer])
          : FunctionConstant(target);
      final original = DynamicDispatch(
        function,
        (kind: FunctionKind.method, name: 'call', privateScope: null),
        const [],
        const {},
        mode == 'invalid' ? [.string] : const [],
        failure,
      );
      final owner = CallableImplementations(types: types)
        ..extend(
          IrProgram(
            runtime.classes,
            [
              ...runtime.functions,
              IrFunction(target, [source]),
              IrFunction(failure, [failing]),
            ],
            globals: [...runtime.globals, state],
            externals: runtime.externals,
          ),
        );
      final binding = owner.bindDynamic(original, [target]);
      final call = DynamicDispatch(
        function,
        original.selector,
        const [],
        const {},
        original.typeArguments,
        failure,
        const {},
        binding,
      );
      entry.finish(
        Invoke(call, onReturn: Jump(result, [call]), onThrow: Jump(caught)),
      );
      result.finish(
        Return(
          result.emit(
            Equals(
              result.parameters.single,
              TypeConstant(
                mode == 'bound' ? ValueType.integer : ValueType.number,
              ),
            ),
          ),
        ),
      );
      caught.finish(
        Return(
          mode == 'invalid'
              ? caught.emit(
                  Equals(
                    caught.emit(LoadGlobal(state)),
                    const Constant.integer(7),
                  ),
                )
              : const Constant.boolean(false),
        ),
      );
      final body = IrFunction(root, [entry, result, caught]);
      final classes = [...runtime.classes, ...owner.storage.classes];
      final program = IrProgram(
        classes,
        [
          ...runtime.functions,
          IrFunction(target, [source]),
          IrFunction(failure, [failing]),
          ...owner.functions,
          ...types.functions,
          body,
        ],
        globals: [...runtime.globals, state],
        externals: runtime.externals,
      );
      final layout = ProgramLayout(
        classes,
        nativeLayout: NativeLayout(Target.host()),
        typeImplementations: types,
      );
      expect(
        IrInterpreter(program, {}, typeLayout: layout).run(body, []),
        isTrue,
      );
    });
  }

  test('generic descriptor retains the canonical applied calling shape', () {
    final t = TypeParameterType('T')
      ..initializeBound(.number)
      ..initializeDefaultType(.number);
    final generic = FunctionType(
      t,
      [t, t],
      namedParameters: {'other': false},
      typeParameters: [t],
    );
    final values = TypeValues();
    final before = values.constant(generic);
    final signature = before.fields[TypeMetadata.signature] as ObjectConstant;
    final applied = values.constant(generic.instantiate([.integer]));
    expect(
      signature.fields[TypeMetadata.appliedShape]!.structuralKey,
      applied.fields[TypeMetadata.shape]!.structuralKey,
    );
    expect(
      signature.fields[TypeMetadata.appliedSignature]!.structuralKey,
      applied.fields[TypeMetadata.signature]!.structuralKey,
    );
    final appliedInfo =
        signature.fields[TypeMetadata.appliedSignature] as ObjectConstant;
    final named = appliedInfo.fields[TypeMetadata.named] as ObjectConstant;
    expect((named.fields[TypeMetadata.nameSlot] as ScalarConstant).value, 2);
    values.id(ClassType(null, 'Later'));
    expect(values.constant(generic).structuralKey, before.structuralKey);
  });
}
