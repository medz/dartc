import 'dart:ffi' show Int64;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import 'frozen_predicate_test.dart' show Layout;

void main() {
  for (final choice in [true, false, null]) {
    for (final negated in [false, true]) {
      test(
        'saved is-test of a possible scalar carrier follows its type while reading current bytes (choice=$choice, negated=$negated)',
        () {
          final uri = Uri.parse('memory:type-carrier');
          final root = FunctionTarget(uri, 'root', .integer, [.boolean]);
          final saved = GlobalVariable(uri, 'saved', .object, isLate: true);
          final entry = Block(root.parameterTypes),
              merged = Block([ValueType.object]),
              later = Block(),
              number = Block(),
              other = Block();
          final box = entry.emit(MaterializeValue(const Constant.integer(42)));
          final payload = entry.emit(
            IntBinary(
              .add,
              entry.emit(ReferenceAddress(box)),
              const Constant.integer(ObjectHeader.fieldsOffset),
            ),
          );
          entry.finish(
            Branch(
              entry.parameters.single,
              Jump(merged, [box]),
              Jump(merged, [const Constant.string('s')]),
            ),
          );
          final x = merged.parameters.single;
          merged.emit(StoreGlobal(saved, x));
          final check = merged.emit(
            TypeTest(x, ValueType.integer, negated: negated),
          );
          merged.finish(Jump(later));
          later.emit(
            StoreNative(
              payload,
              NativeScalarType(Int64),
              const Constant.integer(9),
            ),
          );
          later.finish(
            Branch(
              check,
              Jump(negated ? other : number),
              Jump(negated ? number : other),
            ),
          );
          final read = number.emit(LoadGlobal(saved));
          final numberResult = number.emit(
            ProjectValue(
              number.emit(TypeCast(read, ValueType.integer)),
              ExecutionShape.word,
            ),
          );
          number.finish(Return(numberResult));
          final otherResult = other.emit(LoadGlobal(saved));
          other.finish(const Return(Constant.integer(-1)));
          final graph = IrProgram(
            [IrClass(ValueType.integer, [])],
            [
              IrFunction(root, [entry, merged, later, number, other]),
            ],
            globals: [saved],
          );
          final facts = ProgramFlow(graph, [
            (
              target: root,
              arguments: [
                choice == null
                    ? FlowValue.unknown(.boolean)
                    : FlowValue.constant(Constant.boolean(choice)),
              ],
            ),
          ], memoryLayout: Layout()).facts;
          expect(facts.reachesBlock(number), choice != false);
          expect(facts.reachesBlock(other), choice != true);
          if (choice != false) {
            print(
              'choice=$choice isNot=$negated backings=${facts.valueOf(read).managedBackings.length} range=[${facts.valueOf(numberResult).integers?.lower},${facts.valueOf(numberResult).integers?.upper}]',
            );
            expect(facts.valueOf(numberResult).integers?.contains(9), isTrue);
            if (choice == true) {
              expect(facts.valueOf(numberResult).integers?.constant, 9);
            }
          }
          if (choice != true) {
            expect(
              (facts.valueOf(otherResult).constant as ScalarConstant?)?.value,
              's',
            );
          }
        },
      );
    }
  }
}
