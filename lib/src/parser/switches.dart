part of 'parser.dart';

final class _SwitchExpressionReader(final _Parser parser)
    extends _Reader<Expression> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    parser.advance();
    final condition = _ConditionReader(parser);
    yield condition;
    parser.expect(.leftBrace);
    final cases = <SwitchExpressionCase>[];
    while (parser.current.kind != .rightBrace && parser.current.kind != .eof) {
      final start = parser.current.start;
      final pattern = _CasePatternReader(parser);
      yield pattern;
      parser.expect(.arrow);
      final value = _ExpressionReader(parser);
      if (!value.start()) yield value;
      cases.add(
        SwitchExpressionCase(
          source: parser.source,
          start: start,
          end: value.result.end,
          pattern: pattern.result,
          value: value.result,
        ),
      );
      if (parser.current.kind != .comma) break;
      parser.advance();
    }
    result = SwitchExpression(
      source: parser.source,
      start: token.start,
      end: parser.expect(.rightBrace),
      expression: condition.result,
      cases: cases,
    );
  }
}

final class _SwitchStatementReader(final _Parser parser)
    extends _Reader<Statement> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    parser.advance();
    final condition = _ConditionReader(parser);
    yield condition;
    parser.expect(.leftBrace);
    final members = <SwitchStatementMember>[];
    var hasDefault = false;
    while (parser.current.kind != .rightBrace && parser.current.kind != .eof) {
      final start = parser.current.start;
      final labels = <Label>[];
      while (parser.current.kind.isIdentifier &&
          parser.tokens[parser.cursor + 1].kind == .colon) {
        final name = parser.identifier(parser.current);
        parser.advance();
        final end = parser.current.end;
        parser.advance();
        labels.add(
          Label(source: parser.source, start: name.start, end: end, name: name),
        );
      }
      CasePattern? pattern;
      if (parser.current.kind == .keywordCase) {
        parser.advance();
        final reader = _CasePatternReader(parser);
        yield reader;
        pattern = reader.result;
      } else if (parser.current.kind == .keywordDefault) {
        if (hasDefault) {
          parser.error(
            'duplicate_default',
            'A switch can contain only one default member.',
            parser.current,
          );
        }
        hasDefault = true;
        parser.advance();
      } else {
        parser.error(
          'expected_switch_member',
          "Expected 'case' or 'default'.",
          parser.current,
        );
        if (labels.isEmpty) {
          parser.unexpected();
          continue;
        }
        pattern = MissingPattern(
          source: parser.source,
          offset: parser.current.start,
        );
      }
      var end = parser.expect(.colon);
      final statements = <Statement>[];
      while (!parser.startsSwitchMember &&
          parser.current.kind != .rightBrace &&
          parser.current.kind != .eof) {
        final cursor = parser.cursor;
        final statement = _StatementReader(parser);
        yield statement;
        statements.add(statement.result);
        end = statement.result.end;
        if (parser.cursor == cursor) parser.unexpected();
      }
      members.add(
        SwitchStatementMember(
          source: parser.source,
          start: start,
          end: end,
          labels: labels,
          pattern: pattern,
          statements: statements,
        ),
      );
    }
    result = SwitchStatement(
      source: parser.source,
      start: token.start,
      end: parser.expect(.rightBrace),
      expression: condition.result,
      members: members,
    );
  }
}

extension on _Parser {
  bool get startsSwitchMember {
    var index = cursor;
    while (tokens[index].kind.isIdentifier &&
        tokens[index + 1].kind == .colon) {
      index += 2;
    }
    return tokens[index].kind == .keywordCase ||
        tokens[index].kind == .keywordDefault;
  }
}
