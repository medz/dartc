import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const target = Target(.linux, .arm64);
  final uri = Uri.parse('memory:preparation');
  final entry = FunctionTarget(uri, 'entry', .integer, []);
  final other = FunctionTarget(uri, 'other', .integer, []);
  final extra = ClassType(uri, 'Extra');
  final program = IrProgram(
    [IrClass(extra, [])],
    [
      for (final function in [entry, other])
        IrFunction(function, [
          Block()..finish(const Return(Constant.integer(7))),
        ]),
    ],
  );

  test('preparation rejects foreign graphs and facts missing entry roots', () {
    final preparation = _preparation(target, program, roots: [entry]);
    final foreign = IrProgram(program.classes, program.functions);
    expect(
      () => preparation.prepare(CallTypeFlow(foreign, [entry]).facts),
      throwsArgumentError,
    );
    expect(
      () => preparation.prepare(CallTypeFlow(program, [other]).facts),
      throwsArgumentError,
    );
  });

  test('same-size fact changes invalidate preparation and emission', () {
    final preparation = _preparation(target, program, roots: [entry]);
    final flow = CallTypeFlow(
      preparation.program,
      preparation.roots,
      instantiatedTypes: preparation.instantiatedTypes,
    );
    final facts = flow.facts;
    final definitions = facts.definitions;
    final prepared = preparation.prepare(facts);
    expect(flow.extend(instantiatedTypes: [extra]), isTrue);
    expect(flow.facts.definitions, definitions);
    expect(() => preparation.prepare(facts), throwsStateError);
    expect(
      () => Arm64CodeGenerator(target).generate(prepared),
      throwsStateError,
    );
    final current = preparation.prepare(flow.facts);
    expect(current.definitions, {entry});
    expect(
      Arm64CodeGenerator(target).generate(current).symbols.single.name,
      'entry',
    );
  });

  test('prepared bindings and definitions cannot be changed by callers', () {
    final exports = {
      entry: NativeExport('visible', NativeSignature(Int64, [])),
    };
    final prepared = Compiler(target).prepare(program, exports: exports);
    exports.clear();
    expect(() => prepared.definitions.clear(), throwsUnsupportedError);
    final generator = Arm64CodeGenerator(target);
    final first = generator.generate(prepared),
        second = generator.generate(prepared);
    expect(first.symbols.single.name, 'visible');
    expect(second.sections.single.bytes, first.sections.single.bytes);
    expect(
      () => X64CodeGenerator(const .new(.linux, .x64)).generate(prepared),
      throwsArgumentError,
    );
    expect(
      () => Arm64CodeGenerator(const .new(.macos, .arm64)).generate(prepared),
      throwsArgumentError,
    );
  });

  test('caught call failures do not require a heap lifecycle', () {
    final raise = FunctionTarget(uri, 'raise', .never, []);
    final raised = Block()
      ..finish(Throw.recorded(const Constant.integer(7), null));
    final forward = FunctionTarget(uri, 'forward', .never, []);
    final forwarded = Block();
    forwarded.finish(Unreachable(forwarded.emit(DirectCall(raise, []))));
    final recover = FunctionTarget(uri, 'recover', .integer, []);
    final called = Block(), caught = Block();
    called.finish(
      Invoke(DirectCall(forward, []), onReturn: null, onThrow: Jump(caught)),
    );
    caught.finish(const Return(Constant.integer(42)));
    final program = IrProgram([], [
      IrFunction(raise, [raised]),
      IrFunction(forward, [forwarded]),
      IrFunction(recover, [called, caught]),
    ]);
    final exported = FunctionTarget(uri, 'raises', .integer, []);
    final exportedBody = Block()
      ..finish(Throw.recorded(const Constant.integer(7), null));
    expect(
      () => Compiler(target).prepare(
        IrProgram([], [
          ...program.functions,
          IrFunction(exported, [exportedBody]),
        ]),
        exports: {exported: NativeExport('raises', NativeSignature(Int64, []))},
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('entry lifecycle'),
        ),
      ),
    );
    final preparation = _preparation(target, program, roots: [recover]);
    final flow = CallTypeFlow(
      preparation.program,
      preparation.roots,
      instantiatedTypes: preparation.instantiatedTypes,
    );
    final prepared = preparation.prepare(flow.facts);
    expect(prepared.definitions, {raise, forward, recover});
    expect(Arm64CodeGenerator(target).generate(prepared).imports, isEmpty);

    final escaping = _preparation(target, program, roots: [forward]);
    expect(
      () => escaping.prepare(
        CallTypeFlow(
          escaping.program,
          escaping.roots,
          instantiatedTypes: escaping.instantiatedTypes,
        ).facts,
      ),
      throwsArgumentError,
    );
  });

  test(
    'native exports enter through their ABI bridge without adding source roots',
    () {
      final pointer = FfiTypes.int64Pointer;
      final identity = FunctionTarget(uri, 'identity', pointer, [pointer]);
      final body = Block(identity.parameterTypes);
      body.finish(Return(body.parameters.single));
      final program = IrProgram([], [
        IrFunction(identity, [body]),
      ]);
      final exports = {
        identity: NativeExport(
          'identity',
          NativeSignature(Pointer<Int64>, [Pointer<Int64>]),
        ),
      };
      final preparation = _preparation(target, program, exports: exports);
      final entry = preparation.roots.single;
      expect(entry.parameterTypes, [ValueType.integer]);
      expect(entry.returnType, ValueType.integer);
      final facts = ProgramFlow(
        preparation.program,
        const [],
        openEntries: preparation.roots,
      ).facts;
      expect(facts.openEntries, isNot(contains(identity)));
      expect(facts.definitions, contains(identity));
      final explicit = _preparation(
        target,
        program,
        roots: [identity],
        exports: exports,
      );
      expect(explicit.roots, contains(identity));
      final module = Arm64CodeGenerator(target)
          .generate(Compiler(target).prepare(program, exports: exports));
      expect(
        module.symbols.where((symbol) => symbol.exported).single.name,
        'identity',
      );
    },
  );

  test('ABI conversions simplify with the actual native entry arguments', () {
    final pointer = FfiTypes.int64Pointer;
    final identity = FunctionTarget(uri, 'pointerIdentity', pointer, [pointer]);
    final body = Block(identity.parameterTypes);
    body.finish(Return(body.parameters.single));
    final boundaries = NativeBoundaries(
      IrProgram([], [
        IrFunction(identity, [body]),
      ]),
      exports: {
        identity: NativeExport(
          'pointer_identity',
          NativeSignature(Pointer<Int64>, [Pointer<Int64>]),
        ),
      },
    );
    final facts = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      DirectCallInlining(),
    ]).run(boundaries.program, const [], openEntries: boundaries.roots);
    final entry = boundaries.roots.single;
    final rewritten = facts.program.implementationOf(entry) as IrFunction;
    expect(facts.definitions, {entry});
    expect(rewritten.blocks.single.instructions, isEmpty);
    for (final address in [0, 8, 0x12345678]) {
      expect(
        IrInterpreter(facts.program, {}).run(rewritten, [address]),
        address,
      );
    }
    final preparation = ProgramPreparation(
      target,
      facts.program,
      boundaries: boundaries,
    );
    final prepared = preparation.prepare(
      CallTypeFlow(
        preparation.program,
        preparation.roots,
        instantiatedTypes: preparation.instantiatedTypes,
      ).facts,
    );
    expect(Arm64CodeGenerator(target).generate(prepared).imports, isEmpty);
  });

  test(
    'native Void discards a Dart result without changing ordinary Dart calls',
    () {
      final function = FunctionTarget(uri, 'forwardVoid', .voidType, [
        .integer,
      ]);
      final block = Block(function.parameterTypes)
        ..finish(const Return(Constant.integer(42)));
      final source = IrFunction(function, [block]);
      final boundaries = NativeBoundaries(
        IrProgram([], [source]),
        exports: {
          function: NativeExport('forwardVoid', NativeSignature(Void, [Int64])),
        },
      );
      final facts = ProgramOptimizer(const [
        ProgramSimplification(),
        DirectCallInlining(),
      ]).run(boundaries.program, [], openEntries: boundaries.roots);
      final bridge =
          facts.program.implementationOf(boundaries.roots.single) as IrFunction;
      final runner = IrInterpreter(facts.program, {});
      expect(runner.run(source, [7]), 42);
      expect(runner.run(bridge, [7]), isNull);
    },
  );

  test('escaped callbacks analyze ABI entry values before Dart calls', () {
    final pointer = FfiTypes.int64Pointer;
    final identity = FunctionTarget(uri, 'callback', pointer, [pointer]);
    final callbackBody = Block(identity.parameterTypes);
    callbackBody.finish(Return(callbackBody.parameters.single));
    final declaration = StaticCallbackTarget(
      identity,
      FunctionType(pointer, [pointer]),
    );
    final factory = FunctionTarget(uri, 'callbackAddress', .integer, []);
    final factoryBody = Block();
    factoryBody.finish(
      Return(factoryBody.emit(NativeCallbackAddress(declaration))),
    );
    final boundaries = NativeBoundaries(
      IrProgram([], [
        IrFunction(identity, [callbackBody]),
        IrFunction(factory, [factoryBody]),
      ]),
      roots: [factory],
    );
    final native = boundaries.callbacks[declaration]!.target;
    final entries = {declaration: native};
    final closed = ProgramFlow(boundaries.program, [
      (target: factory, arguments: <FlowValue>[]),
    ], nativeEntries: entries).facts;
    expect(closed.definitions, {factory});
    final escaped =
        ProgramOptimizer(const [ProgramSimplification(), DirectCallInlining()])
            .run(
              boundaries.program,
              const [],
              openEntries: [factory],
              nativeEntries: entries,
            );
    expect(escaped.definitions, {factory, native});
    final rewritten = escaped.program.implementationOf(native) as IrFunction;
    expect(rewritten.entry.instructions, isEmpty);
    for (final address in [0, 8, 0x12345678]) {
      expect(
        IrInterpreter(escaped.program, {}).run(rewritten, [address]),
        address,
      );
    }
    expect(
      () => ProgramFlow(
        boundaries.program,
        const [],
        nativeEntries: {
          declaration: FunctionTarget(null, 'missing', .integer, [.integer]),
        },
      ),
      throwsArgumentError,
    );
  });

  test('native addresses must be bound before emission', () {
    final reference = NativeReference(
      'fixture',
      'storage',
      NativeTypeRef.of(Int64),
    );
    final block = Block();
    block.finish(Return(block.emit(NativeSymbolAddress(reference))));
    final input = IrProgram([], [
      IrFunction(entry, [block]),
    ]);
    expect(
      () => Compiler(target).prepare(input, roots: [entry]),
      throwsArgumentError,
    );
    final symbols = {reference: 'native_storage'};
    final prepared = Compiler(target)
        .prepare(input, roots: [entry], nativeSymbols: symbols);
    symbols.clear();
    expect(Arm64CodeGenerator(target).generate(prepared).imports, [
      'native_storage',
    ]);
  });

  test('unused pointer tear-offs do not require managed allocation', () {
    final pointer = FfiTypes.int64Pointer;
    final forward = FunctionTarget(uri, 'forward', pointer, [pointer]);
    final pass = Block(forward.parameterTypes);
    pass.finish(Return(pass.parameters.single));
    final start = Block();
    final address = start.emit(
      PointerFromAddress(const Constant.integer(32), pointer),
    );
    start.finish(
      Return(
        start.emit(PointerAddress(start.emit(DirectCall(forward, [address])))),
      ),
    );
    final unused = FunctionTarget(uri, 'unused', forward.signature, []);
    final input = IrProgram([], [
      IrFunction(entry, [start]),
      IrFunction(forward, [pass]),
      IrFunction(unused, [Block()..finish(Return(FunctionConstant(forward)))]),
    ]);
    final prepared = Compiler(target).prepare(input, roots: [entry]);
    expect(prepared.definitions, {entry});
    final result = prepared.program.implementationOf(entry) as IrFunction;
    expect(IrInterpreter(prepared.program, {}).run(result, []), 32);
    expect(Arm64CodeGenerator(target).generate(prepared).imports, isEmpty);
  });

  test(
    'callback bridges follow current roots, exports and rewritten bodies',
    () {
      final helper = FunctionTarget(uri, 'address', .integer, []);
      final start = Block();
      final first = start.emit(DirectCall(helper, []));
      final second = start.emit(DirectCall(helper, []));
      start.finish(Return(start.emit(IntBinary(.subtract, first, second))));
      final address = Block();
      address.finish(
        Return(
          address.emit(
            NativeCallbackAddress(
              StaticCallbackTarget(
                other,
                FunctionType(FfiTypes.scalarTypes[Int64]!, []),
                exceptionalReturn: const Constant.integer(-1),
              ),
            ),
          ),
        ),
      );
      final input = IrProgram([], [
        IrFunction(entry, [start]),
        IrFunction(helper, [address]),
        program.implementationOf(other)! as IrFunction,
      ]);
      final unused = Compiler(target).prepare(input, roots: [other]);
      expect(unused.definitions, {other});
      expect(Arm64CodeGenerator(target).generate(unused).imports, isEmpty);
      final removed = IrProgram([], [
        input.implementationOf(entry)! as IrFunction,
        IrFunction(helper, [
          Block()..finish(const Return(Constant.integer(0))),
        ]),
        input.implementationOf(other)! as IrFunction,
      ]);
      final current = _preparation(target, removed, roots: [entry]);
      expect(current.program, same(removed));
      for (final selected in [
        _preparation(target, input, roots: [entry]),
        _preparation(
          target,
          const DirectCallInlining().run(
            ProgramFlow(input, const [], openEntries: [entry]).facts,
          ),
          roots: [entry],
        ),
        _preparation(
          target,
          input,
          exports: {entry: NativeExport('address', NativeSignature(Int64, []))},
        ),
      ]) {
        expect(
          selected.program.functions.where(
            (body) =>
                body.target.library == null && body.callees.contains(other),
          ),
          hasLength(1),
        );
        final facts = CallTypeFlow(selected.program, selected.roots).facts;
        expect(() => current.prepare(facts), throwsArgumentError);
      }
    },
  );

  test('eliminated operations do not retain generated support', () {
    final start = Block(), live = Block(), dead = Block();
    start.finish(Branch(const Constant.boolean(true), Jump(live), Jump(dead)));
    live.finish(const Return(Constant.integer(7)));
    dead.finish(
      Return(
        dead.emit(
          IntBinary(
            .truncateDivide,
            const Constant.integer(1),
            const Constant.integer(0),
          ),
        ),
      ),
    );
    final input = IrProgram([], [
      IrFunction(entry, [start, live, dead]),
    ]);
    final prepared = Compiler(target).prepare(input, roots: [entry]);
    expect(prepared.definitions, {entry});
    expect(Arm64CodeGenerator(target).generate(prepared).imports, isEmpty);
  });

  test('an eliminated callback does not require a persistent runtime', () {
    final start = Block(), live = Block(), dead = Block();
    start.finish(Branch(const Constant.boolean(true), Jump(live), Jump(dead)));
    live.finish(const Return(Constant.integer(7)));
    dead.finish(
      Return(
        dead.emit(
          NativeCallbackAddress(
            StaticCallbackTarget(
              other,
              FunctionType(FfiTypes.scalarTypes[Int64]!, []),
              exceptionalReturn: const Constant.integer(-1),
            ),
          ),
        ),
      ),
    );
    final input = IrProgram([], [
      IrFunction(entry, [start, live, dead]),
      program.implementationOf(other)! as IrFunction,
    ]);
    final prepared = Compiler(target).prepare(input, roots: [entry]);
    final module = Arm64CodeGenerator(target).generate(prepared);
    expect(module.symbols.map((symbol) => symbol.name), contains('entry'));
    expect(module.imports, isEmpty);
  });
}

ProgramPreparation _preparation(
  Target target,
  IrProgram program, {
  Iterable<FunctionTarget> roots = const [],
  Map<FunctionTarget, NativeExport> exports = const {},
}) {
  final boundaries = NativeBoundaries(program, roots: roots, exports: exports);
  return ProgramPreparation(target, boundaries.program, boundaries: boundaries);
}
