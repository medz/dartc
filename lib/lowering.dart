/// Translation from checked Dart libraries to the compiler's typed IR.
///
/// [CheckedLibraries.read] runs [Lowering.lower] while the analysis session is
/// open. The returned functions can be inspected after the session closes.
///
/// {@example /tool/print_ir.dart#lower_libraries}
///
/// @docImport 'src/lowering/checked_libraries.dart';
/// @docImport 'src/lowering/lowering.dart';
library;

export 'src/lowering/checked_libraries.dart' show CheckedLibraries;
export 'src/lowering/lowering.dart' show Lowering;
