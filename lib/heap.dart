/// The runtime that compiled programs contain.
///
/// Its source is translated with each program that needs it, and it runs here
/// on a simulated machine.
library;

export 'src/heap/collector.dart' show allocate, collect, heap;
export 'src/heap/machine.dart' show Machine, machine;
export 'src/heap/numbers.dart';
export 'src/heap/report.dart' show writeNumber;
export 'src/heap/unwind.dart' show raise;
