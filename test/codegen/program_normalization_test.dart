import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  late IrProgram runtimeProgram;
  setUpAll(() async {
    await prepareRuntime();
    runtimeProgram = ProgramNormalization(
      heapRuntime.program,
      runtime: heapRuntime,
    ).run();
  });
  IrProgram normalize(IrFunction body) => ProgramNormalization(
    IrProgram(
      runtimeProgram.classes,
      [...runtimeProgram.functions, body],
      globals: runtimeProgram.globals,
      externals: runtimeProgram.externals,
    ),
    runtime: heapRuntime,
  ).run();

  test(
    'collection construction exposes checked factories and actual arguments',
    () {
      final root = FunctionTarget(null, 'collections', .voidType, []);
      final block = Block();
      block.emit(NewCollection(CoreTypes.listOf(.integer)));
      block.emit(
        NewCollection(
          CoreTypes.listOf(.integer),
          growable: const Constant.boolean(false),
        ),
      );
      block.emit(NewCollection(CoreTypes.mapOf(.string, .integer)));
      block.emit(NewCollection(CoreTypes.setOf(.integer)));
      final filled = block.emit(
        ListFilled(
          CoreTypes.listOf(.integer),
          const Constant.integer(3),
          const Constant.integer(7),
          const Constant.boolean(false),
        ),
      );
      block.emit(
        ListFrom(
          CoreTypes.listOf(.integer),
          filled,
          const Constant.boolean(true),
        ),
      );
      block.finish(const Return());
      final whole = normalize(IrFunction(root, [block]));
      final normalized = whole.implementationOf(root) as IrFunction;
      final calls = normalized.entry.instructions
          .whereType<DirectCall>()
          .toList();
      expect(calls, hasLength(6));
      for (final (index, call) in calls.indexed) {
        expect(
          heapRuntime.program.implementationOf(call.target),
          isA<IrFunction>(),
        );
        expect(
          call.ownerType!.typeArguments,
          index == 2 ? <ValueType>[.string, .integer] : <ValueType>[.integer],
        );
      }
      expect(
        calls[0].inputs.single,
        isA<ScalarConstant>().having((v) => v.value, 'growable', true),
      );
      expect(
        calls[1].inputs.single,
        isA<ScalarConstant>().having((v) => v.value, 'growable', false),
      );
      expect(calls[4].inputs.map((v) => (v as ScalarConstant).value), [
        3,
        7,
        false,
      ]);
      expect(calls[5].inputs.first, same(calls[4]));
      expect((calls[5].inputs.last as ScalarConstant).value, true);
      expect(
        ProgramNormalization(whole, runtime: heapRuntime).run(),
        same(whole),
      );
    },
  );

  test(
    'generic construction and literal spread retain lexical type arguments',
    () {
      final element = TypeParameterType('E')..initializeBound(.object.nullable);
      final list = CoreTypes.listOf(element);
      final root = FunctionTarget(
        null,
        'spread',
        list,
        [CoreTypes.iterableOf(.object.nullable)],
        typeParameters: [element],
      );
      final block = Block(root.parameterTypes),
          normal = Block([list]),
          caught = Block();
      final value = block.emit(NewCollection(list));
      final spread = CollectionSpread(value, block.parameters.single);
      block.finish(
        Invoke(spread, onReturn: Jump(normal, [value]), onThrow: Jump(caught)),
      );
      normal.finish(Return(normal.parameters.single));
      caught.finish(Throw(const Constant.integer(73)));
      final normalized = normalize(
        IrFunction(root, [block, normal, caught]),
      ).implementationOf(root) as IrFunction;
      final creation = normalized.entry.instructions.single as DirectCall;
      expect(creation.ownerType!.typeArguments, [element]);
      final invocation = normalized.entry.end as Invoke;
      final call = invocation.operation as DirectCall;
      expect(call.typeArguments, [element]);
      expect(call.inputs.first, same(creation));
      expect(invocation.onThrow.target.end, isA<Throw>());
      expect(invocation.onReturn!.target.end, isA<Return>());
    },
  );

  test('missing checked constructors fail before machine representation', () {
    final root = FunctionTarget(
      null,
      'missing',
      CoreTypes.listOf(.integer),
      [],
    );
    final block = Block();
    block.finish(Return(block.emit(NewCollection(CoreTypes.listOf(.integer)))));
    final program = IrProgram([], [
      IrFunction(root, [block]),
    ]);
    expect(() => ProgramNormalization(program).run(), throwsArgumentError);
  });
}
