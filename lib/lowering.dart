/// Translation from checked Dart libraries to the compiler's typed IR.
///
/// [CheckedLibraries.read] runs [Lowering.lower] while the analysis session is
/// open. The resulting class declarations and function bodies are independent
/// of the analyzer session.
///
/// {@example /tool/print_ir.dart#lower_libraries}
///
/// @docImport 'analyzer.dart';
/// @docImport 'src/lowering/lowering.dart';
library;

export 'src/lowering/lowering.dart' show Lowering;
