part of 'parser.dart';

final class _RecordTypes(final Token opening) extends _AnnotatedTypeFrame {
  final List<PositionalRecordTypeField> positional = [];
  final List<NamedRecordTypeField> named = [];
  Token? namedOpening;
  RecordTypeNamedFields? namedFields;
  bool hasComma = false;
}

extension on _TypeReader {
  TypeAnnotation? prepareRecord(_RecordTypes frame) {
    if (current.kind == .leftBrace) {
      if (frame.namedOpening != null) {
        fail(
          'unexpected_token',
          'Only one named record field group is allowed.',
        );
        return null;
      }
      frame.namedOpening = current;
      parser.advance();
    }
    if (frame.namedOpening != null && current.kind == .rightBrace) {
      if (frame.named.isEmpty) {
        fail('expected_type', 'Expected a named record field.');
        return null;
      }
      frame.namedFields = RecordTypeNamedFields(
        source: source,
        start: frame.namedOpening!.start,
        end: current.end,
        fields: frame.named,
      );
      parser.advance();
      return finishRecord(frame);
    }
    if (current.kind == .rightParen) return finishRecord(frame);
    readMetadata(frame);
    return null;
  }

  TypeAnnotation? continueRecord(_RecordTypes frame) {
    if (current.kind == .comma) {
      frame.hasComma = true;
      parser.advance();
      return prepareRecord(frame);
    }
    if (current.kind == .rightBrace) return prepareRecord(frame);
    return finishRecord(frame);
  }

  TypeAnnotation? finishRecord(_RecordTypes frame) {
    if (current.kind != .rightParen ||
        frame.namedOpening != null && frame.namedFields == null) {
      fail('expected_closer', 'Expected the end of the record type.');
      return null;
    }
    if (frame.positional.length == 1 &&
        frame.namedFields == null &&
        !frame.hasComma) {
      fail(
        'expected_comma',
        'A single positional record type needs a trailing comma.',
      );
      return null;
    }
    final end = current.end;
    parser.advance();
    frames.removeLast();
    final question = nullableOffset();
    return RecordTypeAnnotation(
      source: source,
      start: frame.opening.start,
      end: question == null ? end : question + 1,
      questionOffset: question,
      positionalFields: frame.positional,
      namedFields: frame.namedFields,
    );
  }
}
