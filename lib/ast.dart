/// Immutable Dart type, metadata, and expression nodes.
///
/// Nodes refer to one source snapshot and use UTF-16 ranges. Constructing a
/// node checks its ranges and children; it does not parse or type-check Dart.
///
/// {@example /example/ast.dart}
library;

export 'src/ast/nodes.dart';
export 'src/ast/walk.dart';
