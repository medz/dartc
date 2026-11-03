part of 'parser.dart';

final class _StringSequence(final SyntaxTreeBuilder arena) {
  final List<int> _strings = [];
  final List<int> _parts = [];
  Token? _opening;

  void addLiteral(int literal) => _strings.add(literal);

  void addText(Token token) {
    if (token.kind == .stringStart) _opening = token;
    _parts.add(arena.stringText(start: token.start, end: token.end));
    if (token.kind == .stringEnd) _finishString(token.end);
  }

  void addInterpolation(
    Token marker,
    int expression,
    int end, {
    required bool isBraced,
  }) {
    _parts.add(
      arena.stringInterpolation(
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
      arena.interpolatedStringExpression(
        start: opening.start,
        end: end,
        parts: _parts,
      ),
    );
    _parts.clear();
    _opening = null;
  }

  int finish(int end) {
    // Recovery can reach EOF before the scanner emits a closing text segment.
    if (_opening != null) _finishString(end);
    if (_strings.length == 1) return _strings.single;
    return arena.adjacentStringsExpression(
      start: arena.start(_strings.first),
      end: arena.end(_strings.last),
      strings: _strings,
    );
  }
}
