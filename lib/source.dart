/// Source snapshots, UTF-16 ranges, and line information.
///
/// Source offsets are zero-based; line and column numbers are one-based.
/// Loading and URI resolution belong to the caller.
///
/// {@example /example/source.dart}
library;

export 'src/source/line_info.dart';
export 'src/source/source_file.dart';
export 'src/source/source_provider.dart';
export 'src/source/source_span.dart';
