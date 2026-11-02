part of 'scanner.dart';

const _identifierState = 1;
final _keywords = _buildKeywords();

({Uint16List steps, List<TokenKind?> kinds}) _buildKeywords() {
  final words = TokenKind.values.where((kind) => kind.isKeyword);
  final capacity = words.fold(2, (n, kind) => n + kind.spelling!.length);
  // A missing keyword edge either ends the token (zero) or continues a name.
  final row = Uint16List(128);
  for (var code = 0; code < row.length; code++) {
    if (_isIdentifierPart(code, true)) row[code] = _identifierState;
  }
  final steps = Uint16List(capacity * 128);
  steps.setRange(0, 128, row);
  final kinds = List<TokenKind?>.filled(capacity, null);
  var used = 2;
  for (final kind in words) {
    var state = 0;
    for (final code in kind.spelling!.codeUnits) {
      final slot = state * 128 + code;
      if (steps[slot] == _identifierState) {
        steps[slot] = used++;
        final first = steps[slot] * 128;
        steps.setRange(first, first + 128, row);
      }
      state = steps[slot];
    }
    kinds[state] = kind;
  }
  return (steps: steps, kinds: kinds);
}
