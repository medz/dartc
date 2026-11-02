part of 'parser.dart';

final class _SwitchExpressionReader(final _Parser parser) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    parser.advance();
    final condition = _ConditionReader(parser);
    yield condition;
    parser.expect(.leftBrace);
    final cases = <int>[];
    while (parser.current.kind != .rightBrace && parser.current.kind != .eof) {
      final start = parser.current.start;
      final pattern = _CasePatternReader(parser);
      yield pattern;
      parser.expect(.arrow);
      final value = _ExpressionReader(parser);
      if (!value.start()) yield value;
      cases.add(
        parser.arena.putSwitchExpressionCase(
          source: parser.source,
          start: start,
          end: parser.arena.rEnd(value.result),
          pattern: pattern.result,
          value: value.result,
        ),
      );
      if (parser.current.kind != .comma) break;
      parser.advance();
    }
    result = parser.arena.putSwitchExpression(
      source: parser.source,
      start: token.start,
      end: parser.expect(.rightBrace),
      expression: condition.result,
      cases: cases,
    );
  }
}

final class _SwitchStatementReader(final _Parser parser) extends _Reader<int> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final token = parser.current;
    parser.advance();
    final condition = _ConditionReader(parser);
    yield condition;
    parser.expect(.leftBrace);
    final members = <int>[];
    parser.switchDepth++;
    var hasDefault = false;
    while (parser.current.kind != .rightBrace && parser.current.kind != .eof) {
      final start = parser.current.start;
      final labels = <int>[];
      while (parser.current.kind.isIdentifier &&
          parser.tokens[parser.cursor + 1].kind == .colon) {
        final name = parser.identifier(parser.current);
        parser.advance();
        final end = parser.current.end;
        parser.advance();
        labels.add(
          parser.arena.putLabel(
            source: parser.source,
            start: parser.arena.rStart(name),
            end: end,
            name: name,
          ),
        );
      }
      int? pattern;
      if (parser.current.kind == .keywordCase) {
        parser.advance();
        final reader = _CasePatternReader(
          parser,
          constantExpression: parser.before(3, 0),
        );
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
        pattern = parser.arena.putMissingPattern(
          source: parser.source,
          offset: parser.current.start,
        );
      }
      var end = parser.expect(.colon);
      final statements = <int>[];
      while (!parser.startsSwitchMember &&
          parser.current.kind != .rightBrace &&
          parser.current.kind != .eof) {
        final cursor = parser.cursor;
        final statement = _StatementReader(parser);
        yield statement;
        statements.add(statement.result);
        end = parser.arena.rEnd(statement.result);
        if (parser.cursor == cursor) parser.unexpected();
      }
      members.add(
        parser.arena.putSwitchStatementMember(
          source: parser.source,
          start: start,
          end: end,
          labels: labels,
          pattern: pattern,
          statements: statements,
        ),
      );
    }
    parser.switchDepth--;
    result = parser.arena.putSwitchStatement(
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
