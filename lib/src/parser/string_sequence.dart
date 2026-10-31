import 'package:dartc/ast.dart';
import 'package:dartc/scanner.dart';

final class StringSequence {
  final List<StringExpression> _strings = [];
  final List<StringPart> _parts = [];
  Token? _opening;

  void addLiteral(StringLiteralExpression literal) => _strings.add(literal);

  void addText(Token token) {
    if (token.kind == .stringStart) _opening = token;
    _parts.add(
      StringText(source: token.source, start: token.start, end: token.end),
    );
    if (token.kind == .stringEnd) _finishString(token.end);
  }

  void addInterpolation(
    Token marker,
    Expression expression,
    int end, {
    required bool isBraced,
  }) {
    _parts.add(
      StringInterpolation(
        source: marker.source,
        start: marker.start,
        end: end,
        expression: expression,
        isBraced: isBraced,
      ),
    );
  }

  void _finishString(int end) {
    final opening = _opening!;
    _strings.add(
      InterpolatedStringExpression(
        source: opening.source,
        start: opening.start,
        end: end,
        parts: _parts,
      ),
    );
    _parts.clear();
    _opening = null;
  }

  StringExpression finish(int end) {
    // Recovery can reach EOF before the scanner emits a closing text segment.
    if (_opening != null) _finishString(end);
    if (_strings.length == 1) return _strings.single;
    return AdjacentStringsExpression(
      source: _strings.first.source,
      start: _strings.first.start,
      end: _strings.last.end,
      strings: _strings,
    );
  }
}
