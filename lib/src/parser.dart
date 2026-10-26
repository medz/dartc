// Supported grammar:
// program   = ["void"] "main" "(" ")" "{" statement* "}" EOF
// statement = "print" "(" string ")" ";"
// Strings use single/double quotes; interpolation and raw/multiline strings
// are not supported. Whitespace and line/nested block comments are allowed.
List<String> parse(String source) => _Parser(source).parse();

class _Parser {
  final String source;
  int position = 0;

  _Parser(this.source);

  List<String> parse() {
    _word('void');
    _expectWord('main');
    _expect('(');
    _expect(')');
    _expect('{');
    final statements = <String>[];
    while (!_take('}')) {
      _expectWord('print');
      _expect('(');
      statements.add(_string());
      _expect(')');
      _expect(';');
    }
    _skip();
    if (position != source.length) _error('Unexpected code after main');
    return statements;
  }

  bool _word(String value) {
    _skip();
    if (!source.startsWith(value, position)) return false;
    final end = position + value.length;
    if (end < source.length) {
      final c = source.codeUnitAt(end);
      if (c >= 65 && c <= 90 ||
          c >= 97 && c <= 122 ||
          c >= 48 && c <= 57 ||
          c == 95 ||
          c == 36) {
        return false;
      }
    }
    position = end;
    return true;
  }

  void _expectWord(String value) {
    if (!_word(value)) _error('Expected "$value"');
  }

  bool _take(String value) {
    _skip();
    if (!source.startsWith(value, position)) return false;
    position += value.length;
    return true;
  }

  void _expect(String value) {
    if (!_take(value)) _error('Expected "$value"');
  }

  void _skip() {
    while (position < source.length) {
      final c = source.codeUnitAt(position);
      if (c == 32 || c >= 9 && c <= 13) {
        position++;
      } else if (source.startsWith('//', position)) {
        while (position < source.length && source.codeUnitAt(position) != 10) {
          position++;
        }
      } else if (source.startsWith('/*', position)) {
        position += 2;
        var depth = 1;
        while (depth > 0) {
          if (position >= source.length) _error('Unterminated block comment');
          if (source.startsWith('/*', position)) {
            depth++;
            position += 2;
          } else if (source.startsWith('*/', position)) {
            depth--;
            position += 2;
          } else {
            position++;
          }
        }
      } else {
        return;
      }
    }
  }

  String _string() {
    _skip();
    if (position == source.length ||
        source.codeUnitAt(position) != 39 &&
            source.codeUnitAt(position) != 34) {
      _error('print currently requires a string literal');
    }
    final quote = source.codeUnitAt(position++);
    if (position + 1 < source.length &&
        source.codeUnitAt(position) == quote &&
        source.codeUnitAt(position + 1) == quote) {
      _error('Multiline string literals are not supported');
    }
    final result = StringBuffer();
    while (position < source.length) {
      final c = source.codeUnitAt(position++);
      if (c == quote) return result.toString();
      if (c == 10 || c == 13) _error('Unterminated string literal');
      if (c == 36) _error('String interpolation is not supported');
      if (c != 92) {
        result.writeCharCode(c);
        continue;
      }
      if (position == source.length) _error('Unterminated escape sequence');
      final escape = source[position++];
      final value = switch (escape) {
        'n' => 10,
        'r' => 13,
        't' => 9,
        'b' => 8,
        'f' => 12,
        'v' => 11,
        "'" => 39,
        '"' => 34,
        r'\' => 92,
        r'$' => 36,
        'x' => _hex(2),
        'u' => _unicode(),
        _ => _error('Unsupported escape sequence'),
      };
      result.writeCharCode(value);
    }
    _error('Unterminated string literal');
  }

  int _hex(int length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      if (position == source.length) _error('Incomplete hexadecimal escape');
      final c = source.codeUnitAt(position);
      final digit = c >= 48 && c <= 57
          ? c - 48
          : c >= 65 && c <= 70
          ? c - 55
          : c >= 97 && c <= 102
          ? c - 87
          : -1;
      if (digit < 0) _error('Invalid hexadecimal escape');
      position++;
      result = result * 16 + digit;
    }
    return result;
  }

  int _unicode() {
    if (position == source.length || source[position] != '{') return _hex(4);
    position++;
    var value = 0;
    var digits = 0;
    while (position < source.length && source[position] != '}') {
      if (++digits > 6) _error('Unicode escape has more than six digits');
      value = value * 16 + _hex(1);
    }
    if (digits == 0 || position == source.length || value > 0x10ffff) {
      _error('Invalid Unicode escape');
    }
    position++;
    return value;
  }

  Never _error(String message) =>
      throw FormatException(message, source, position);
}
