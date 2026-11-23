/// Something in the source that stops compilation, with 1-based positions.
final class const SourceProblem(
  final String path,
  final int line,
  final int column,
  final String message,
) {
  @override
  String toString() => '$path:$line:$column: $message';
}

/// A program that cannot be compiled.
final class CompileFailure(Iterable<SourceProblem> problems)
    implements Exception {
  final List<SourceProblem> problems = .unmodifiable(problems);

  @override
  String toString() => problems.join('\n');
}
