import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/src/compiler/runtime.dart';

late HeapRuntime heapRuntime;

Future<void> prepareRuntime() async {
  final archive = await SourceArchive.load();
  heapRuntime =
      await AnalysisSession(
        [],
        includeDependencies: true,
        sdk: DartSdk(archive),
        sourceArchive: archive,
        resources: ['dartc/src/runtime/allocator.dart'],
      ).use((input) async {
        final program = (await Lowering().lower(input)).program;
        return bindRuntime(program, input, input.libraries.first.element.uri);
      });
}
