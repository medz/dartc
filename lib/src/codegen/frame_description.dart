import 'package:dartc/ir.dart';

/// Describes logical source frames, innermost first, separated by newlines.
String? frameDescription(FunctionTarget function, [SourceLocation? location]) {
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

  final frames = <String>[];
  var current = location;
  do {
    final target = current?.function ?? function;
    if (target.library != null) {
      final label = name(target);
      final position = current?.position;
      frames.add(
        position == null
            ? label
            : '$label (${position.uri}:${position.line}:${position.column})',
      );
    }
    current = current?.caller;
  } while (current != null);
  return frames.isEmpty ? null : frames.join('\n');
}
