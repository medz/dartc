import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/src/frontend/analyzer_metadata.dart';
import 'package:dartc/src/frontend/constant_evaluation.dart';
import 'package:dartc/src/frontend/constant_safety.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/constant_safety/dependency.dart' as sdk;

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
  test(
    'private symbol comparisons lose identity in analyzer, not the VM',
    () async {
      expect(sdk.b, isFalse);
      expect(sdk.selected, 2);
      await AnalysisSession([
        'test/frontend/lowering/fixtures/constant_safety/dependency.dart',
      ]).use((checked) {
        final unit = checked.libraries.single.units.single;
        final variables = [
          for (final declaration
              in unit.unit.declarations
                  .whereType<TopLevelVariableDeclaration>())
            ...declaration.variables.variables,
        ];
        final b = variables
            .singleWhere((v) => v.name.lexeme == 'b')
            .declaredFragment!
            .element;
        expect(b.computeConstantValue()!.toBoolValue(), isTrue);
        final selected = variables
            .singleWhere((v) => v.name.lexeme == 'selected')
            .declaredFragment!
            .element;
        expect(selected.computeConstantValue()!.toIntValue(), 1);
      });
    },
  );

  test(
    'checks reachable source dependencies before using folded values',
    () async {
      await AnalysisSession([
        'test/frontend/lowering/fixtures/constant_safety/entry.dart',
      ]).use((checked) {
        final unit = checked.libraries.single.units.first;
        final safety = ConstantSafety();
        for (final declaration
            in unit.unit.declarations
                .whereType<TopLevelVariableDeclaration>()) {
          for (final node in declaration.variables.variables) {
            final variable = node.declaredFragment!.element;
            for (var repetition = 0; repetition < 2; repetition++) {
              void checkVariable() =>
                  safety.check(unit, node, variable: variable);
              void checkExpression() =>
                  safety.check(unit, node, syntax: node.initializer);
              for (final check in [checkVariable, checkExpression]) {
                if (node.name.lexeme.startsWith('unsafe')) {
                  expect(
                    check,
                    throwsA(
                      isA<UnsupportedError>()
                          .having(
                            (e) => e.message,
                            'source',
                            contains('entry.dart:'),
                          )
                          .having(
                            (e) => e.message,
                            'reason',
                            contains('private Symbol literal'),
                          ),
                    ),
                    reason: '${node.name.lexeme}, repetition $repetition',
                  );
                } else {
                  expect(check, returnsNormally, reason: node.name.lexeme);
                }
              }
            }
          }
        }
      });
    },
  );
  test('repeated checks retain failures and their use-site locations', () async {
    await AnalysisSession([
      'test/frontend/lowering/fixtures/constant_safety/entry.dart',
    ]).use((checked) {
      final unit = checked.libraries.single.units.first;
      final variables = [
        for (final declaration
            in unit.unit.declarations.whereType<TopLevelVariableDeclaration>())
          ...declaration.variables.variables,
      ];
      final safe = variables.singleWhere(
        (v) => v.name.lexeme == 'safeUnrelated',
      );
      final unsafe = variables.singleWhere(
        (v) => v.name.lexeme == 'unsafeMultihop',
      );
      final safety = ConstantSafety();
      safety.check(
        unit,
        safe,
        variable: safe.declaredFragment!.element,
        syntax: safe.initializer,
      );
      for (final site in [safe, unsafe, safe]) {
        final location = unit.lineInfo.getLocation(site.offset);
        for (final (variable, expression) in [
          (safe.declaredFragment!.element, unsafe.initializer),
          (unsafe.declaredFragment!.element, safe.initializer),
        ]) {
          expect(
            () => safety.check(
              unit,
              site,
              variable: variable,
              syntax: expression,
            ),
            throwsA(
              isA<UnsupportedError>()
                  .having(
                    (error) => error.message,
                    'outer use site',
                    startsWith(
                      '${unit.uri}:${location.lineNumber}:${location.columnNumber}:',
                    ),
                  )
                  .having(
                    (error) => error.message,
                    'reason',
                    contains('private Symbol literal'),
                  ),
            ),
          );
        }
      }
    });
  });
  test('lowering rejects folded scalar dependencies at the use site', () async {
    final directory = Directory.systemTemp.createTempSync('constant-safety-');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/dependency.dart').writeAsStringSync(
      "const a = #_p; const b = a == Symbol('_p'); const selected = b ? 1 : 2;",
    );
    final entry = File('${directory.path}/entry.dart');
    for (final expression in [
      'd.selected',
      'const [d.selected]',
      'const (d.selected,)',
    ]) {
      entry.writeAsStringSync(
        "import 'dependency.dart' as d; Object f() => $expression;",
      );
      await expectLater(
        AnalysisSession([entry.path])
            .use((input) async => (await Lowering().lower(input)).program),
        throwsA(
          isA<UnsupportedError>()
              .having((e) => e.message, 'use site', contains('entry.dart:1:'))
              .having(
                (e) => e.message,
                'reason',
                contains('private Symbol literal'),
              ),
        ),
      );
    }
    entry.writeAsStringSync("import 'dependency.dart' as d; int f() => 42;");
    await AnalysisSession([entry.path])
        .use((input) async => (await Lowering().lower(input)).program);
  });
  test(
    'super formal defaults follow inherited constant dependencies',
    () async {
      await AnalysisSession([
        'test/frontend/lowering/fixtures/constant_safety/dependency.dart',
      ]).use((checked) {
        final unit = checked.libraries.single.units.single;
        final safety = ConstantSafety();
        for (final name in [
          'SafeInheritedBox',
          'SafeInheritedAgain',
          'UnsafeInheritedBox',
          'UnsafeInheritedAgain',
        ]) {
          final element = unit.libraryElement.getClass(name)!;
          final parameter = element.constructors.single.formalParameters.single;
          expect(parameter.hasDefaultValue, isTrue);
          expect(parameter.constantInitializer, isNull);
          void check() => safety.check(unit, unit.unit, variable: parameter);
          if (name.startsWith('Unsafe')) {
            expect(
              check,
              throwsA(
                isA<UnsupportedError>().having(
                  (error) => error.message,
                  'reason',
                  contains('private Symbol literal'),
                ),
              ),
              reason: name,
            );
          } else {
            expect(check, returnsNormally, reason: name);
          }
        }
      });
    },
  );
}
