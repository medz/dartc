import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'a wider function view reads its real header across a helper summary',
    () {
      final root = FunctionTarget(null, 'root', .boolean, []);
      final source = FunctionTarget(
        null,
        'source',
        .integer,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 1,
      );
      final body = Block(source.parameterTypes)
        ..finish(const Return(Constant.integer(42)));
      final sourceBody = IrFunction(source, [body]);
      final storage = ClosureStorage([], definitions: [sourceBody]);
      final shape = storage.ensureClosure(source);
      final view = FunctionType(.number, []);
      final create = FunctionTarget(null, 'create', view, []);
      final entry = Block();
      entry.finish(
        Return(
          entry.emit(
            Construct.callable(
              shape.storage,
              [entry.emit(FunctionEntryTableAddress(source))],
              view,
              TypeConstant(source.signature),
            ),
          ),
        ),
      );
      final test = Block();
      final function = test.emit(DirectCall(create, []));
      test.finish(Return(test.emit(TypeTest(function, source.signature))));
      final program = IrProgram(
        [
          ...storage.classes,
          for (final entry in TypeMetadata.fields.entries)
            IrClass(entry.key, entry.value),
        ],
        [
          sourceBody,
          ...storage.functions,
          IrFunction(create, [entry]),
          IrFunction(root, [test]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ]).facts;
      expect((facts.returnedBy(root).constant as ScalarConstant).value, isTrue);
      final optimized = ProgramOptimizer(const [
        ProgramSimplification(),
        ProgramStorageElimination(),
        DirectCallInlining(),
        ProgramCallSpecialization(),
      ]).run(program, [(target: root, arguments: <FlowValue>[])]);
      for (final graph in [program, optimized.program]) {
        expect(
          IrInterpreter(
            graph,
            {},
          ).run(graph.implementationOf(root) as IrFunction, []),
          isTrue,
        );
      }
    },
  );

  test('the static function view cannot decide a narrower runtime check', () {
    final root = FunctionTarget(null, 'root', .voidType, []);
    final source = FunctionTarget(
      null,
      'source',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 1,
    );
    final sourceBody = IrFunction(source, [
      Block(source.parameterTypes)..finish(const Return(Constant.integer(42))),
    ]);
    final storage = ClosureStorage([], definitions: [sourceBody]);
    final shape = storage.ensureClosure(source);
    final operation = Construct.callable(
      shape.storage,
      [FunctionEntryTableAddress(source)],
      FunctionType(.number, []),
      TypeConstant(source.signature),
    );
    final value = FlowValue.object(FlowObject(operation, Object()));
    final check = value.check(source.signature, runtimeTypes: true);
    expect(check.value.objects, value.objects);
    expect(check.mayFail, isTrue);
    final known = value.check(
      source.signature,
      runtimeTypes: true,
      runtimeTypeOf: (_) => source.signature,
    );
    expect(known.mayFail, isFalse);
    expect(known.value.objects, value.objects);
  });
}
