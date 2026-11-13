import 'package:dartc/ir.dart';

/// Describes a source callable and optional original call site.
String? frameDescription(FunctionTarget function, [SourceLocation? location]) {
  if (function.library == null) return null;
  String name(FunctionTarget target) {
    final prefix = target.enclosing == null
        ? target.owner?.name
        : name(target.enclosing!);
    return prefix == null
        ? target.name
        : target.name.isEmpty
        ? prefix
        : '$prefix.${target.name}';
  }

  final label = name(function);
  return location == null
      ? label
      : '$label (${location.uri}:${location.line}:${location.column})';
}
