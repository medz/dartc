import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final nullOnLeft in [false, true]) {
    for (final negated in [false, true]) {
      test('null equality preserves state (left=$nullOnLeft, !=$negated)', () {
        final global = GlobalVariable(
          Uri.parse('memory:null-equality'),
          'value',
          ValueType.integer.nullable,
        );
        final root = FunctionTarget(null, 'compare', ValueType.integer.nullable, [
          .object.nullable,
        ]);
        final body = Block(root.parameterTypes);
        body.emit(StoreGlobal(global, const Constant.integer(7)));
        final operand = body.parameters.single;
        final comparison = body.emit(
          Equals(
            nullOnLeft ? const Constant.nullValue() : operand,
            nullOnLeft ? operand : const Constant.nullValue(),
            negated: negated,
          ),
        );
        body.finish(Return(body.emit(LoadGlobal(global))));
        final function = IrFunction(root, [body]);
        final program = IrProgram([], [function], globals: [global]);
        final facts = ProgramFlow(program, [
          (target: root, arguments: [FlowValue.unknown(.object.nullable)]),
        ]).facts;
        expect(facts.hasUnknownCall(comparison), isFalse);
        expect((facts.returnedBy(root).constant as ScalarConstant).value, 7);
        expect(facts.thrownBy(root).exception.isBottom, isTrue);
        expect(facts.valueOf(comparison).constant, isNull);
        for (final graph in [
          program,
          const ProgramSimplification().run(facts),
        ]) {
          final current = graph.implementationOf(root) as IrFunction;
          expect(IrInterpreter(graph, {}).run(current, [null]), 7);
          expect(IrInterpreter(graph, {}).run(current, [42]), 7);
        }
      });
    }
  }

  for (final negated in [false, true]) {
    test('non-null equality retains override writes (!=$negated)', () {
      final type = ClassType(null, 'Equality');
      final global = GlobalVariable(
        Uri.parse('memory:null-equality'),
        'value',
        ValueType.integer.nullable,
      );
      final equals = FunctionTarget(
        null,
        '==',
        .boolean,
        [.object],
        owner: type,
        kind: .method,
      );
      final method = Block(equals.parameterTypes);
      method.emit(StoreGlobal(global, const Constant.integer(9)));
      method.finish(const Return(Constant.boolean(true)));
      final root = FunctionTarget(null, 'compare', ValueType.integer.nullable, [type]);
      final body = Block(root.parameterTypes);
      body.emit(StoreGlobal(global, const Constant.integer(7)));
      final comparison = body.emit(
        Equals(
          body.parameters.single,
          const Constant.integer(42),
          negated: negated,
        ),
      );
      body.finish(Return(body.emit(LoadGlobal(global))));
      final program = IrProgram(
        [
          IrClass(type, [], members: [equals]),
        ],
        [
          IrFunction(equals, [method]),
          IrFunction(root, [body]),
        ],
        globals: [global],
      );
      final facts = ProgramFlow(program, [
        (
          target: root,
          arguments: [FlowValue.constant(ObjectConstant(type, {}))],
        ),
      ]).facts;
      expect(facts.hasUnknownCall(comparison), isFalse);
      expect(facts.definitions, contains(equals));
      expect((facts.returnedBy(root).constant as ScalarConstant).value, 9);
      expect(
        (facts.valueOf(comparison).constant as ScalarConstant).value,
        !negated,
      );
    });
  }
}
