import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/src/lowering/constant_safety.dart';
import 'package:test/test.dart';

import 'fixtures/constant_safety/dependency.dart' as sdk;

void main() {
  test(
    'private symbol comparisons lose identity in analyzer, not the VM',
    () async {
      expect(sdk.b, isFalse);
      expect(sdk.selected, 2);
      await CheckedLibraries.read(
        ['test/lowering/fixtures/constant_safety/dependency.dart'],
        (checked) {
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
        },
      );
    },
  );

  test(
    'checks reachable source dependencies before using folded values',
    () async {
      await CheckedLibraries.read(
        ['test/lowering/fixtures/constant_safety/entry.dart'],
        (checked) {
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
                    safety.check(unit, node, expression: node.initializer);
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
        },
      );
    },
  );
  test('cached inputs do not hide new failures or cache their locations', () async {
    await CheckedLibraries.read(
      ['test/lowering/fixtures/constant_safety/entry.dart'],
      (checked) {
        final unit = checked.libraries.single.units.first;
        final variables = [
          for (final declaration
              in unit.unit.declarations
                  .whereType<TopLevelVariableDeclaration>())
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
          expression: safe.initializer,
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
                expression: expression,
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
      },
    );
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
        CheckedLibraries.read([entry.path], Lowering.lower),
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
    await CheckedLibraries.read([entry.path], Lowering.lower);
  });
  test(
    'super formal defaults follow inherited constant dependencies',
    () async {
      await CheckedLibraries.read(
        ['test/lowering/fixtures/constant_safety/dependency.dart'],
        (checked) {
          final unit = checked.libraries.single.units.single;
          final safety = ConstantSafety();
          for (final name in [
            'SafeInheritedBox',
            'SafeInheritedAgain',
            'UnsafeInheritedBox',
            'UnsafeInheritedAgain',
          ]) {
            final element = unit.libraryElement.getClass(name)!;
            final parameter =
                element.constructors.single.formalParameters.single;
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
        },
      );
    },
  );
}
