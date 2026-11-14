import 'package:dartc/ir.dart';

/// Logical source frames, innermost first, excluding generated machine frames.
Iterable<(String, SourceLocation?)> sourceFrames(
  FunctionTarget function, [
  SourceLocation? location,
]) sync* {
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

  var current = location;
  do {
    final target = current?.function ?? function;
    if (target.library != null) {
      yield (name(target), current);
    }
    current = current?.caller;
  } while (current != null);
}

/// Describes logical source frames for suspended Dart continuations.
String? frameDescription(FunctionTarget function, [SourceLocation? location]) {
  final frames = [
    for (final (name, source) in sourceFrames(function, location))
      switch (source?.position) {
        null => name,
        final position =>
          '$name (${position.uri}:${position.line}:${position.column})',
      },
  ];
  return frames.isEmpty ? null : frames.join('\n');
}
