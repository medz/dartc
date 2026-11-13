import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/src/frontend/analyzer_metadata.dart';
import 'package:dartc/src/frontend/constant_evaluation.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';

void main() {
  test('numeric constant dependencies retain exact values', () async {
    await AnalysisSession([
      'test/frontend/lowering/fixtures/constant_safety/numeric.dart',
    ]).use((checked) {
      final unit = checked.libraries.single.units.single;
      final constants = ConstantEvaluation();
      const expected = {
        'integer': 9007199254740993,
        'floating': 9007199254740992.0,
        'equal': false,
        'unequal': true,
        'less': true,
        'lessEqual': false,
        'greater': true,
        'greaterEqual': false,
        'selected': 2,
        'exact': true,
        'largeDifferent': true,
        'zeros': true,
        'signedDoubleZeros': true,
        'distinctZeros': false,
        'mixedIdentity': false,
        'reversedIdentity': false,
        'roundedIdentity': false,
        'zeroIdentity': false,
        'integerIdentity': true,
        'doubleIdentity': true,
        'contextualDouble': 1.0,
        'contextualIdentity': true,
        'nan': false,
        'strings': true,
        'maximumLess': true,
        'reverseMaximum': true,
        'minimumEqual': true,
        'zeroOrders': true,
        'fractional': true,
        'infinite': true,
        'nanRelations': true,
      };
      for (final declaration
          in unit.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
        for (final variable in declaration.variables.variables) {
          final value = constants.variable(
            variable.declaredFragment!.element,
            unit,
            variable,
          );
          final name = variable.name.lexeme;
          if (name == 'nested' || name == 'literalNested') {
            expect(value!.getField('value')!.toBoolValue(), false);
          } else if (name == 'abbreviated') {
            expect(value!.getField('value')!.toBoolValue(), true);
          } else if (name == 'record') {
            expect(
              value!.toRecordValue()!.positional.single.toBoolValue(),
              false,
            );
            expect(
              value.toRecordValue()!.named['greater']!.toBoolValue(),
              true,
            );
          } else if (name == 'values') {
            expect(value!.toListValue()!.map((v) => v.toIntValue()), [2, 3]);
          } else if (name == 'mapping') {
            expect(value!.toMapValue()!.values.single!.toBoolValue(), true);
          } else {
            expect(expected, contains(name));
            expect(
              value!.toBoolValue() ??
                  value.toIntValue() ??
                  value.toDoubleValue(),
              expected[name],
              reason: name,
            );
          }
        }
      }
    });
  });

  test(
    'constant expressions and constructor arguments reach IR unchanged',
    () async {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/constant_safety/numeric.dart',
      ]).use(Lowering().lower);
      final runner = IrInterpreter(result.program, {});
      for (final (name, expected) in [
        ('constructedArgument', false),
        ('recordExpression', true),
        ('listExpression', true),
        ('mapExpression', true),
      ]) {
        final function = result.program.functions.singleWhere(
          (f) => f.target.name == name,
        );
        expect(runner.run(function, []), expected, reason: name);
      }
    },
  );
  test(
    'constructor initializers and defaults use exact numeric comparisons',
    () async {
      await AnalysisSession([
        'test/frontend/lowering/fixtures/constant_safety/numeric_constructor.dart',
      ]).use((checked) {
        final unit = checked.libraries.single.units.single;
        final constants = ConstantEvaluation();
        for (final declaration
            in unit.unit.declarations
                .whereType<TopLevelVariableDeclaration>()) {
          for (final variable in declaration.variables.variables) {
            final value = constants.variable(
              variable.declaredFragment!.element,
              unit,
              variable,
            )!;
            if (variable.name.lexeme == 'sharedDependency') {
              final fields = value.toRecordValue()!.positional;
              expect(fields.first.toBoolValue(), false);
              expect(fields.last.getField('result')!.toBoolValue(), true);
            } else {
              expect(
                value.toBoolValue() ??
                    (value.getField('result') ??
                            constantSuperclass(value)?.getField('result'))!
                        .toBoolValue(),
                !{
                  'defaultValue',
                  'inherited',
                  'factoryDefault',
                }.contains(variable.name.lexeme),
                reason: variable.name.lexeme,
              );
            }
          }
        }
      });
    },
  );
  test('a rounded comparison cannot hide a failing const assertion', () async {
    for (final enabled in [false, true]) {
      await expectLater(
        AnalysisSession([
          'test/frontend/lowering/fixtures/constant_safety/numeric_assertion.dart',
        ]).use(Lowering(enableAssertions: enabled).lower),
        throwsA(
          isA<FormatException>()
              .having(
                (e) => e.message,
                'assertion',
                contains('The numeric values must be equal.'),
              )
              .having(
                (e) => e.message,
                'source',
                contains('numeric_assertion.dart'),
              ),
        ),
      );
    }
  });
  for (final kind in ['parameter', 'field', 'factory']) {
    test('exact constructor values retain $kind type checks', () async {
      await expectLater(
        AnalysisSession([
          'test/frontend/lowering/fixtures/constant_safety/numeric_${kind}_error.dart',
        ]).use((_) => fail('An invalid constant passed analysis.')),
        throwsFormatException,
      );
    });
  }
  for (final kind in ['assertion', 'type', 'duplicate']) {
    test('native numeric identity retains $kind checks', () async {
      await expectLater(
        AnalysisSession([
          'test/frontend/lowering/fixtures/constant_safety/numeric_identity_$kind.dart',
        ]).use(
          (_) =>
              fail('An invalid identity-dependent constant passed analysis.'),
        ),
        throwsFormatException,
      );
    });
  }
}
