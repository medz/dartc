import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final classes = [
    for (final entry in TypeMetadata.fields.entries)
      IrClass(entry.key, entry.value),
  ];
  final uri = Uri.parse('memory:checked-types');
  TypeParameterType parameter(String name, [ValueType? bound]) =>
      TypeParameterType(name)..initializeBound(bound ?? .number);

  test(
    'body descriptor is checked before use and failure preserves writes',
    () {
      final state = GlobalVariable(uri, 'state', .integer, isLate: true);
      final t = parameter('T');
      final target = FunctionTarget(uri, 'entry', .integer, [
        TypeMetadata.type,
      ]);
      final start = Block(target.parameterTypes),
          normal = Block(),
          failed = Block();
      start.emit(StoreGlobal(state, const Constant.integer(7)));
      final check = CheckedTypeArgument(t, start.parameters.single, {
        t: start.parameters.single,
      });
      start.finish(
        Invoke(check, onReturn: Jump(normal), onThrow: Jump(failed)),
      );
      normal.emit(ReifyType(t));
      normal.finish(const Return(Constant.integer(42)));
      failed.finish(Return(failed.emit(LoadGlobal(state))));
      final body = IrFunction(
        target,
        [start, normal, failed],
        typeBindings: [TypeBinding.checked(check)],
      );
      for (final actual in [ValueType.integer, ValueType.string]) {
        final root = FunctionTarget(uri, 'root', .integer, []);
        final entry = Block();
        // Explicit metadata view is a representation conversion, not a bound proof.
        final metadata = entry.emit(
          UncheckedCast(TypeConstant(actual), TypeMetadata.type),
        );
        entry.finish(Return(entry.emit(DirectCall(target, [metadata]))));
        final program = IrProgram(
          classes,
          [
            IrFunction(root, [entry]),
            body,
          ],
          globals: [state],
        );
        final expected = actual == ValueType.integer ? 42 : 7;
        expect(
          IrInterpreter(
            program,
            {},
          ).run(program.implementationOf(root) as IrFunction, []),
          expected,
        );
        final flow = ProgramFlow(program, [
          (target: root, arguments: const []),
        ]).facts;
        expect(
          (flow.returnedBy(root).constant as ScalarConstant).value,
          expected,
        );
        final optimized = ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramCallSpecialization(),
          ProgramStoragePromotion(),
          ProgramStorageElimination(),
          ProgramBranchSpecialization(),
          ProgramLoopSpecialization(),
          DirectCallInlining(),
        ]).run(program, [(target: root, arguments: const [])]);
        expect(
          IrInterpreter(
            optimized.program,
            {},
          ).run(optimized.program.implementationOf(root) as IrFunction, []),
          expected,
        );
      }
    },
  );

  test(
    'unknown descriptor remains a descriptor and never becomes its bound',
    () {
      final t = parameter('T');
      final target = FunctionTarget(uri, 'unknown', .typeType, [
        TypeMetadata.type,
      ]);
      final entry = Block(target.parameterTypes);
      final check = entry.emit(
        CheckedTypeArgument(t, entry.parameters.single, {
          t: entry.parameters.single,
        }),
      );
      final reified = entry.emit(ReifyType(t));
      entry.finish(Return(reified));
      final body = IrFunction(
        target,
        [entry],
        typeBindings: [TypeBinding.checked(check)],
      );
      final facts = ProgramFlow(IrProgram(classes, [body]), [
        (target: target, arguments: [FlowValue.unknown(TypeMetadata.type)]),
      ]).facts;
      expect(facts.valueOf(reified).constant, isNull);
      expect(facts.valueOf(reified).isBottom, isFalse);
      expect(
        ValueLiveness.source(body).uses[entry]!.containsKey(check),
        isTrue,
      );
    },
  );

  test('type use on failure path or before checkpoint is rejected', () {
    for (final before in [true, false]) {
      final t = parameter('T');
      final target = FunctionTarget(uri, 'bad', .typeType, [TypeMetadata.type]);
      final entry = Block(target.parameterTypes),
          normal = Block(),
          failed = Block();
      final check = CheckedTypeArgument(t, entry.parameters.single, {
        t: entry.parameters.single,
      });
      if (before) entry.emit(ReifyType(t));
      entry.finish(
        Invoke(check, onReturn: Jump(normal), onThrow: Jump(failed)),
      );
      normal.finish(Return(TypeConstant(.integer)));
      failed.finish(
        Return(before ? TypeConstant(.string) : failed.emit(ReifyType(t))),
      );
      expect(
        () => IrFunction(
          target,
          [entry, normal, failed],
          typeBindings: [TypeBinding.checked(check)],
        ),
        throwsStateError,
      );
    }
  });

  test(
    'rewrites reject unchecked replacement and preserve checkpoint binding',
    () {
      final t = parameter('T');
      final target = FunctionTarget(uri, 'rewrite', .typeType, [
        TypeMetadata.type,
      ]);
      final entry = Block(target.parameterTypes);
      final check = entry.emit(
        CheckedTypeArgument(t, entry.parameters.single, {
          t: entry.parameters.single,
        }),
      );
      entry.finish(Return(entry.emit(ReifyType(t))));
      final body = IrFunction(
        target,
        [entry],
        typeBindings: [TypeBinding.checked(check)],
      );
      expect(
        () => FunctionRewrite(
          body,
          replacements: {check: entry.parameters.single},
          discardable: {check},
        ).run(),
        throwsStateError,
      );
      final helper = FunctionTarget(uri, 'check', TypeMetadata.type, [
        TypeMetadata.type,
        TypeMetadata.type,
      ]);
      final mapped = FunctionRewrite(
        body,
        operations: {
          check: CheckedTypeArgument(t, entry.parameters.single, {
            t: entry.parameters.single,
          }, implementation: helper),
        },
      ).run();
      expect(mapped.typeBindings.single.check.implementation, helper);
      expect(mapped.callees, contains(helper));
    },
  );

  test('simultaneous raw environment validates cross-parameter bounds', () {
    final u = parameter('U', .object);
    final t = parameter('T', u);
    final target = FunctionTarget(uri, 'crossBound', .typeType, []);
    final entry = Block();
    final integer = TypeConstant(.integer), string = TypeConstant(.string);
    final env = {t: integer, u: string};
    final outer = entry.emit(CheckedTypeArgument(u, string, env));
    final check = entry.emit(CheckedTypeArgument(t, integer, env));
    entry.finish(Return(entry.emit(ReifyType(t))));
    final body = IrFunction(
      target,
      [entry],
      typeBindings: [TypeBinding.checked(outer), TypeBinding.checked(check)],
    );
    final program = IrProgram(classes, [body]);
    expect(
      () => IrInterpreter(program, {}).run(body, []),
      throwsA(isA<TypeError>()),
    );
  });

  test(
    'actual helper writes and exceptional exits are analyzed at checkpoint',
    () {
      final state = GlobalVariable(uri, 'helperState', .integer, isLate: true);
      final t = parameter('T');
      final helper = FunctionTarget(uri, 'reject', TypeMetadata.type, [
        TypeMetadata.type,
        TypeMetadata.type,
      ]);
      final implementation = Block(helper.parameterTypes);
      implementation.emit(StoreGlobal(state, const Constant.integer(9)));
      implementation.finish(Throw(const Constant.string('bad type')));
      final target = FunctionTarget(uri, 'invokeCheck', .integer, [
        TypeMetadata.type,
      ]);
      final entry = Block(target.parameterTypes),
          normal = Block(),
          caught = Block();
      final check = CheckedTypeArgument(t, entry.parameters.single, {
        t: entry.parameters.single,
      }, implementation: helper);
      entry.finish(
        Invoke(check, onReturn: Jump(normal), onThrow: Jump(caught)),
      );
      normal.finish(const Return(Constant.integer(0)));
      caught.finish(Return(caught.emit(LoadGlobal(state))));
      final body = IrFunction(
        target,
        [entry, normal, caught],
        typeBindings: [TypeBinding.checked(check)],
      );
      final program = IrProgram(
        classes,
        [
          body,
          IrFunction(helper, [implementation]),
        ],
        globals: [state],
      );
      final facts = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(TypeConstant(.string))],
        ),
      ]).facts;
      expect((facts.returnedBy(target).constant as ScalarConstant).value, 9);
      expect(facts.executionTargetsOf(check), {helper});
      expect(facts.definitions, contains(helper));
    },
  );

  test('two inlined activations own independent checked body binders', () {
    final t = parameter('T', .object);
    final target = FunctionTarget(uri, 'matches', .boolean, [
      TypeMetadata.type,
      .object,
    ]);
    final entry = Block(target.parameterTypes);
    final check = entry.emit(
      CheckedTypeArgument(t, entry.parameters.first, {
        t: entry.parameters.first,
      }),
    );
    entry.finish(Return(entry.emit(TypeTest(entry.parameters.last, t))));
    final body = IrFunction(
      target,
      [entry],
      typeBindings: [TypeBinding.checked(check)],
    );
    final root = FunctionTarget(uri, 'twice', .boolean, [.object]);
    final start = Block(root.parameterTypes);
    final integer = start.emit(
      UncheckedCast(TypeConstant(.integer), TypeMetadata.type),
    );
    final string = start.emit(
      UncheckedCast(TypeConstant(.string), TypeMetadata.type),
    );
    final one = start.emit(
      DirectCall(target, [integer, start.parameters.single]),
    );
    final two = start.emit(
      DirectCall(target, [string, start.parameters.single]),
    );
    start.finish(Return(start.emit(Equals(one, two))));
    final source = IrFunction(root, [start]);
    final result = FunctionRewrite(
      source,
      inlined: {
        one: (
          body: body,
          arguments: one.inputs.toList(),
          environment: const {},
          handler: null,
        ),
        two: (
          body: body,
          arguments: two.inputs.toList(),
          environment: const {},
          handler: null,
        ),
      },
    ).run();
    expect(result.typeBindings, hasLength(2));
    expect(
      identical(
        result.typeBindings[0].parameter,
        result.typeBindings[1].parameter,
      ),
      isFalse,
    );
    final program = IrProgram(classes, [result]);
    expect(IrInterpreter(program, {}).run(result, [42]), false);
    expect(IrInterpreter(program, {}).run(result, ['s']), false);
    expect(IrInterpreter(program, {}).run(result, [true]), true);
  });

  test('only complete successful literal evidence can remove a checkpoint', () {
    for (final actual in [ValueType.integer, ValueType.string]) {
      final t = parameter('T');
      final target = FunctionTarget(uri, 'literal', .typeType, []);
      final entry = Block();
      final descriptor = TypeConstant(actual);
      final check = entry.emit(
        CheckedTypeArgument(t, descriptor, {t: descriptor}),
      );
      entry.finish(Return(entry.emit(ReifyType(t))));
      final body = IrFunction(
        target,
        [entry],
        typeBindings: [TypeBinding.checked(check)],
      );
      IrFunction rewrite() => FunctionRewrite(
        body,
        replacements: {check: descriptor},
        discardable: {check},
      ).run();
      if (actual == ValueType.string) {
        expect(rewrite, throwsStateError);
      } else {
        final changed = rewrite();
        expect(changed.typeBindings.single.value, same(descriptor));
        expect(
          changed.blocks
              .expand((b) => b.instructions)
              .whereType<CheckedTypeArgument>(),
          isEmpty,
        );
        final program = IrProgram(classes, [changed]);
        final facts = ProgramFlow(program, [
          (target: target, arguments: const []),
        ]).facts;
        expect(
          (facts.returnedBy(target).constant as TypeConstant).representedType,
          ValueType.integer,
        );
      }
    }
  });
}
