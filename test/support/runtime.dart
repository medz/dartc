import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/src/compiler/runtime.dart';

late HeapRuntime heapRuntime;

Future<LoweringResult> prepareRuntime([String? source]) async {
  final archive = await SourceArchive.load();
  return AnalysisSession(
    [?source],
    includeDependencies: true,
    sdk: DartSdk(archive),
    sourceArchive: archive,
    resources: ['dartc/src/runtime/allocator.dart'],
  ).use((input) async {
    final result = await Lowering().lower(input);
    heapRuntime = bindRuntime(result);
    return result;
  });
}
