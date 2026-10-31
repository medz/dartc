part of 'parser.dart';

extension on _Parser {
  List<Annotation> readMetadata() {
    if (current.kind != .at) return const [];
    final metadata = <Annotation>[];
    do {
      final at = current;
      advance();
      final name = <Identifier>[readVariableName()];
      while (current.kind == .dot && name.length < 3) {
        advance();
        name.add(readAnnotationMember());
      }
      TypeArgumentList? typeArguments;
      Identifier? constructorName;
      if (current.kind == .less) {
        if (name.length > 2) {
          error(
            'invalid_annotation_type_arguments',
            'Type arguments must follow the annotation type name.',
            current,
          );
        }
        final start = current.start;
        final reader = _TypeReader(this);
        typeArguments = reader.read(arguments: true) as TypeArgumentList?;
        if (reader.failure case final failure?) {
          error(failure.$1, failure.$2, failure.$3);
        }
        typeArguments ??= TypeArgumentList(
          source: source,
          start: start,
          end: current.start,
          arguments: const [],
        );
        if (current.kind == .dot) {
          advance();
          constructorName = readAnnotationMember();
        }
      }
      ArgumentList? arguments;
      final nameEnd =
          constructorName?.end ?? typeArguments?.end ?? name.last.end;
      if (current.kind == .leftParen &&
          (current.start == nameEnd || typeArguments != null)) {
        if (current.start != nameEnd) {
          error(
            'annotation_argument_space',
            'Annotation arguments must immediately follow the name.',
            current,
          );
        }
        arguments = readArgumentList();
      } else if (typeArguments != null) {
        error(
          'expected_annotation_arguments',
          'Expected arguments after the annotation type arguments.',
          current,
        );
      }
      metadata.add(
        Annotation(
          source: source,
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
    } while (current.kind == .at);
    return metadata;
  }

  Identifier readAnnotationMember() {
    if (current.kind == .keywordNew) {
      final result = identifier(current);
      advance();
      return result;
    }
    return readVariableName();
  }

  ArgumentList readArgumentList() {
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    final arguments = _ArgumentList(current, 0, 0);
    advance();
    frames.add(arguments);
    expectsOperand = true;
    hasSyntaxError = false;
    if (run(trial: false, boundary: .header)) {
      parseWithTrials(boundary: .header);
    }
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    return arguments.result;
  }
}
