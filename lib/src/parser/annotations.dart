part of 'parser.dart';

final class _MetadataReader(final _Parser parser) extends _Reader<List<int>> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (parser.current.kind != .at) {
      result = const [];
      return;
    }
    final metadata = <int>[];
    do {
      final at = parser.current;
      parser.advance();
      final name = <int>[parser.readVariableName()];
      while (parser.current.kind == .dot && name.length < 3) {
        parser.advance();
        name.add(parser.readAnnotationMember());
      }
      int? typeArguments;
      int? constructorName;
      if (parser.current.kind == .less) {
        if (name.length > 2) {
          parser.error(
            'invalid_annotation_type_arguments',
            'Type arguments must follow the annotation type name.',
            parser.current,
          );
        }
        final start = parser.current.start;
        final reader = _TypeReader(parser);
        if (!reader.start(arguments: true)) yield _TypeTask(reader);
        typeArguments = parser.arena.asTypeArgumentListOrNull(reader.result);
        if (reader.failure case final failure?) {
          parser.error(failure.$1, failure.$2, failure.$3);
        }
        typeArguments ??= parser.arena.putTypeArgumentList(
          start: start,
          end: parser.current.start,
          arguments: const [],
        );
        if (parser.current.kind == .dot) {
          parser.advance();
          constructorName = parser.readAnnotationMember();
        }
      }
      int? arguments;
      final nameEnd =
          parser.arena.rEndOrNull(constructorName) ??
          parser.arena.rEndOrNull(typeArguments) ??
          parser.arena.rEnd(name.last);
      if (parser.current.kind == .leftParen &&
          (parser.current.start == nameEnd || typeArguments != null)) {
        if (parser.current.start != nameEnd) {
          parser.error(
            'annotation_argument_space',
            'Annotation arguments must immediately follow the name.',
            parser.current,
          );
        }
        final reader = _ArgumentsReader(parser);
        yield reader;
        arguments = reader.result;
      } else if (typeArguments != null) {
        parser.error(
          'expected_annotation_arguments',
          'Expected arguments after the annotation type arguments.',
          parser.current,
        );
      }
      metadata.add(
        parser.arena.putAnnotation(
          start: at.start,
          end:
              parser.arena.rEndOrNull(arguments) ??
              parser.arena.rEndOrNull(constructorName) ??
              parser.arena.rEndOrNull(typeArguments) ??
              parser.arena.rEnd(name.last),
          name: name,
          typeArguments: typeArguments,
          constructorName: constructorName,
          arguments: arguments,
        ),
      );
    } while (parser.current.kind == .at);
    result = metadata;
  }
}

extension on _Parser {
  int readAnnotationMember() {
    if (current.kind == .keywordNew) {
      final result = identifier(current);
      advance();
      return result;
    }
    return readVariableName();
  }
}
