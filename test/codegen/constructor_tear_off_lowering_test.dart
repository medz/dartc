import 'package:dartc/frontend.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/constructor_tear_off_lowering.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/pointer_representation.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/constructor_tear_offs.dart' as source;

void main() {
  final uri = Uri.parse('memory:constructor-entries');
  test('residual constructor calls match execution identity and keep callable pointer ABI', () {
    for (final pointer in [false, true]) {
      final owner = pointer ? FfiTypes.int64Pointer : ClassType(uri, 'Value');
      final initializer = FunctionTarget(
        owner.library,
        'new',
        .voidType,
        [],
        owner: owner.declaration,
        kind: .initializer,
      );
      final destination = FunctionTarget(uri, 'implementation', owner, []);
      final constructor = IrFunction(initializer, [
        Block(initializer.parameterTypes)..finish(const Return()),
      ]);
      final targetBlock = Block();
      targetBlock.finish(
        Return(
          pointer
              ? targetBlock.emit(
                  PointerFromAddress(const Constant.integer(16), owner),
                )
              : ObjectConstant(owner, {}),
        ),
      );
      final implementation = IrFunction(destination, [targetBlock]);
      final constant = FunctionConstant(
        initializer,
        ownerType: pointer ? owner : null,
      ).withInvocationEntry(destination);
      final caller = FunctionTarget(uri, 'invoke', owner, [constant.type]);
      final block = Block(caller.parameterTypes);
      block.emit(DirectCall(destination, []));
      final call = block.emit(
        FunctionCall(
          block.parameters.single,
          [],
          const {},
          const [],
          destination,
        ),
      );
      block.finish(Return(call));
      final body = IrFunction(caller, [block]);
      final getter = FunctionTarget(uri, 'getCallable', constant.type, []);
      final bodies = [
        constructor,
        implementation,
        body,
        IrFunction(getter, [Block()..finish(Return(constant))]),
      ];
      final classes = [
        IrClass(owner.declaration, [], constructors: [initializer]),
      ];
      final program = IrProgram(classes, bodies);
      final closures = ClosureStorage(bodies);
      final layout = ProgramLayout(
        [...classes, ...closures.classes],
        functions: bodies,
        closureStorage: closures,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final represented = FunctionRepresentation(
        body,
        layout,
        CheckedCasts(),
        MemberCalls(program, {}),
        HeapPlan(),
      )..prune();
      expect(
        represented.invocations.entries
            .where((entry) => represented.callOrigins[entry.key] == call)
            .map((entry) => entry.value),
        [destination],
      );
      if (pointer) {
        expect(
          PointerRepresentation(bodies).returnsAddress(destination),
          isFalse,
        );
      }
    }
  });

  test('precise external constructor inputs close before specialization', () {
    final owner = ClassType(uri, 'Box');
    final field = InstanceField(owner, 'value', .integer);
    final initializer = FunctionTarget(
      uri,
      'new',
      .voidType,
      [.integer],
      owner: owner,
      kind: .initializer,
    );
    final body = Block(initializer.parameterTypes);
    body.emit(StoreField(field, body.parameters[0], body.parameters[1]));
    body.finish(const Return());
    final constant = FunctionConstant(initializer);
    final root = FunctionTarget(uri, 'root', .integer, [
      constant.type,
      .integer,
    ]);
    final entry = Block(root.parameterTypes);
    final made = entry.emit(
      FunctionCall(entry.parameters[0], [entry.parameters[1]]),
    );
    entry.finish(Return(entry.emit(LoadField(field, made))));
    final program = IrProgram(
      [
        IrClass(owner, [field], constructors: [initializer]),
      ],
      [
        IrFunction(initializer, [body]),
        IrFunction(root, [entry]),
      ],
    );
    final facts =
        ProgramOptimizer(const [
          ConstructorTearOffLowering(),
          ProgramCallSpecialization(),
        ]).run(program, [
          (
            target: root,
            arguments: [
              FlowValue.constant(constant),
              FlowValue.constant(const Constant.integer(42)),
            ],
          ),
        ]);
    final rebound =
        facts.entries.single.arguments[0].constant as FunctionConstant;
    expect(rebound.structuralKey, constant.structuralKey);
    expect(rebound.invocationEntry, isNotNull);
    expect(facts.definitions, contains(rebound.invocationEntry));
    final rewritten = facts.program.implementationOf(root) as IrFunction;
    expect(
      rewritten.blocks
          .expand((block) => block.instructions)
          .whereType<Construct>(),
      isEmpty,
    );
    expect(rewritten.callees, contains(rebound.invocationEntry));
    expect((facts.returnedBy(root).constant as ScalarConstant).value, 42);
    expect(constant.invocationEntry, isNull);
  });

  test(
    'invocation entries keep identity and reject a different callable contract',
    () {
      final owner = ClassType(uri, 'Value');
      final initializer = FunctionTarget(
        uri,
        'new',
        .voidType,
        [.integer],
        owner: owner,
        kind: .initializer,
      );
      final original = FunctionConstant(initializer);
      final entry = FunctionTarget(uri, 'invoke', owner, [.integer]);
      final rebound = original.withInvocationEntry(entry);
      expect(rebound.target, same(initializer));
      expect(rebound.type, original.type);
      expect(rebound.structuralKey, original.structuralKey);
      expect(rebound.resolveInvocation([]).target, same(entry));
      final output = StringBuffer();
      IrFunction(FunctionTarget(uri, 'extracted', rebound.type, []), [
        Block()..finish(Return(rebound)),
      ]).writeTo(output);
      expect(
        output.toString(),
        contains('via memory:constructor-entries::invoke'),
      );
      final call = FunctionCall(
        original,
        [const Constant.integer(4)],
        {},
        [],
        initializer,
      );
      final mapped = call.mapInputs(
        (value) => value == original ? rebound : value,
      ) as FunctionCall;
      expect(mapped.target, same(entry));
      for (final invalid in [
        FunctionTarget(uri, 'wrongResult', .integer, [.integer]),
        FunctionTarget(uri, 'wrongParameter', owner, [.string]),
        initializer,
      ]) {
        expect(
          () => original.withInvocationEntry(invalid),
          throwsArgumentError,
        );
      }
    },
  );

  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/codegen/fixtures/constructor_tear_offs.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });
  IrFunction function(String name, [IrProgram? input]) =>
      (input ?? program).functions.singleWhere(
        (body) =>
            body.target.name == name &&
            body.target.library?.path.endsWith('/constructor_tear_offs.dart') ==
                true,
      );

  test('retained bridges precede specialization and storage never creates a second implementation', () {
    final root = function('redirected').target;
    final transform = const ConstructorTearOffLowering().bind();
    final lowered = transform(
      ProgramFlow(program, [], openEntries: [root]).facts,
    );
    final rewritten = lowered.implementationOf(root) as IrFunction;
    final constant = rewritten.functionConstants.single;
    final entry = constant.invocationEntry!;
    final bridge = lowered.implementationOf(entry) as IrFunction;
    expect(
      bridge.blocks.single.instructions.whereType<Construct>(),
      hasLength(1),
    );
    expect(rewritten.callees, contains(entry));
    expect(rewritten.callees, isNot(contains(constant.target)));
    expect(
      () => ClosureStorage([function('redirected')]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'missing lowering',
          contains('must be lowered before storage'),
        ),
      ),
    );
    expect(
      function(
        'unusedTearOff',
        lowered,
      ).functionConstants.single.invocationEntry,
      isNull,
    );
    final facts = ProgramFlow(lowered, [], openEntries: [root]).facts;
    expect(transform(facts), same(lowered));
    final selection = CallTypeFlow(lowered, [root]);
    expect(selection.facts.definitions, contains(entry));
    final storage = ClosureStorage(
      lowered.functions.where(
        (body) => facts.definitions.contains(body.target),
      ),
    );
    expect(storage.constants[constant.structuralKey]!.target, same(entry));
    expect(
      storage.constants[constant.structuralKey]!.sourceTarget,
      same(constant.target),
    );
    expect(
      storage.functions.where(
        (body) => body.target.name.startsWith('constructor'),
      ),
      isEmpty,
    );
    final specialized = const ProgramCallSpecialization().run(facts);
    final body = specialized.implementationOf(root) as IrFunction;
    expect(
      body.blocks
          .expand((block) => block.instructions)
          .whereType<DirectCall>()
          .where((call) => call.target == entry),
      hasLength(1),
    );
    expect(
      body.blocks.expand((block) => block.instructions).whereType<Construct>(),
      isEmpty,
    );
  });

  test('constructor calls preserve redirects, generic aliases, defaults and source identity', () {
    final roots = [
      for (final name in [
        'redirected',
        'factoryBody',
        'caught',
        'named',
        'generic',
        'alias',
        'useDefault',
        'nested',
        'concreteIdentity',
        'instantiatedEquality',
        'aliasIdentity',
      ])
        function(name).target,
    ];
    final initialFacts = ProgramOptimizer(const [ConstructorTearOffLowering()])
        .run(program, [], openEntries: roots);
    final lowered = initialFacts.program;
    final defaulted = function('defaulted', lowered);
    expect(
      (defaulted.defaults.values.single as FunctionConstant).invocationEntry,
      isNotNull,
    );
    final factoryEntry = function(
      'factoryBody',
      lowered,
    ).functionConstants.single.invocationEntry!;
    expect(
      (lowered.implementationOf(
        factoryEntry,
      ) as IrFunction).blocks.single.instructions.single,
      isA<DirectCall>(),
    );
    final storage = ClosureStorage(
      lowered.functions.where(
        (body) => initialFacts.definitions.contains(body.target),
      ),
    );
    for (final name in ['generic', 'alias', 'nested']) {
      final constants = function(name, lowered).functionConstants;
      expect(constants, isNotEmpty);
      for (final constant in constants) {
        expect(constant.invocationEntry?.signature, constant.genericSignature);
        final shape = storage.constants[constant.structuralKey]!;
        expect(shape.sourceTarget, same(constant.target));
        expect(shape.signature, constant.type);
      }
    }
    final facts = ProgramOptimizer(const [
      ConstructorTearOffLowering(),
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      DirectCallInlining(),
    ]).run(program, [], openEntries: roots);
    for (final executable in [lowered, facts.program]) {
      final runner = IrInterpreter(executable, {});
      for (final input in [-7, 0, 42]) {
        for (final (name, expected) in <(String, int Function(int))>[
          ('redirected', source.redirected),
          ('factoryBody', source.factoryBody),
          ('caught', source.caught),
          ('named', source.named),
          ('generic', source.generic),
          ('alias', source.alias),
          ('nested', source.nested),
          ('useDefault', source.useDefault),
        ]) {
          expect(
            runner.run(function(name, executable), [input]),
            expected(input),
            reason: name,
          );
        }
      }
      for (final (name, expected) in [
        ('concreteIdentity', source.concreteIdentity()),
        ('instantiatedEquality', source.instantiatedEquality()),
        ('aliasIdentity', source.aliasIdentity()),
      ]) {
        expect(
          runner.run(function(name, executable), []),
          expected,
          reason: name,
        );
      }
    }
  });
}
