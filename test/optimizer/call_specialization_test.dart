import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/call_specialization.dart' as source;

void main() {
  late IrProgram program;
  final optimizer = ProgramOptimizer(const [
    ProgramSimplification(),
    ProgramCallSpecialization(),
    ProgramStoragePromotion(),
    ProgramStorageElimination(),
  ]);
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/call_specialization.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  test('unknown values cross generic calls and fields without containers', () {
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'forward',
    );
    final facts = optimizer.run(program, [
      (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
    ]);
    final body = facts.program.implementationOf(entry.target) as IrFunction;
    final interpreter = IrInterpreter(facts.program, {});
    for (final value in [-37, 0, 9, 0x7fffffffffffffff]) {
      expect(interpreter.run(body, [value]), source.forward(value));
    }
    expect(
      body.blocks
          .expand((block) => block.instructions)
          .where(
            (operation) =>
                operation is Construct ||
                operation is LoadField ||
                operation is StoreField ||
                operation is InstanceCall ||
                operation is DirectCall,
          ),
      isEmpty,
    );
  });

  test('a known receiver binds a direct call with unknown arguments', () {
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'dispatch',
    );
    final result = const ProgramCallSpecialization().run(
      ProgramFlow(program, [
        (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
      ]).facts,
    );
    final body = result.implementationOf(entry.target) as IrFunction;
    expect(
      body.callees.where((target) => target.kind == .method).single.name,
      'add',
    );
    expect(body.virtualMembers, isEmpty);
    final interpreter = IrInterpreter(result, {});
    for (final value in [-9, 0, 12]) {
      expect(interpreter.run(body, [value]), source.dispatch(value));
    }
  });

  test('receiver bounds distinguish unique and polymorphic dispatch', () {
    final entry = program.functions.singleWhere(
      (body) => body.target.name == 'readReceiver',
    );
    for (final name in ['Child', 'Parent']) {
      final type = program.classes.singleWhere((c) => c.type.name == name).type;
      final result = const ProgramCallSpecialization().run(
        ProgramFlow(program, [
          (target: entry.target, arguments: [FlowValue.unknown(type)]),
        ]).facts,
      );
      final body = result.implementationOf(entry.target) as IrFunction;
      expect(body.virtualMembers.isEmpty, name == 'Child');
      if (name == 'Child') {
        expect(body.callees.single.owner, type);
      }
      for (final caller in ['readChild', if (name == 'Parent') 'readParent']) {
        final function = result.functions.singleWhere(
          (body) => body.target.name == caller,
        );
        expect(
          IrInterpreter(result, {}).run(function, []),
          caller == 'readChild' ? source.readChild() : source.readParent(),
        );
      }
    }
  });

  for (final example in <String, int Function(int)>{
    'narrowedReceiver': source.narrowedReceiver,
    'covariantReceiver': source.covariantReceiver,
    'negatedEquality': source.negatedEquality,
  }.entries) {
    test('proven member calls preserve ${example.key}', () {
      final function = program.functions.singleWhere(
        (body) => body.target.name == example.key,
      );
      final facts = ProgramFlow(program, [
        (target: function.target, arguments: [FlowValue.unknown(.integer)]),
      ]).facts;
      final specialized = const ProgramCallSpecialization().run(facts);
      final body = specialized.implementationOf(function.target) as IrFunction;
      if (example.key != 'negatedEquality') {
        expect(body.virtualMembers, isEmpty);
      }
      for (final value in [-37, 0, 19]) {
        expect(
          IrInterpreter(specialized, {}).run(body, [value]),
          example.value(value),
        );
      }
    });
  }

  for (final entry in <String, int Function()>{
    'rejectedWrite': source.rejectedWrite,
    'defaultArgument': source.defaultArgument,
  }.entries) {
    test('specialization preserves ${entry.key}', () {
      final function = program.functions.singleWhere(
        (f) => f.target.name == entry.key,
      );
      final facts = optimizer.run(program, [
        (target: function.target, arguments: <FlowValue>[]),
      ]);
      final body =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(IrInterpreter(facts.program, {}).run(body, []), entry.value());
    });
  }

  for (final example in <String, int Function(int)>{
    'staticValue': source.staticValue,
    'capturedValue': source.capturedValue,
    'sharedCapture': source.sharedCapture,
    'multipleCaptures': source.multipleCaptures,
    'lexicalTypes': source.lexicalTypes,
    'genericValue': source.genericValue,
    'boundValue': source.boundValue,
    'aliasedConstructor': source.aliasedConstructor,
    'redirectedConstructor': source.redirectedConstructor,
    'throwingValue': source.throwingValue,
  }.entries) {
    test('known function values preserve ${example.key}', () {
      final entry = program.functions.singleWhere(
        (function) => function.target.name == example.key,
      );
      final entries = [
        (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
      ];
      final specialized = const ProgramCallSpecialization().run(
        ProgramFlow(program, entries).facts,
      );
      final body = specialized.implementationOf(entry.target) as IrFunction;
      final originalCalls = [
        for (final block in entry.blocks)
          ...block.instructions.whereType<FunctionCall>(),
        for (final block in entry.blocks)
          if (block.end case Invoke(operation: final FunctionCall call)) call,
      ];
      expect(originalCalls, isNotEmpty);
      final calls = [
        for (final block in body.blocks)
          ...block.instructions.whereType<FunctionCall>(),
        for (final block in body.blocks)
          if (block.end case Invoke(operation: final FunctionCall call)) call,
      ];
      expect(calls.every((call) => call.target != null), isTrue);
      if ([
        'staticValue',
        'aliasedConstructor',
        'redirectedConstructor',
        'throwingValue',
      ].contains(example.key)) {
        expect(calls, isEmpty);
      } else {
        expect(calls, isNotEmpty);
      }
      final optimized = optimizer.run(specialized, entries);
      final simplified =
          optimized.program.implementationOf(entry.target) as IrFunction;
      for (final value in [-37, 0, 19]) {
        final expected = example.value(value);
        expect(IrInterpreter(specialized, {}).run(body, [value]), expected);
        expect(
          IrInterpreter(optimized.program, {}).run(simplified, [value]),
          expected,
        );
      }
    });
  }

  test('an unknown callable retains its open call contract', () {
    final entry = program.functions.singleWhere(
      (function) => function.target.name == 'unknownFunction',
    );
    final result = const ProgramCallSpecialization().run(
      ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [
            FlowValue.unknown(entry.target.parameterTypes.first),
            FlowValue.unknown(.integer),
          ],
        ),
      ]).facts,
    );
    expect(result, same(program));
  });

  test(
    'a proven call retains its target and rejects a changed entry contract',
    () {
      final uri = Uri.parse('memory:call-target');
      final first = FunctionTarget(uri, 'first', .integer, []);
      final second = FunctionTarget(uri, 'second', .integer, []);
      final target = FunctionTarget(uri, 'call', .integer, [first.signature]);
      final entry = Block(target.parameterTypes);
      final call = entry.emit(
        FunctionCall(entry.parameters.single, [], const {}, const [], first),
      );
      entry.finish(Return(call));
      final body = IrFunction(target, [entry]);
      expect(body.callees, contains(first));
      expect(
        (call.mapInputs((value) => value) as FunctionCall).target,
        same(first),
      );
      expect(
        () => FunctionCall(
          FunctionConstant(second),
          [],
          const {},
          const [],
          first,
        ),
        throwsArgumentError,
      );
      final program = IrProgram([], [
        body,
        IrFunction(first, [Block()..finish(const Return(Constant.integer(1)))]),
        IrFunction(second, [
          Block()..finish(const Return(Constant.integer(2))),
        ]),
      ]);
      final facts = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(FunctionConstant(first))],
        ),
      ]).facts;
      expect(
        facts.returnedBy(target).constant?.structuralKey,
        const Constant.integer(1).structuralKey,
      );
      for (final invalid in [
        FlowValue.constant(FunctionConstant(second)),
        FlowValue.unknown(first.signature),
      ]) {
        expect(
          () => ProgramFlow(program, [
            (target: target, arguments: [invalid]),
          ]),
          throwsStateError,
        );
      }
    },
  );
}
