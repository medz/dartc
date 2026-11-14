import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/runtime/contracts.dart';
import 'package:test/test.dart';

void main() {
  test('system binding is confined to supplied SDK sources', () async {
    final result = await AnalysisSession(
      ['test/frontend/lowering/fixtures/system_native.dart'],
      sources: await SdkSources.load(),
      includeDependencies: true,
    ).use(Lowering().lower);
    final user = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'getpid',
    );
    final clock = result.imports.entries.singleWhere(
      (entry) => entry.value.symbol == 'clock_gettime',
    );
    expect(result.runtime.systemFunctions.containsKey(user.key), isFalse);
    expect(result.runtime.nonAllocating, isNot(contains(user.key)));
    expect(result.runtime.systemFunctions[clock.key], SystemLibrary.c);
    expect(clock.value.isLeaf, isTrue);
  });
}
