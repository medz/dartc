import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/mixin_application_state.dart' as sdk;

void main() {
  group('mixin application state and lexical super SDK comparison', () {
    late FixtureComparison fixture;
    setUpAll(() async {
      fixture = FixtureComparison(
        await CheckedLibraries.read([
          'test/lowering/fixtures/mixin_application_state.dart',
          'test/lowering/fixtures/mixin_application_state_private.dart',
        ], Lowering.lower),
      );
    });

    test('SDK initializes repeated applications derived-first', () {
      expect(sdk.independentState(), '2:1:1:1:1:1:2');
      expect(sdk.independentStateWrites(), '30:40:30:50:50:50');
    });

    test('SDK binds each super reference to its lexical prefix', () {
      expect(sdk.lexicalSuperCalls(), '100:11:21');
      expect(sdk.lexicalSuperTearoffs(), '1:11:false:true:true');
      expect(sdk.lexicalSuperEscapedClosures(), '1:11:100');
      expect(sdk.mixinClassLexicalSuper(), '99:7:7');
      expect(sdk.privateClosureProvenance(), '99:41:41');
    });

    for (final (name, reference) in <(String, Object? Function())>[
      ('constraintReceiverView', sdk.constraintReceiverView),
      ('constructorFieldEffects', sdk.constructorFieldEffects),
      ('independentState', sdk.independentState),
      ('independentStateWrites', sdk.independentStateWrites),
      ('independentLazyState', sdk.independentLazyState),
      (
        'lazyAssignmentSkipsOnlyOwnInitializer',
        sdk.lazyAssignmentSkipsOnlyOwnInitializer,
      ),
      ('independentLateFinalWrites', sdk.independentLateFinalWrites),
      ('lateFinalSecondWrite', sdk.lateFinalSecondWrite),
      ('lateReadDoesNotBorrowOtherSlot', sdk.lateReadDoesNotBorrowOtherSlot),
      ('lexicalSuperCalls', sdk.lexicalSuperCalls),
      ('lexicalSuperTearoffs', sdk.lexicalSuperTearoffs),
      ('lexicalSuperEscapedClosures', sdk.lexicalSuperEscapedClosures),
      ('mixinClassLexicalSuper', sdk.mixinClassLexicalSuper),
      ('privateClosureProvenance', sdk.privateClosureProvenance),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }

    test('repeated application fields have distinct ordinary owners', () {
      final fields = fixture.program.classes
          .expand((declaration) => declaration.fields)
          .where(
            (field) =>
                field.name == 'value' && field.owner.name.contains(':mixin:'),
          )
          .toList();
      expect(fields, hasLength(2));
      expect(fields.map((field) => field.owner).toSet(), hasLength(2));
      expect(fields.toSet(), hasLength(2));
      for (final field in fields) {
        expect(field.owner.name, contains(':mixin:'));
      }
    });

    test('late initializers belong to each actual application', () {
      final fields = fixture.program.classes
          .expand((declaration) => declaration.fields)
          .where(
            (field) =>
                field.owner.name.contains(':mixin:') &&
                field.isLate &&
                field.initializer != null,
          )
          .toList();
      expect(fields, hasLength(4));
      expect(fields.map((field) => field.initializer).toSet(), hasLength(4));
      for (final field in fields) {
        expect(field.initializer!.owner, field.owner);
        expect(
          fixture.program.functions.where(
            (body) => body.target == field.initializer,
          ),
          hasLength(1),
        );
      }
    });
  });
}
