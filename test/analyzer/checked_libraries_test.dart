import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  const path = 'test/compiler/fixtures/arithmetic.dart';
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
      await AnalysisSession([path]).use((input) {
        expect(input.libraries, hasLength(1));
        expect(Lowering().lower(input).program.functions, isNotEmpty);
        expect(
          Lowering(enableAssertions: true).lower(input).program.functions,
          isNotEmpty,
        );
      });
    },
  );
  test(
    'explicit SDK validation and transitive errors precede consumption',
    () async {
      expect(() => DartSdk.at('test/compiler/fixtures'), throwsArgumentError);
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
    },
  );
}
