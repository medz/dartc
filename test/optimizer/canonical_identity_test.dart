import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:identity-test');
  final base = ClassType(uri, 'Base'),
      marker = ClassType(uri, 'Marker', superclass: base);
  final candidate = ObjectConstant(marker, {});
  final pointer = FfiTypes.pointer.instantiate([FfiTypes.voidType]);
  for (final bound in <ValueType>[pointer, base, ValueType.object, marker]) {
    for (final reverse in [false, true]) {
      test(
        'a canonical object compared to a ${bound.dartName} bound (reversed=$reverse)',
        () {
          final root = FunctionTarget(uri, 'root', .boolean, [
            ValueType.object,
          ]);
          final b = Block(root.parameterTypes), p = b.parameters.single;
          final check = b.emit(
            reverse ? Identical(candidate, p) : Identical(p, candidate),
          );
          b.finish(Return(check));
          final flow = ProgramFlow(
            IrProgram(
              [IrClass(base, []), IrClass(marker, [])],
              [
                IrFunction(root, [b]),
              ],
            ),
            [
              (target: root, arguments: [FlowValue.unknown(bound)]),
            ],
          ).facts;
          if (bound == pointer) {
            expect(flow.valueOf(check).constant, const Constant.boolean(false));
          } else {
            expect(flow.valueOf(check).constant, isNull);
          }
        },
      );
    }
  }
  test('a merged canonical value and unrelated bound still allow identity', () {
    final root = FunctionTarget(uri, 'mixed', .boolean, [ValueType.object]);
    final b = Block(root.parameterTypes);
    final id = b.emit(Identical(b.parameters.single, candidate));
    b.finish(Return(id));
    final facts = ProgramFlow(
      IrProgram(
        [IrClass(base, []), IrClass(marker, [])],
        [
          IrFunction(root, [b]),
        ],
      ),
      [
        (
          target: root,
          arguments: [
            FlowValue.constant(candidate).join(FlowValue.unknown(pointer)),
          ],
        ),
      ],
    ).facts;
    expect(facts.valueOf(id).constant, isNull);
  });
  final parameter = TypeParameterType('T')
    ..initializeBound(ValueType.object.nullable)
    ..initializeDefaultType(ValueType.dynamicType);
  final box = ClassType(uri, 'Box', typeParameters: [parameter]);
  final proof = PromotedType(ValueType.object, ValueType.integer);
  for (final negative in [false, true]) {
    ValueType arg(ValueType a) =>
        negative ? FunctionType(ValueType.voidType, [a]) : a;
    final annotated = box.instantiate([arg(proof)]),
        lexical = box.instantiate([arg(ValueType.object)]);
    for (final candidateHasProof in [false, true]) {
      test(
        'canonical identity survives reification (contravariant=$negative, annotated constant=$candidateHasProof)',
        () {
          final candidate = ObjectConstant(
            candidateHasProof ? annotated : lexical,
            {},
          );
          final bound = candidateHasProof ? lexical : annotated;
          final lexicalConstant = ObjectConstant(lexical, {});
          expect(annotated.reify(), lexical);
          expect(candidate.structuralKey, lexicalConstant.structuralKey);
          final root = FunctionTarget(uri, 'same', .boolean, [
            ValueType.dynamicType,
          ]);
          final b = Block(root.parameterTypes);
          final cmp = b.emit(Identical(b.parameters.single, candidate));
          b.finish(Return(cmp));
          final selected = FunctionTarget(
            uri,
            'selected',
            ValueType.object,
            [],
          );
          final c = Block()..finish(Return(lexicalConstant));
          final program = IrProgram(
            [IrClass(box, [])],
            [
              IrFunction(root, [b]),
              IrFunction(selected, [c]),
            ],
          );
          final entries = [
            (target: root, arguments: [FlowValue.unknown(bound)]),
            (target: selected, arguments: <FlowValue>[]),
          ];
          bool invoke(IrProgram p) {
            final run = IrInterpreter(p, {});
            final arg = run.run(p.implementationOf(selected) as IrFunction, []);
            return run.run(p.implementationOf(root) as IrFunction, [arg])
                as bool;
          }

          final optimized = ProgramOptimizer(const [ProgramSimplification()])
              .run(program, entries)
              .program;
          final originalResult = invoke(program),
              optimizedResult = invoke(optimized);
          expect(originalResult, isTrue);
          expect(optimizedResult, originalResult);
          final facts = ProgramFlow(program, [
            (target: root, arguments: [FlowValue.unknown(bound)]),
          ]).facts;
          expect(facts.valueOf(cmp).constant, isNull);
        },
      );
    }
  }
}
