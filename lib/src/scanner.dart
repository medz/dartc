import 'host.dart';

const int tokenSymbol = 0;
const int tokenIdentifier = 1;
const int tokenInteger = 2;
const int tokenString = 3;
const int tokenEnd = 4;

// Source ranges use UTF-16 offsets; end is exclusive.
class Token {
  int kind;
  String text;
  int start;
  int end;
  int source;

  Token(this.kind, this.text, this.start, this.end, this.source);
}

void scanError(String message, int offset) {
  print('dartc: ' + message + ' at offset ' + offset.toString());
  hostExit(1);
}

bool scanDigit(int c) {
  return c >= 48 && c <= 57;
}

bool scanLetter(int c) {
  return c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95 || c == 36;
}

int scanHex(int c, int offset) {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 55;
  if (c >= 97 && c <= 102) return c - 87;
  scanError('invalid hexadecimal digit', offset);
  return 0;
}

List<Token> scanTokens(String source) {
  List<Token> tokens = <Token>[];
  var i = 0;
  while (i < source.length) {
    var tokenStart = i;
    var c = source.codeUnitAt(i);
    if (c <= 32) {
      i++;
      continue;
    }
    if (c == 47 && i + 1 < source.length && source.codeUnitAt(i + 1) == 47) {
      while (i < source.length && source.codeUnitAt(i) != 10) i++;
      continue;
    }
    if (c == 47 && i + 1 < source.length && source.codeUnitAt(i + 1) == 42) {
      i += 2;
      var depth = 1;
      while (i + 1 < source.length && depth > 0) {
        if (source.codeUnitAt(i) == 47 && source.codeUnitAt(i + 1) == 42) {
          depth++;
          i += 2;
        } else if (source.codeUnitAt(i) == 42 &&
            source.codeUnitAt(i + 1) == 47) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) scanError('unterminated comment', tokenStart);
      continue;
    }
    var raw = false;
    if (c == 114 &&
        i + 1 < source.length &&
        (source.codeUnitAt(i + 1) == 39 || source.codeUnitAt(i + 1) == 34)) {
      raw = true;
      i++;
      c = source.codeUnitAt(i);
    }
    if (c == 39 || c == 34) {
      var quote = c;
      var triple =
          i + 2 < source.length &&
          source.codeUnitAt(i + 1) == quote &&
          source.codeUnitAt(i + 2) == quote;
      i++;
      if (triple) i += 2;
      var units = <int>[];
      var closed = false;
      while (i < source.length) {
        c = source.codeUnitAt(i);
        if (c == quote &&
            (!triple ||
                i + 2 < source.length &&
                    source.codeUnitAt(i + 1) == quote &&
                    source.codeUnitAt(i + 2) == quote)) {
          i++;
          if (triple) i += 2;
          closed = true;
          break;
        }
        i++;
        if (!raw && c == 92) {
          if (i == source.length) scanError('unterminated escape', tokenStart);
          c = source.codeUnitAt(i);
          i++;
          if (c == 110) {
            c = 10;
          } else if (c == 114) {
            c = 13;
          } else if (c == 116) {
            c = 9;
          } else if (c == 98) {
            c = 8;
          } else if (c == 102) {
            c = 12;
          } else if (c == 118) {
            c = 11;
          } else if (c == 120 || c == 117) {
            var count = 2;
            if (c == 117) count = 4;
            var braces =
                c == 117 && i < source.length && source.codeUnitAt(i) == 123;
            if (braces) i++;
            c = 0;
            var digits = 0;
            while (i < source.length &&
                (braces && source.codeUnitAt(i) != 125 ||
                    !braces && digits < count)) {
              c = c * 16 + scanHex(source.codeUnitAt(i), i);
              i++;
              digits++;
            }
            if (braces) {
              if (i == source.length)
                scanError('unterminated unicode escape', tokenStart);
              i++;
            }
          }
        }
        if (c > 65535) {
          c -= 65536;
          units.add(55296 + (c >> 10));
          units.add(56320 + (c & 1023));
        } else {
          units.add(c);
        }
      }
      if (!closed) scanError('unterminated string', tokenStart);
      tokens.add(
        Token(tokenString, String.fromCharCodes(units), tokenStart, i, -1),
      );
      continue;
    }
    if (scanLetter(c)) {
      var start = i;
      i++;
      while (i < source.length &&
          (scanLetter(source.codeUnitAt(i)) || scanDigit(source.codeUnitAt(i))))
        i++;
      tokens.add(
        Token(tokenIdentifier, source.substring(start, i), start, i, -1),
      );
      continue;
    }
    if (scanDigit(c)) {
      var start = i;
      i++;
      while (i < source.length &&
          (scanLetter(source.codeUnitAt(i)) || scanDigit(source.codeUnitAt(i))))
        i++;
      tokens.add(Token(tokenInteger, source.substring(start, i), start, i, -1));
      continue;
    }
    var size = 1;
    if (i + 3 < source.length && source.substring(i, i + 4) == '>>>=') {
      size = 4;
    } else if (i + 2 < source.length) {
      var three = source.substring(i, i + 3);
      if (three == '>>>' || three == '<<=' || three == '>>=' || three == '~/=')
        size = 3;
    }
    if (size == 1 && i + 1 < source.length) {
      var two = source.substring(i, i + 2);
      if (two == '=>' ||
          two == '==' ||
          two == '!=' ||
          two == '<=' ||
          two == '>=' ||
          two == '&&' ||
          two == '||' ||
          two == '<<' ||
          two == '>>' ||
          two == '~/' ||
          two == '+=' ||
          two == '-=' ||
          two == '*=' ||
          two == '%=' ||
          two == '&=' ||
          two == '|=' ||
          two == '^=' ||
          two == '++' ||
          two == '--')
        size = 2;
    }
    tokens.add(
      Token(tokenSymbol, source.substring(i, i + size), i, i + size, -1),
    );
    i += size;
  }
  tokens.add(Token(tokenEnd, '', source.length, source.length, -1));
  return tokens;
}
