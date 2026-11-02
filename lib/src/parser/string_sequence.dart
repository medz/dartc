import 'package:dartc/scanner.dart';

import '../ast/nodes.dart' show AstArena;
import '../ast/row_fields.dart';

final class StringSequence(final AstArena arena) {
  final List<int> _strings = [];
  final List<int> _parts = [];
  Token? _opening;

  void addLiteral(int literal) => _strings.add(literal);

  void addText(Token token) {
    if (token.kind == .stringStart) _opening = token;
    _parts.add(
      arena.putStringText(
        source: token.source,
        start: token.start,
        end: token.end,
      ),
    );
    if (token.kind == .stringEnd) _finishString(token.end);
  }

  void addInterpolation(
    Token marker,
    int expression,
    int end, {
    required bool isBraced,
  }) {
    _parts.add(
      arena.putStringInterpolation(
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
      arena.putInterpolatedStringExpression(
        source: opening.source,
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
    return arena.putAdjacentStringsExpression(
      source: arena.rSource(_strings.first),
      start: arena.rStart(_strings.first),
      end: arena.rEnd(_strings.last),
      strings: _strings,
    );
  }
}
