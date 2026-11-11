import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';

late IrFunction heapCapacity;

Future<void> prepareRuntime() async {
  heapCapacity = await AnalysisSession(['lib/src/runtime/heap.dart']).use(
    (input) async =>
        (await Lowering().lower(input)).program.functions.singleWhere(
          (f) =>
              f.target.library == input.libraries.single.element.uri &&
              f.target.owner == null &&
              f.target.name == 'heapCapacity',
        ),
  );
}
