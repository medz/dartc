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
  final tokens = input._parserTokens ?? input.tokens;
  if (!input.hasErrors) return tokens;
  final first = tokens.indexWhere(
    (token) =>
        token.kind == .invalid &&
        _invalidRole(input.source.text.codeUnitAt(token.start)) != .other,
  );
  if (first < 0) return tokens;
  // Compact a single copy. The caller retains the original tokens.
  final output = List<Token>.of(tokens);
  var write = first;
  Set<(String, String, SourceSpan?)>? seen;
  void emit(Token token) {
    if (write < output.length) {
      output[write] = token;
    } else {
      output.add(token);
    }
    write++;
  }

  void includeErrors(List<Diagnostic>? errors) {
    if (errors == null || errors.isEmpty) return;
    final reported = seen ??= {
      for (final d in diagnostics) (d.code, d.message, d.span),
    };
    for (final d in errors) {
      if (reported.add((d.code, d.message, d.span))) diagnostics.add(d);
    }
  }

  for (var i = first; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.kind == .invalid) {
      switch (_invalidRole(input.source.text.codeUnitAt(token.start))) {
        case _InvalidRole.skip:
          continue;
        case _InvalidRole.identifier:
          final end = _identifierEnd(input.source.text, token.end);
          while (tokens[i + 1].start < end) {
            i++;
          }
          var start = token.start;
          if (write > 0 && _joinsName(output[write - 1], start)) {
            start = output[--write].start;
          }
          emit(Token._scanned(.identifier, input.source, start, end));
          if (tokens[i].end != end) {
            final fragment = _splitToken(input.source, end, tokens[i]);
            if (fragment == null) {
              final recovered = _Scanner(input.source, recovering: true).scan();
              includeErrors(recovered.diagnostics);
              return recovered.tokens;
            }
            for (final token in fragment._tokens) {
              emit(token);
            }
            includeErrors(fragment._diagnostics);
          }
          continue;
        case _InvalidRole.other:
          break;
      }
    }
    emit(token);
  }
  output.length = write;
  return output;
}

_Scanner? _splitToken(SourceFile source, int start, Token original) {
  final string = original.kind == .stringLiteral;
  if (!string && original.kind != .doubleLiteral) return null;
  final scanner = _Scanner(source, recovering: true).._offset = start;
  do {
    scanner._token();
  } while (scanner._offset < original.end &&
      (!string || scanner._interpolation != null));
  // The enclosing scanner state is reusable only if the fragment ends at the same boundary.
  return scanner._offset == original.end && scanner._interpolation == null
      ? scanner
      : null;
}

int _identifierEnd(String text, int offset) {
  while (offset < text.length &&
      _isIdentifierPart(text.codeUnitAt(offset), true)) {
    offset++;
  }
  return offset;
}

void _appendIdentifier(
  List<Token> tokens,
  SourceFile source,
  int start,
  int end,
) {
  final previous = tokens.lastOrNull;
  if (previous != null && _joinsName(previous, start)) {
    start = tokens.removeLast().start;
  }
  tokens.add(Token._scanned(.identifier, source, start, end));
}

bool _joinsName(Token token, int start) =>
    token.kind == .identifier && token.end == start;
