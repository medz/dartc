import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  test('generic method producer replays lexical descriptors and actual owner projection', () {
    final item = TypeParameterType('Item')..initializeBound(.object.nullable);
    final face = ClassType(
      null,
      'GenericFace',
      isAbstract: true,
      typeParameters: [item],
    );
    final member = FunctionTarget(
      null,
      'read',
      item,
      [],
      owner: face,
      kind: .method,
      isAbstract: true,
    );
    final declarations = <IrClass>[
      IrClass(face, [], members: [member]),
    ];
    final functions = <IrFunction>[];
    final values = <ObjectConstant>[];
    final members = <FunctionTarget>[];
    for (final (index, name) in ['First', 'Second'].indexed) {
      final t = TypeParameterType('Value')..initializeBound(.object.nullable);
      final type = ClassType(
        null,
        name,
        typeParameters: [t],
        interfaces: [
          face.instantiate([t]),
        ],
      );
      final field = InstanceField(type, 'value', t, isFinal: true);
      final method = FunctionTarget(
        null,
        'read',
        t,
        [],
        owner: type,
        kind: .method,
      );
      final body = Block(method.parameterTypes);
      body.finish(Return(body.emit(LoadField(field, body.parameters.single))));
      functions.add(IrFunction(method, [body]));
      declarations.add(IrClass(type, [field], members: [method]));
      values.add(
        ObjectConstant(type.instantiate([ValueType.integer]), {
          field: Constant.integer(41 + index),
        }),
      );
      members.add(method);
    }
    final lexical = TypeParameterType('Lexical')
      ..initializeBound(.object.nullable);
    final extract = FunctionTarget(
      null,
      'extract',
      FunctionType(lexical, []),
      [
        face.instantiate([lexical]),
      ],
      typeParameters: [lexical],
    );
    final extraction = Block(extract.parameterTypes);
    extraction.finish(
      Return(extraction.emit(BindMethod(member, extraction.parameters.single))),
    );
    functions.add(IrFunction(extract, [extraction]));
    final root = FunctionTarget(null, 'choose', .integer, [.boolean]);
    final entry = Block(root.parameterTypes),
        join = Block([
          face.instantiate([ValueType.integer]),
        ]);
    entry.finish(
      Branch(
        entry.parameters.single,
        Jump(join, [values.first]),
        Jump(join, [values.last]),
      ),
    );
    final closure = join.emit(
      DirectCall(extract, join.parameters, typeArguments: [ValueType.integer]),
    );
    join.finish(Return(join.emit(FunctionCall(closure, []))));
    functions.add(IrFunction(root, [entry, join]));
    final runtime = heapRuntime;
    var graph = IrProgram(
      [...runtime.program.classes, ...declarations],
      [...runtime.program.functions, ...functions],
      globals: runtime.program.globals,
      externals: runtime.program.externals,
    );
    FunctionTarget? firstProducer;
    for (final broad in [false, true]) {
      final types = TypeImplementations(runtime: runtime.types?.rebind(graph));
      final callables = CallableImplementations(types: types);
      ProgramLayout layout(IrProgram program) => ProgramLayout(
        program.classes,
        functions: program.functions,
        executionShapes: program.executionShapes,
        typeImplementations: types,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final result =
          ProgramOptimizer([
            TypeLowering(types, failure: runtime.typeCheckFailure),
            CallableLowering(callables),
            MemberEntryLowering(types),
          ]).run(graph, [
            (
              target: root,
              arguments: [
                broad
                    ? FlowValue.unknown(.boolean)
                    : FlowValue.constant(const Constant.boolean(true)),
              ],
            ),
          ], memoryLayoutFor: layout);
      graph = result.program;
      expect(result.pendingExecutionCalls, isEmpty);
      final operation = (graph.implementationOf(extract) as IrFunction).blocks
          .expand(
            (b) => [
              ...b.instructions,
              if (b.end case Invoke(:final operation)) operation,
            ],
          )
          .whereType<BindMethod>()
          .single;
      expect(operation.executionTypes, hasLength(1));
      final current = operation.entryBinding!.entries[members.first]!;
      if (firstProducer == null) firstProducer = current;
      expect(current, firstProducer);
      if (broad)
        expect(operation.entryBinding!.entries.keys.toSet(), members.toSet());
      final runner = IrInterpreter(graph, {}, typeLayout: layout(graph));
      expect(
        runner.run(graph.implementationOf(root) as IrFunction, [true]),
        41,
      );
      if (broad)
        expect(
          runner.run(graph.implementationOf(root) as IrFunction, [false]),
          42,
        );
    }
  });
}
