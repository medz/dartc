part of 'scanner.dart';

final _keywords = _buildKeywords();

({Uint16List steps, List<TokenKind?> kinds}) _buildKeywords() {
  final words = TokenKind.values.where((kind) => kind.isKeyword);
  final capacity = words.fold(1, (n, kind) => n + kind.spelling!.length);
  // ASCII keyword letters occupy distinct slots in the upper half of ASCII.
  final steps = Uint16List(capacity * 64);
  final kinds = List<TokenKind?>.filled(capacity, null);
  var used = 1;
  for (final kind in words) {
    var state = 0;
    for (final code in kind.spelling!.codeUnits) {
      final slot = state * 64 + (code & 63);
      if (steps[slot] == 0) steps[slot] = used++;
      state = steps[slot];
    }
    kinds[state] = kind;
  }
  return (steps: steps, kinds: kinds);
}
