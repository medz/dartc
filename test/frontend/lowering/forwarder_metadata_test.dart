import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/src/frontend/analyzer_metadata.dart';
import 'package:dartc/src/frontend/lowering/bindings.dart';
import 'package:test/test.dart';

void main() {
  test(
    'selected forwarder binders retain exact identity and transported defaults',
    () async {
      await AnalysisSession([
        'test/frontend/lowering/fixtures/nosuchmethod_unsupported.dart',
        'test/frontend/lowering/fixtures/nosuchmethod_unsupported_private.dart',
      ]).use((input) {
        final unit = input.libraries
            .expand((library) => library.units)
            .firstWhere(
              (unit) =>
                  unit.unit.declarations.whereType<ast.ClassDeclaration>().any(
                    (declaration) =>
                        declaration.declaredFragment!.element.name ==
                        'Forwarded',
                  ),
            );
        final declaration = unit.unit.declarations
            .whereType<ast.ClassDeclaration>()
            .singleWhere(
              (declaration) =>
                  declaration.declaredFragment!.element.name == 'Forwarded',
            );
        final element = declaration.declaredFragment!.element;
        final selected = noSuchMethodForwarderCandidates(element)
            .singleWhere((candidate) => candidate.member.name == 'method')
            .member;
        final binder = selected.typeParameters.single;
        expect(identical(binder.baseElement, binder), isTrue);
        expect(identical(binder, selected.type.typeParameters.single), isFalse);
        expect(typeParameterDefault(binder), isNull);
        final templates = executableTypeParameterDefaults(selected);
        expect(templates.single!.getDisplayString(), 'num');

        final bindings = Bindings();
        bindings.classType(element, unit, declaration);
        final first = bindings.bindTypeParameters(
          selected.typeParameters,
          unit,
          declaration,
        );
        expect(first.single.defaultType, isNull);
        final augmented = bindings.bindTypeParameters(
          selected.typeParameters,
          unit,
          declaration,
          defaultTemplates: templates,
        );
        expect(identical(augmented.single, first.single), isTrue);
        expect(augmented.single.bound, ValueType.number);
        expect(augmented.single.defaultType, ValueType.number);
        expect(
          bindings
              .bindTypeParameters(
                selected.typeParameters,
                unit,
                declaration,
                defaultTemplates: templates,
              )
              .single,
          same(first.single),
        );
        expect(
          () => bindings.bindTypeParameters(
            selected.typeParameters,
            unit,
            declaration,
            defaultTemplates: const [],
          ),
          throwsArgumentError,
        );
        expect(
          () => bindings.bindTypeParameters(
            selected.typeParameters,
            unit,
            declaration,
            defaultTemplates: [unit.libraryElement.typeProvider.stringType],
          ),
          throwsUnsupportedError,
        );
      });
    },
  );
  test(
    'foreign private defaults lower while unmodeled-parent guards stay lazy',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-forwarder-lazy-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/imported.dart').writeAsStringSync('''
abstract class PrivateContract { int _f([Symbol value = #public]); }
abstract class PublicContract { int f([Symbol value = #_secret]); }
class ImportedParent implements PublicContract {
  dynamic noSuchMethod(Invocation invocation) => 1;
}
''');
      final entry = File('${directory.path}/entry.dart')
        ..writeAsStringSync('''
import 'imported.dart';
class ForeignPrivate implements PrivateContract {
  dynamic noSuchMethod(Invocation invocation) => 1;
}
class UnknownParent extends ImportedParent {}
''');
      final program = await AnalysisSession([entry.path])
          .use((input) async => (await Lowering().lower(input)).program);
      final foreign = program.classes.singleWhere(
        (c) => c.type.name == 'ForeignPrivate',
      );
      expect(foreign.unsupportedForwarders, isEmpty);
      expect(
        foreign.members.keys,
        contains((
          kind: FunctionKind.method,
          name: '_f',
          privateScope: File('${directory.path}/imported.dart').uri,
        )),
      );
      final unknown = program.classes.singleWhere(
        (c) => c.type.name == 'UnknownParent',
      );
      expect(
        unknown.unsupportedForwarders,
        contains((kind: FunctionKind.method, name: 'f', privateScope: null)),
      );
    },
  );
}
