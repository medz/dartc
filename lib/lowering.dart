/// Translation from checked Dart libraries to the compiler's typed IR.
///
/// [AnalysisSession.use] keeps checked input available to a [Lowering] instance.
/// The resulting IR and native bindings are independent of the session.
///
/// {@example /tool/print_ir.dart#lower_libraries}
///
/// @docImport 'analyzer.dart';
/// @docImport 'src/lowering/lowering.dart';
library;

export 'src/lowering/lowering.dart' show Lowering, LoweringResult;
