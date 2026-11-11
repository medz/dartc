/// Checks Dart libraries and translates their resolved declarations to typed IR.
///
/// Use [AnalysisSession] for scoped analysis and [Lowering] to translate its
/// checked libraries. Resolved analyzer objects belong to the open session;
/// the resulting IR and native bindings remain usable after it closes.
///
/// {@example /tool/print_ir.dart#lower_libraries}
///
/// @docImport 'src/frontend/analysis/session.dart';
/// @docImport 'src/frontend/lowering/lowering.dart';
library;

export 'src/frontend/analysis/session.dart'
    show AnalysisSession, CheckedLibraries;
export 'src/frontend/lowering/lowering.dart' show Lowering, LoweringResult;

export 'src/frontend/runtime_declarations.dart' show RuntimeDeclarations;
