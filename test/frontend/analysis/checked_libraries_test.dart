import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  const path = 'test/compiler/fixtures/arithmetic.dart';
  test('platform declarations determine unused constant assertions', () async {
    const fixture =
        'test/frontend/analysis/fixtures/environment_assertion.dart';
    await AnalysisSession([fixture]).use((_) {});
    await expectLater(
      AnalysisSession(
        [fixture],
        environment: {'dart.library.js_interop': 'true'},
      ).use((_) {}),
      throwsFormatException,
    );
  });
  test(
    'environment declarations are isolated from later caller edits',
    () async {
      final declarations = {'flavor': 'native', 'text': 'before'};
      final session = AnalysisSession(
        ['test/compiler/fixtures/environment.dart'],
        includeDependencies: true,
        environment: declarations,
      );
      declarations['flavor'] = 'default';
      declarations['text'] = 'after';
      await session.use((checked) {
        final library = checked.libraries.first.element;
        final strings = library
            .getTopLevelVariable('stringValues')!
            .computeConstantValue()!
            .toMapValue()!;
        expect(
          strings.entries
              .singleWhere((e) => e.key!.toStringValue() == 'text')
              .value!
              .toStringValue(),
          'before',
        );
        expect(
          [
            for (final import in library.firstFragment.libraryImports)
              if (import.importedLibrary?.getTopLevelVariable('selected')
                  case final selected?)
                selected.computeConstantValue()!.toStringValue(),
          ],
          ['native', 'default'],
        );
      });
    },
  );
  test('SDK selection alone does not mount private runtime sources', () async {
    await expectLater(
      AnalysisSession(
        [path],
        resources: ['sdk/runtime/allocator.dart'],
      ).use((_) {}),
      throwsArgumentError,
    );
  });
  test(
    'source resources share analysis identities and lifetime with inputs',
    () async {
      final session = AnalysisSession(
        [path],
        sources: await SdkSources.load(),
        resources: ['sdk/runtime/allocator.dart'],
      );
      final checked = await session.resolve();
      final runtime = checked.resources['sdk/runtime/allocator.dart']!;
      expect(runtime.session, same(checked.libraries.first.session));
      expect(
        runtime.element.typeProvider.intType.element,
        same(checked.libraries.first.element.typeProvider.intType.element),
      );
      await session.close();
      expect(() => checked.resources, throwsStateError);
    },
  );

  test('missing source resources fail before analysis', () async {
    await expectLater(
      AnalysisSession(
        [path],
        sources: await SdkSources.load(),
        resources: ['sdk/runtime/missing.dart'],
      ).use((_) => fail('A missing resource reached the consumer.')),
      throwsArgumentError,
    );
  });
  test('resolution and disposal belong to the session', () async {
    final session = AnalysisSession([path]);
    final resolving = session.resolve();
    expect(session.resolve(), same(resolving));
    final checked = await resolving;
    expect(checked.libraries, hasLength(1));
    final closing = session.close();
    expect(session.close(), same(closing));
    await closing;
    expect(() => session.resolve(), throwsStateError);
    expect(() => checked.libraries, throwsStateError);
  });

  test('scoped access closes the session after consumer failure', () async {
    final session = AnalysisSession([path]);
    final failure = StateError('consumer failed');
    await expectLater(
      session.use((_) => throw failure),
      throwsA(same(failure)),
    );
    expect(() => session.resolve(), throwsStateError);
    await session.close();
  });

  test('transitive errors precede consumption', () async {
    var consumed = false;
    await expectLater(
      AnalysisSession([
        'test/compiler/fixtures/invalid_dependency.dart',
      ], includeDependencies: true).use((_) {
        consumed = true;
      }),
      throwsFormatException,
    );
    expect(consumed, isFalse);
  });

  test('constant checks use exact comparisons before rejecting SDK errors', () {
    return AnalysisSession([
      'test/frontend/analysis/fixtures/valid_constants.dart',
    ]).use((_) {});
  });

  for (final fixture in [
    'invalid_local_constant',
    'invalid_constant_expression',
    'invalid_constant_default',
    'invalid_constant_annotation',
    'invalid_constant_dependency',
    'invalid_constant_beside_valid',
  ]) {
    test('checks $fixture before allowing consumption', () async {
      var consumed = false;
      await expectLater(
        AnalysisSession([
          'test/frontend/analysis/fixtures/$fixture.dart',
        ], includeDependencies: true).use((_) => consumed = true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'assertion',
            contains('Expected equal values.'),
          ),
        ),
      );
      expect(consumed, isFalse);
    });
  }
}
