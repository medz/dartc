import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test('system binding is confined to supplied SDK sources', () async {
    final result = await AnalysisSession(
      ['test/frontend/lowering/fixtures/system_native.dart'],
      sources: await SdkSources.load(),
      resources: ['sdk/patches/date_time.dart'],
      includeDependencies: true,
    ).use(Lowering().lower);
    final user = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'getpid',
    );
    final clock = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'clock_gettime',
    );
    expect(result.runtime.systemFunctions.contains(user.key), isFalse);
    expect(result.runtime.systemFunctions.contains(clock.key), isTrue);
  });
}
