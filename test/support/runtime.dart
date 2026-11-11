import 'package:dartc/codegen.dart';
import 'package:dartc/frontend.dart';

late HeapRuntime heapRuntime;

Future<void> prepareRuntime() async {
  heapRuntime = await AnalysisSession(['lib/src/runtime/heap.dart'])
      .use((input) async {
        final program = (await Lowering().lower(input)).program;
        final functions = {
          for (final function in program.functions)
            if (function.target.library == input.libraries.single.element.uri &&
                function.target.owner == null)
              function.target.name: function,
        };
        return HeapRuntime(
          capacity: functions['heapCapacity']!,
          copy: functions['copyWords']!,
          clear: functions['clearWords']!,
        );
      });
}
