import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  const path = 'test/compiler/fixtures/arithmetic.dart';
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
      final lowered = await Lowering().lower(checked);
      final body = lowered.program.functions.singleWhere(
        (f) =>
            f.target.library == runtime.element.uri &&
            f.target.name == 'slotSize',
      );
      expect(body.target.library?.scheme, 'file');
      expect(body.callees, isEmpty);
      await session.close();
      expect(() => checked.resources, throwsStateError);
    },
  );

  test('missing source resources fail before analysis', () async {
    await expectLater(
      AnalysisSession([path], resources: ['runtime/missing.dart']).use((_) {}),
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

  test(
    'checks and lowers a batch without recreating its analysis session',
    () async {
      await AnalysisSession([path]).use((input) async {
        expect(input.libraries, hasLength(1));
        expect((await Lowering().lower(input)).program.functions, isNotEmpty);
        expect(
          (await Lowering(enableAssertions: true).lower(input))
              .program
              .functions,
          isNotEmpty,
        );
      });
    },
  );
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
    ]).use((checked) async {
      expect(checked.libraries, hasLength(1));
      expect((await Lowering().lower(checked)).program.functions, isNotEmpty);
    });
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
