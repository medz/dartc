import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/compiler/runtime.dart';

late HeapRuntime heapRuntime;

Future<LoweringResult> prepareRuntime([String? source]) async {
  final archive = await SdkSources.load();
  return AnalysisSession(
    [?source],
    includeDependencies: true,
    sdk: DartSdk(archive),
    sources: archive,
    resources: [
      'sdk/runtime/allocator.dart',
      'sdk/runtime/stack_trace.dart',
      'sdk/runtime/type_info.dart',
      'sdk/runtime/dispatch.dart',
      'sdk/runtime/executable_memory.dart',
    ],
  ).use((input) async {
    final result = await Lowering().lower(input);
    heapRuntime = bindRuntime(result, Target.host());
    return result;
  });
}
