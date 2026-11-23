import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

import '../hir/support.dart';
import 'support.dart';

void main() {
  /// Runs a program exiting with 1 if what [build] adds holds.
  int? runsTo(HirValue Function(HirBlock block) build) => runLowered(
    body((block) {
      final condition = build(block);
      final yes = HirBlock(), no = HirBlock();
      yes.end(HirExit(yes.add(HirConst(1))));
      no.end(HirExit(no.add(HirConst(0))));
      return HirBranch(condition, HirEdge(yes), HirEdge(no));
    }),
  );

  test('int operators follow Dart', () {
    for (final a in integers) {
      for (final b in integers) {
        for (final operator in HirIntOperator.values) {
          final expected = integerResult(operator, a, b);
          if (expected == null) continue;
          final module = body((block) {
            final l = block.add(HirConst(a)), r = block.add(HirConst(b));
            return HirExit(block.add(HirIntBinary(operator, l, r)));
          });
          expect(
            runLowered(module),
            expected,
            reason: '$a ${operator.symbol} $b',
          );
        }
      }
    }
  });

  test('double operators follow Dart', () {
    for (final a in doubles) {
      for (final b in doubles) {
        for (final operator in HirFloatOperator.values) {
          final expected = doubleResult(operator, a, b);
          final result = runsTo((block) {
            final l = block.add(HirConst(a)), r = block.add(HirConst(b));
            final found = block.add(HirFloatBinary(operator, l, r));
            return sameDouble(block, found, expected);
          });
          expect(result, 1, reason: '$a ${operator.symbol} $b');
        }
      }
    }
  });

  test('comparisons follow Dart', () {
    for (final List<num> values in [integers, doubles]) {
      for (final a in values) {
        for (final b in values) {
          for (final relation in HirRelation.values) {
            final result = runsTo((block) {
              final l = block.add(HirConst(a)), r = block.add(HirConst(b));
              return block.add(HirCompare(relation, l, r));
            });
            final expected = relationResult(relation, a, b) ? 1 : 0;
            expect(result, expected, reason: '$a ${relation.symbol} $b');
          }
        }
      }
    }
  });

  test('bool operators follow Dart', () {
    for (final a in [true, false]) {
      HirValue constant(HirBlock block, bool value) =>
          block.add(HirConst(value));
      expect(
        runsTo((block) => block.add(HirUnary(.not, constant(block, a)))),
        a ? 0 : 1,
      );
      for (final b in [true, false]) {
        for (final (operator, expected) in [
          (HirBoolOperator.and, a & b),
          (HirBoolOperator.or, a | b),
          (HirBoolOperator.xor, a ^ b),
        ]) {
          final result = runsTo((block) {
            final l = constant(block, a), r = constant(block, b);
            return block.add(HirBoolBinary(operator, l, r));
          });
          expect(result, expected ? 1 : 0);
        }
        for (final (relation, expected) in [
          (HirRelation.equal, a == b),
          (HirRelation.notEqual, a != b),
        ]) {
          final result = runsTo((block) {
            final l = constant(block, a), r = constant(block, b);
            return block.add(HirCompare(relation, l, r));
          });
          expect(result, expected ? 1 : 0);
        }
      }
    }
  });

  test('prefix operators follow Dart', () {
    for (final value in integers) {
      for (final (operator, expected) in [
        (HirUnaryOperator.negateInt, -value),
        (HirUnaryOperator.complement, ~value),
      ]) {
        final module = body((block) {
          final operand = block.add(HirConst(value));
          return HirExit(block.add(HirUnary(operator, operand)));
        });
        expect(runLowered(module), expected);
      }
      final converted = runsTo((block) {
        final operand = block.add(HirConst(value));
        final found = block.add(HirUnary(.intToFloat, operand));
        return sameDouble(block, found, value.toDouble());
      });
      expect(converted, 1);
    }
    for (final value in doubles) {
      final negated = runsTo((block) {
        final operand = block.add(HirConst(value));
        final found = block.add(HirUnary(.negateFloat, operand));
        return sameDouble(block, found, -value);
      });
      expect(negated, 1);
    }
  });

  test('calls and loops pass values', () {
    expect(runLowered(loopingCalls()), 34);
  });

  test('a program that returns ends with 0', () {
    expect(runLowered(body((_) => HirReturn())), isNull);
  });

  test('only the system functions used are imported', () {
    List<String> imports(HirModule module) => [
      for (final external in lowerProgram(module).externals) external.name,
    ];
    expect(imports(body((_) => HirReturn())), isEmpty);
    expect(imports(body((block) => HirExit(block.add(HirConst(1))))), ['exit']);
    final modulo = body((block) {
      final one = block.add(HirConst(1.0));
      block.add(HirFloatBinary(.modulo, one, one));
      return HirReturn();
    });
    expect(imports(modulo), ['fmod']);
  });

  test('functions of one name stay apart', () {
    HirFunction named(String name, int code) {
      final block = HirBlock();
      block.end(HirReturn(block.add(HirConst(code))));
      return HirFunction(name, const [], .integer)..define([block]);
    }

    final first = named('exit', 5), second = named('exit', 6);
    final module = body((block) {
      final a = block.add(HirCall(first, [])),
          b = block.add(HirCall(second, []));
      return HirExit(block.add(HirIntBinary(.multiply, a, b)));
    }, [first, second]);
    expect(runLowered(module), 30);
  });

  test('blocks may be listed in any order', () {
    final entry = HirBlock(), middle = HirBlock(), last = HirBlock();
    entry.end(HirJump(HirEdge(middle)));
    final value = middle.add(HirConst(9));
    middle.end(HirJump(HirEdge(last)));
    last.end(HirExit(value));
    final main = HirFunction('main', const [])..define([entry, last, middle]);
    expect(runLowered(HirModule(main, [main])), 9);
  });

  test('refuses an invalid program', () {
    final main = HirFunction('main', const [])..define([HirBlock()]);
    expect(
      () => lowerProgram(HirModule(main, [main])),
      throwsA(isA<HirError>()),
    );
    expect(LirInterpreter(lowerProgram(body((_) => HirReturn()))), isNotNull);
  });
}
