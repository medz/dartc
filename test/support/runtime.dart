import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/src/compiler/runtime.dart';

late HeapRuntime heapRuntime;

Future<void> prepareRuntime() async {
  heapRuntime =
      await AnalysisSession([
        'lib/src/runtime/heap.dart',
      ], includeDependencies: true).use((input) async {
        final program = (await Lowering().lower(input)).program;
        return bindRuntime(program, input.libraries.first.element.uri);
      });
}
