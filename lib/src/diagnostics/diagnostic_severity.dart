/// The severity of a diagnostic.
enum DiagnosticSeverity {
  /// Information that does not by itself prevent compilation.
  info,

  /// A problem that does not by itself prevent compilation.
  warning,

  /// A problem that prevents successful compilation.
  error,
}
