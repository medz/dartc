import 'package:dartc/ir.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/checked_casts.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:dartc/src/codegen/heap_plan.dart';
import 'package:dartc/src/codegen/indirect_invocation.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/codegen/callable_implementations.dart';
import 'package:dartc/src/codegen/callable_lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'dynamic carrier call keeps one indirect edge and its exception handler',
    () {
      final state = GlobalVariable(
        Uri.parse('memory:dynamic-carrier'),
        'state',
        .integer,
        isLate: true,
      );
      final sources = [
        FunctionTarget(null, 'returns', .integer, []),
        FunctionTarget(null, 'throws', .integer, []),
      ];
      final bodies = [
        for (final (index, source) in sources.indexed)
          () {
            final block = Block();
            block.emit(
              StoreGlobal(state, Constant.integer(index == 0 ? 9 : 73)),
            );
            block.finish(
              index == 0
                  ? const Return(Constant.integer(42))
                  : Throw(const Constant.integer(7)),
            );
            return IrFunction(source, [block]);
          }(),
      ];
      final failure = FunctionTarget(null, 'missing', .dynamicType, [
        .dynamicType,
      ]);
      final failed = Block(failure.parameterTypes)
        ..finish(Throw(const Constant.integer(-1)));
      final root = FunctionTarget(null, 'dynamicInvoke', .integer, [.boolean]);
      final entry = Block(root.parameterTypes),
          yes = Block(),
          no = Block(),
          join = Block([sources.first.signature]),
          normal = Block(),
          caught = Block();
      entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
      yes.finish(Jump(join, [FunctionConstant(sources.first)]));
      no.finish(Jump(join, [FunctionConstant(sources.last)]));
      final call = DynamicDispatch(
        join.parameters.single,
        (kind: FunctionKind.method, name: 'call', privateScope: null),
        const [],
        const {},
        const [],
        failure,
      );
      join.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)));
      normal.finish(Return(normal.emit(LoadGlobal(state))));
      caught.finish(Return(caught.emit(LoadGlobal(state))));
      final original = IrProgram(
        [],
        [
          ...bodies,
          IrFunction(failure, [failed]),
          IrFunction(root, [entry, yes, no, join, normal, caught]),
        ],
        globals: [state],
      );
      final owner = CallableImplementations();
      final program = CallableLowering(owner)
          .run(ProgramFlow(original, const [], openEntries: [root]).facts);
      final facts = ProgramFlow(program, const [], openEntries: [root]).facts;
      final body = program.implementationOf(root)! as IrFunction;
      expect(IrInterpreter(program, {}).run(body, [true]), 9);
      expect(IrInterpreter(program, {}).run(body, [false]), 73);
      for (final architecture in [Architecture.arm64, Architecture.x64]) {
        final closures = ClosureStorage(
          program.functions,
          storageDeclarations: program.classes,
          callableImplementations: owner,
        );
        final layouts = ProgramLayout(
          [...program.classes, ...closures.classes],
          closureStorage: closures,
          nativeLayout: NativeLayout(Target(.linux, architecture)),
        );
        final selected = FunctionRepresentation(
          body,
          layouts,
          CheckedCasts(),
          MemberCalls(program, facts.definitions, callTypes: facts),
          HeapPlan(),
        );
        final indirect = selected.instructions.values
            .expand((ops) => ops)
            .whereType<IndirectInvocation>()
            .single;
        final callBlock = selected.instructions.entries.singleWhere(
          (entry) => entry.value.contains(indirect),
        ).key;
        final edge = selected.ends[callBlock]! as Invoke;
        expect(edge.operation, same(indirect.origin));
        expect(edge.onThrow, isNotNull);
        expect(edge.onReturn, isNotNull);
        expect(
          selected.indirectInvocations[indirect],
          owner.functions.map((body) => body.target).toSet(),
        );
      }
    },
  );

  for (final mode in ['valid', 'type', 'arity']) {
    test(
      'dynamic callable $mode executes its real entry and failure effects',
      () {
        final state = GlobalVariable(
          Uri.parse('memory:dynamic-calls'),
          'state',
          .integer,
          isLate: true,
        );
        final source = FunctionTarget(null, 'source', .integer, [.integer]);
        final body = Block(source.parameterTypes);
        body.emit(StoreGlobal(state, const Constant.integer(9)));
        body.finish(Return(body.parameters.single));
        final args = mode == 'arity'
            ? <Value>[]
            : <Value>[
                mode == 'type'
                    ? Constant.string('bad')
                    : const Constant.integer(42),
              ];
        final failure = FunctionTarget(null, 'failure', .dynamicType, [
          for (var i = 0; i <= args.length; i++) ValueType.dynamicType,
        ]);
        final failing = Block(failure.parameterTypes);
        failing.emit(StoreGlobal(state, const Constant.integer(73)));
        failing.finish(Throw(const Constant.integer(7)));
        final root = FunctionTarget(null, 'root', .integer, []);
        final entry = Block(), normal = Block(), caught = Block();
        entry.emit(StoreGlobal(state, const Constant.integer(1)));
        final call = DynamicDispatch(
          FunctionConstant(source),
          (kind: FunctionKind.method, name: 'call', privateScope: null),
          args,
          const {},
          const [],
          failure,
        );
        entry.finish(
          Invoke(call, onReturn: Jump(normal), onThrow: Jump(caught)),
        );
        normal.finish(Return(normal.emit(LoadGlobal(state))));
        caught.finish(Return(caught.emit(LoadGlobal(state))));
        final original = IrProgram(
          [],
          [
            IrFunction(root, [entry, normal, caught]),
            IrFunction(source, [body]),
            IrFunction(failure, [failing]),
          ],
          globals: [state],
        );
        final roots = [(target: root, arguments: <FlowValue>[])];
        final owner = CallableImplementations();
        final lowered = CallableLowering(owner)
            .run(ProgramFlow(original, roots).facts);
        expect(owner.functions, hasLength(1));
        final optimized = ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramCallSpecialization(),
          ProgramStorageElimination(),
          DirectCallInlining(),
        ]).run(lowered, roots);
        final expected = switch (mode) {
          'valid' => 9,
          'arity' => 73,
          _ => 1,
        };
        for (final program in [original, lowered, optimized.program]) {
          expect(
            IrInterpreter(
              program,
              {},
            ).run(program.implementationOf(root) as IrFunction, []),
            expected,
          );
        }
        expect(
          (optimized.returnedBy(root).constant as ScalarConstant).value,
          expected,
        );
      },
    );
  }
}
