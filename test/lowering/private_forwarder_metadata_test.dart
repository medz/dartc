import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/src/lowering/analyzer_metadata.dart';
import 'package:dartc/src/lowering/bindings.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';

void main() {
  test(
    'real replacement uses combined defaults and named covariance slots',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-private-meta-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final imported = File('${directory.path}/imported.dart')
        ..writeAsStringSync('''
class Base {
  int _f({covariant int z = 1, int a = 2}) => 0;
}
abstract class Contract { int _f({num a = 20, num z = 30}); }
abstract class Other { num _f({num z = 30, num a = 20}); }
''');
      final entry = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
import 'imported.dart';
class Replacement extends Base implements Contract, Other {}
''');
      await AnalysisSession([entry.path, imported.path]).use((input) {
        final unit = input.libraries
            .expand((l) => l.units)
            .firstWhere(
              (u) => u.unit.declarations.whereType<ast.ClassDeclaration>().any(
                (d) => d.declaredFragment!.element.name == 'Replacement',
              ),
            );
        final declaration = unit.unit.declarations
            .whereType<ast.ClassDeclaration>()
            .single;
        final element = declaration.declaredFragment!.element;
        final candidate = noSuchMethodForwarderCandidates(element)
            .singleWhere((c) => c.member.name == '_f');
        expect(candidate.overridesConcrete, isTrue);
        final parameters = candidate.member.formalParameters;
        expect(
          parameters.map((p) => p.type.getDisplayString()),
          everyElement('num'),
        );
        expect(
          parameters
              .singleWhere((p) => p.name == 'a')
              .computeConstantValue()!
              .toIntValue(),
          20,
        );
        expect(
          parameters
              .singleWhere((p) => p.name == 'z')
              .computeConstantValue()!
              .toIntValue(),
          30,
        );
        expect({
          ...candidate.additionalCovariance,
          for (final (i, parameter) in parameters.indexed)
            if (parameter.isCovariant) i,
        }, contains(parameters.indexWhere((p) => p.name == 'z')));

        final bindings = Bindings();
        for (final library in input.libraries) {
          for (final source in library.units) {
            for (final declaration
                in source.unit.declarations.whereType<ast.ClassDeclaration>()) {
              bindings.registerClass(
                declaration.declaredFragment!.element,
                source,
                declaration,
              );
            }
          }
        }
        final forwarder = bindings.forwarders(element).single;
        expect(forwarder.selector.privateLibrary, imported.uri);
        expect(forwarder.library, entry.uri);
        expect(forwarder.signature.parameters, everyElement(ValueType.number));
        final z = forwarder.signature.named['z']!.slot;
        final a = forwarder.signature.named['a']!.slot;
        expect(forwarder.covariantParameters, contains(z));
        expect((bindings.defaults(forwarder)[a] as ScalarConstant).value, 20);
        expect((bindings.defaults(forwarder)[z] as ScalarConstant).value, 30);
        final factory = bindings.noSuchMethodBodyTarget(
          element,
          forwarder,
          unit,
          declaration,
        );
        expect(factory.library, Uri.parse('dart:core'));
        expect(factory.owner, ValueType.noSuchMethodError);
        expect(factory.kind, FunctionKind.factory);
        expect(factory.name, 'withInvocation');
        expect(factory.redirect, isNull);
        expect(factory.typeParameters, isEmpty);
        expect(bindings.defaults(factory), isEmpty);
        expect(
          factory,
          same(
            bindings.target(
              element.library.typeProvider.objectElement.library
                  .getClass('NoSuchMethodError')!
                  .getNamedConstructor('withInvocation')!,
              unit,
              declaration,
            ),
          ),
        );
        expect(factory.returnType, ValueType.noSuchMethodError);
        expect(factory.signature.parameters, [
          ValueType.object.nullable,
          CoreTypes.invocation,
        ]);
      });
    },
  );

  test(
    'zero-parameter foreign-private getter replacement has mutable metadata',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-private-getter-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final imported = File('${directory.path}/imported.dart')
        ..writeAsStringSync('''
class R { Object? get _g => 7; }
abstract class I { int get _g; }
int read(I value) => value._g;
''');
      final entry = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
import 'imported.dart';
class B extends R implements I {}
int invoke() => read(B());
''');
      final program = await AnalysisSession([entry.path, imported.path])
          .use((input) {
            final element = input.libraries
                .expand((l) => l.units)
                .expand(
                  (u) => u.unit.declarations.whereType<ast.ClassDeclaration>(),
                )
                .singleWhere((d) => d.declaredFragment!.element.name == 'B')
                .declaredFragment!
                .element;
            final candidate = noSuchMethodForwarderCandidates(element)
                .singleWhere((c) => c.member.name == '_g');
            expect(candidate.overridesConcrete, isTrue);
            expect(candidate.member.formalParameters, isEmpty);
            expect(candidate.member.returnType.getDisplayString(), 'int');
            expect(candidate.additionalCovariance, isEmpty);
            return Lowering().lower(input).program;
          });
      final invoke = program.functions.singleWhere(
        (f) => f.target.name == 'invoke',
      );
      expect(
        () => FixtureRunner(program, {}).run(invoke, []),
        throwsNoSuchMethodError,
      );
    },
  );
}
