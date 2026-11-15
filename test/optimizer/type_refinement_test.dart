import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/type_refinement.dart' as source;

void main() {
  final uri = Uri.parse('memory:type-refinement');
  test(
    'generic external and unknown function results use their call environment',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final external = FunctionTarget(
        uri,
        'external',
        t,
        [],
        typeParameters: [t],
      );
      final u = TypeParameterType('U')..initializeBound(.object.nullable);
      final forward = FunctionTarget(
        uri,
        'forwardExternal',
        u,
        [],
        typeParameters: [u],
      );
      final forwarding = Block();
      forwarding.finish(
        Return(forwarding.emit(DirectCall(external, [], typeArguments: [u]))),
      );
      final v = TypeParameterType('V')..initializeBound(.object.nullable);
      final indirect = FunctionTarget(
        uri,
        'forwardFunction',
        v,
        [FunctionType(v, [])],
        typeParameters: [v],
      );
      final indirectBody = Block(indirect.parameterTypes);
      indirectBody.finish(
        Return(
          indirectBody.emit(FunctionCall(indirectBody.parameters.single, [])),
        ),
      );
      final root = FunctionTarget(uri, 'entry', .voidType, [
        FunctionType(.integer, []),
        FunctionType(.string, []),
      ]);
      final entry = Block(root.parameterTypes);
      final operations = <DirectCall>[];
      for (final (index, type) in [
        ValueType.integer,
        ValueType.string,
      ].indexed) {
        operations.add(
          entry.emit(DirectCall(forward, [], typeArguments: [type])),
        );
        operations.add(
          entry.emit(
            DirectCall(
              indirect,
              [entry.parameters[index]],
              typeArguments: [type],
            ),
          ),
        );
      }
      entry.finish(const Return());
      final program = IrProgram(
        [],
        [
          IrFunction(forward, [forwarding]),
          IrFunction(indirect, [indirectBody]),
          IrFunction(root, [entry]),
        ],
        externals: [IrExternal(external, effects: const {})],
      );
      final facts = ProgramFlow(program, [
        (
          target: root,
          arguments: root.parameterTypes.map(FlowValue.unknown).toList(),
        ),
      ]).facts;
      for (final call in operations) {
        expect(facts.valueOf(call).unknownTypes, {call.type});
        expect(
          facts
              .valueOf(call)
              .types
              .every((type) => type.freeTypeParameters.isEmpty),
          isTrue,
        );
      }
    },
  );

  late IrProgram sourceProgram;
  test('generic field and record reads receive the resolved result type', () {
    final parameter = TypeParameterType('E')..initializeBound(.object.nullable);
    final box = ClassType(uri, 'Box', typeParameters: [parameter]);
    final field = InstanceField(box, 'value', parameter);
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final record = RecordType([t]);
    final read = FunctionTarget(
      uri,
      'read',
      t,
      [
        box.instantiate([t]),
        record,
      ],
      typeParameters: [t],
    );
    final body = Block(read.parameterTypes);
    final fieldValue = body.emit(LoadField(field, body.parameters.first));
    final recordValue = body.emit(RecordGet(body.parameters.last, 0));
    body.finish(Return(recordValue));
    final main = FunctionTarget(uri, 'main', .voidType, [
      for (final type in [ValueType.integer, ValueType.string]) ...[
        box.instantiate([type]),
        RecordType([type]),
      ],
    ]);
    final entry = Block(main.parameterTypes);
    for (final (index, type) in [ValueType.integer, ValueType.string].indexed) {
      entry.emit(
        DirectCall(
          read,
          entry.parameters.skip(index * 2).take(2),
          typeArguments: [type],
        ),
      );
    }
    entry.finish(const Return());
    final program = IrProgram(
      [
        IrClass(box, [field]),
      ],
      [
        IrFunction(read, [body]),
        IrFunction(main, [entry]),
      ],
    );
    final facts = ProgramFlow(program, [
      (
        target: main,
        arguments: main.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ]).facts;
    for (final activation in facts.activationsOf(read)) {
      final owner =
          facts
                  .valueOf(body.parameters.first, activation: activation)
                  .unknownTypes
                  .single
              as ClassType;
      for (final operation in [fieldValue, recordValue]) {
        expect(facts.valueOf(operation, activation: activation).unknownTypes, {
          owner.typeArguments.single,
        });
      }
    }
  });

  setUpAll(() async {
    sourceProgram = await AnalysisSession([
      'test/optimizer/fixtures/type_refinement.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  test('open generic dispatch excludes unrelated exact constant receivers', () {
    final function = sourceProgram.functions.singleWhere(
      (body) => body.target.name == 'readCount',
    );
    final facts = ProgramFlow(sourceProgram, [
      (
        target: function.target,
        arguments: function.target.parameterTypes
            .map(FlowValue.unknown)
            .toList(),
      ),
    ]).facts;
    expect(facts.thrownBy(function.target).exception.isBottom, isTrue);
    expect(facts.returnedBy(function.target).integers, FlowIntegerRange(3, 7));
    final storage = sourceProgram.functions.singleWhere(
      (body) =>
          body.target.name == 'count' &&
          body.target.owner?.name == 'StorageReader',
    );
    expect(facts.activationsOf(storage.target), isNotEmpty);
    for (final activation in facts.activationsOf(storage.target)) {
      expect(
        facts
            .valueOf(storage.entry.parameters.first, activation: activation)
            .types
            .every(
              (type) =>
                  type is ClassType &&
                  type.declaration == storage.target.owner!.declaration,
            ),
        isTrue,
      );
    }
  });

  test('caller result bounds constrain open generic receiver results', () {
    final function = sourceProgram.functions.singleWhere(
      (body) => body.target.name == 'readBag',
    );
    final facts = ProgramFlow(sourceProgram, [
      (
        target: function.target,
        arguments: function.target.parameterTypes
            .map(FlowValue.unknown)
            .toList(),
      ),
    ]).facts;
    expect(facts.returnedBy(function.target).unknownTypes, {ValueType.integer});
    expect(facts.thrownBy(function.target).exception.isBottom, isTrue);
    final read = function.entry.instructions
        .whereType<InstanceCall>()
        .firstWhere(
          (call) =>
              call.type is ClassType &&
              (call.type as ClassType).name == 'Receiver',
        );
    expect(facts.valueOf(read).unknownTypes, {read.type});
  });

  for (final example in <String, int Function(bool)>{
    'nullableGuard': source.nullableGuard,
    'nullAssertion': source.nullAssertion,
    'genericChecks': source.genericChecks,
  }.entries) {
    test('source guards preserve ${example.key}', () {
      final body = sourceProgram.functions.singleWhere(
        (body) => body.target.name == example.key,
      );
      final facts =
          ProgramOptimizer(const [
            ProgramCallSpecialization(),
            ProgramSimplification(),
          ]).run(sourceProgram, [
            (target: body.target, arguments: [FlowValue.unknown(.boolean)]),
          ]);
      final optimized =
          facts.program.implementationOf(body.target) as IrFunction;
      for (final selected in [true, false]) {
        final expected = example.value(selected);
        expect(
          IrInterpreter(facts.program, {}).run(optimized, [selected]),
          expected,
        );
        final exact = ProgramFlow(sourceProgram, [
          (
            target: body.target,
            arguments: [FlowValue.constant(Constant.boolean(selected))],
          ),
        ]).facts;
        expect(
          exact.returnedBy(body.target).constant?.structuralKey,
          Constant.integer(expected).structuralKey,
        );
      }
    });
  }

  for (final negated in [false, true]) {
    test('type-test edges filter both outcomes with negated=$negated', () {
      final target = FunctionTarget(uri, 'select', .object.nullable, [
        .object.nullable,
      ]);
      final entry = Block(target.parameterTypes);
      final test = entry.emit(
        TypeTest(
          entry.parameters.single,
          ValueType.integer.nullable,
          negated: negated,
        ),
      );
      final matches = test.refinement(!negated)!;
      final misses = test.refinement(negated)!;
      final yes = Block([matches.type])
        ..finish(const Return(Constant.nullValue()));
      final no = Block([misses.type]);
      no.finish(Return(no.parameters.single));
      final yesEdge = Jump(yes, [matches]), noEdge = Jump(no, [misses]);
      entry.finish(
        Branch(test, negated ? noEdge : yesEdge, negated ? yesEdge : noEdge),
      );
      final body = IrFunction(target, [entry, yes, no]);
      final program = IrProgram([], [body]);
      final values = FlowValue.constant(const Constant.integer(7))
          .join(FlowValue.constant(const Constant.string('other')))
          .join(FlowValue.constant(const Constant.nullValue()));
      final facts = ProgramFlow(program, [
        (target: target, arguments: [values]),
      ]).facts;
      expect(
        facts.valueOf(matches).constants.map((c) => c.structuralKey).toSet(),
        {
          const Constant.integer(7).structuralKey,
          const Constant.nullValue().structuralKey,
        },
      );
      expect(
        facts.valueOf(misses).constant?.structuralKey,
        const Constant.string('other').structuralKey,
      );
      expect(
        facts.valueOf(no.parameters.single),
        facts
            .valueOf(misses)
            .withSource(
              no.parameters.single,
              facts.activationsOf(target).single,
            ),
      );
      final exact = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.integer(7))],
        ),
      ]).facts;
      expect(exact.valueOf(misses).isBottom, isTrue);
      expect(exact.equivalentsOf(misses), isEmpty);
      expect(exact.reachesBlock(no), isFalse);
    });
  }

  test('source generic null checks disappear only for non-null inputs', () {
    for (final (name, evaluate, samples)
        in <(String, int Function(Object?), List<Object?>)>[
          (
            'nonNullableInput',
            (value) => source.nonNullableInput(value!),
            [-3, 0, 'value', true],
          ),
          ('nullableInput', source.nullableInput, [null, -3, 0, 'value', true]),
        ]) {
      final body = sourceProgram.functions.singleWhere(
        (body) => body.target.name == name,
      );
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ]).run(sourceProgram, [
            (
              target: body.target,
              arguments: body.target.parameterTypes
                  .map(FlowValue.unknown)
                  .toList(),
            ),
          ]);
      final rewritten =
          facts.program.implementationOf(body.target) as IrFunction;
      for (final value in samples) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [value]),
          evaluate(value),
        );
      }
      if (name == 'nonNullableInput') {
        expect(
          facts.returnedBy(body.target).constant?.structuralKey,
          const Constant.integer(7).structuralKey,
        );
        expect(facts.definitions, {body.target});
        expect(
          rewritten.blocks
              .expand((block) => block.instructions)
              .whereType<TypeTest>(),
          isEmpty,
        );
      } else {
        expect(facts.returnedBy(body.target).constant, isNull);
      }
    }
    final open = sourceProgram.functions.singleWhere(
      (body) => body.target.name == 'possibleInterface',
    );
    final facts = ProgramFlow(sourceProgram, [
      (
        target: open.target,
        arguments: open.target.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ]).facts;
    expect(facts.returnedBy(open.target).constant, isNull);
    expect(facts.returnedBy(open.target).unknownTypes, {ValueType.boolean});
  });

  test(
    'null assertions refine normal values without losing exceptional paths',
    () {
      final target = FunctionTarget(uri, 'assertNotNull', .object, [
        .dynamicType,
      ]);
      final entry = Block(target.parameterTypes);
      final checked = entry.emit(NullCheck(entry.parameters.single));
      final viewed = entry.emit(UncheckedCast(checked, .object));
      entry.finish(Return(viewed));
      final body = IrFunction(target, [entry]);
      final program = IrProgram([], [body]);
      for (final (input, expected, throws) in [
        (FlowValue.unknown(.dynamicType), ValueType.object, true),
        (
          FlowValue.unknown(ValueType.integer.nullable),
          ValueType.integer,
          true,
        ),
        (FlowValue.unknown(.integer), ValueType.integer, false),
      ]) {
        final facts = ProgramFlow(program, [
          (target: target, arguments: [input]),
        ]).facts;
        expect(facts.valueOf(checked).unknownTypes, {expected});
        expect(facts.valueOf(viewed).unknownTypes, {expected});
        expect(facts.exitsOf(checked), (normal: true, exceptional: throws));
        expect(facts.effectsOf(checked).contains(Effect.mayThrow), throws);
      }
      final failed = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.nullValue())],
        ),
      ]).facts;
      expect(failed.valueOf(checked).isBottom, isTrue);
      expect(failed.exitsOf(checked), (normal: false, exceptional: true));
      expect(failed.reachesOperation(viewed), isFalse);
    },
  );

  test('refinement queries use each invocation generic environment', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final target = FunctionTarget(
      uri,
      'choose',
      .object.nullable,
      [.object.nullable],
      typeParameters: [t],
    );
    final entry = Block(target.parameterTypes);
    final condition = entry.emit(TypeTest(entry.parameters.single, t));
    final refinement = condition.refinement(true)!;
    final yes = Block([refinement.type]);
    yes.finish(Return(yes.parameters.single));
    final no = Block()..finish(const Return(Constant.nullValue()));
    entry.finish(Branch(condition, Jump(yes, [refinement]), Jump(no)));
    final body = IrFunction(target, [entry, yes, no]);
    final main = FunctionTarget(uri, 'main', .voidType, []);
    final calls = Block();
    for (final (input, type) in <(Constant, ValueType)>[
      (const Constant.integer(7), .integer),
      (const Constant.string('kept'), .string),
      (const Constant.integer(7), .string),
    ]) {
      calls.emit(DirectCall(target, [input], typeArguments: [type]));
    }
    calls.finish(const Return());
    final program = IrProgram([], [
      body,
      IrFunction(main, [calls]),
    ]);
    final facts = ProgramFlow(program, [(target: main, arguments: [])]).facts;
    var reached = 0, rejected = 0;
    for (final activation in facts.activationsOf(target)) {
      final matches = facts.valueOf(condition, activation: activation).constant;
      final value = facts.valueOf(refinement, activation: activation);
      if (matches case ScalarConstant(value: true)) {
        reached++;
        expect(
          value.constant?.structuralKey,
          facts
              .valueOf(entry.parameters.single, activation: activation)
              .constant
              ?.structuralKey,
        );
        expect(
          value,
          facts
              .valueOf(yes.parameters.single, activation: activation)
              .withSources(value.sources),
        );
      } else {
        rejected++;
        expect(value.isBottom, isTrue);
      }
    }
    expect(reached, 2);
    expect(rejected, 1);
  });
}
