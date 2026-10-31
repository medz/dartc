part of 'parser.dart';

final class _MetadataReader(final _Parser parser)
    extends _Reader<List<Annotation>> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (parser.current.kind != .at) {
      result = const [];
      return;
    }
    final metadata = <Annotation>[];
    do {
      final at = parser.current;
      parser.advance();
      final name = <Identifier>[parser.readVariableName()];
      while (parser.current.kind == .dot && name.length < 3) {
        parser.advance();
        name.add(parser.readAnnotationMember());
      }
      TypeArgumentList? typeArguments;
      Identifier? constructorName;
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
        typeArguments = reader.read(arguments: true) as TypeArgumentList?;
        if (reader.failure case final failure?) {
          parser.error(failure.$1, failure.$2, failure.$3);
        }
        typeArguments ??= TypeArgumentList(
          source: parser.source,
          start: start,
          end: parser.current.start,
          arguments: const [],
        );
        if (parser.current.kind == .dot) {
          parser.advance();
          constructorName = parser.readAnnotationMember();
        }
      }
      ArgumentList? arguments;
      final nameEnd =
          constructorName?.end ?? typeArguments?.end ?? name.last.end;
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
        Annotation(
          source: parser.source,
          start: at.start,
          end:
              arguments?.end ??
              constructorName?.end ??
              typeArguments?.end ??
              name.last.end,
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
  Identifier readAnnotationMember() {
    if (current.kind == .keywordNew) {
      final result = identifier(current);
      advance();
      return result;
    }
    return readVariableName();
  }
}
