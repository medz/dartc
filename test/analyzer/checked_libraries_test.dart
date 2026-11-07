import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  const path = 'test/compiler/fixtures/arithmetic.dart';
  test(
    'checks and lowers a batch without recreating its analysis session',
    () async {
      await CheckedLibraries.read([path], (input) {
        expect(input.libraries, hasLength(1));
        expect(Lowering.lower(input).functions, isNotEmpty);
        expect(
          Lowering.lower(input, enableAssertions: true).functions,
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
        CheckedLibraries.read(
          ['test/compiler/fixtures/invalid_dependency.dart'],
          (_) {
            consumed = true;
          },
          includeDependencies: true,
        ),
        throwsFormatException,
      );
      expect(consumed, isFalse);
    },
  );
}
