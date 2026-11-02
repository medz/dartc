part of 'scanner.dart';

enum _InvalidRole { skip, identifier, other }

_InvalidRole _invalidRole(int code) => switch (code) {
  < 0x1f ||
  0xa0 ||
  0x1680 ||
  0x180e ||
  >= 0x2000 && <= 0x200b ||
  0x2028 ||
  0x2029 ||
  0x202f ||
  0x205f ||
  0x3000 ||
  0xfeff ||
  0xfffd => .skip,
  0x1f || >= 0x7f => .identifier,
  _ => .other,
};

List<Token> tokensForParsing(ScanResult input, List<Diagnostic> diagnostics) {
  final tokens = input.tokens;
  if (!input.hasErrors) return tokens;
  List<Token>? filtered;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.kind == .invalid) {
      switch (_invalidRole(input.source.text.codeUnitAt(token.start))) {
        case _InvalidRole.skip:
          filtered ??= tokens.sublist(0, i);
          continue;
        case _InvalidRole.identifier:
          // A recovered name can consume the prefix of a number or raw string.
          final recovered = _Scanner(input.source, recovering: true).scan();
          final seen = {
            for (final d in diagnostics) (d.code, d.message, d.span),
          };
          for (final d in recovered.diagnostics) {
            if (seen.add((d.code, d.message, d.span))) diagnostics.add(d);
          }
          return recovered.tokens;
        case _InvalidRole.other:
          break;
      }
    }
    filtered?.add(token);
  }
  return filtered ?? tokens;
}

extension on _Scanner {
  void _recoverIdentifier(int start) {
    final previous = _tokens.lastOrNull;
    if (previous != null &&
        previous.kind == .identifier &&
        previous.end == start) {
      start = _tokens.removeLast().start;
    }
    while (_offset < _text.length &&
        _isIdentifierPart(_text.codeUnitAt(_offset), true)) {
      _offset++;
    }
    _emit(.identifier, start);
  }
}
