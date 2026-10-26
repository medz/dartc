import 'host.dart';

const int tokenSymbol = 0;
const int tokenIdentifier = 1;
const int tokenInteger = 2;
const int tokenString = 3;
const int tokenEnd = 4;
const int tokenStringPart = 5;
const int tokenInterpolationStart = 6;
const int tokenInterpolationEnd = 7;
const int tokenStringTail = 8;

// Source ranges use UTF-16 offsets; end is exclusive.
class Token {
  int kind;
  String text;
  int start;
  int end;
  int source;

  Token(this.kind, this.text, this.start, this.end, this.source);
}

class Scanner {
  String source;
  List<Token> tokens;
  int position;

  Scanner(this.source, this.tokens, this.position);
}

bool tokenIs(Token token, String text) {
  return (token.kind == tokenSymbol ||
          token.kind == tokenIdentifier ||
          token.kind == tokenEnd) &&
      token.text == text;
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

void scanString(Scanner scanner, bool raw, int tokenStart) {
  var source = scanner.source;
  var tokens = scanner.tokens;
  var i = scanner.position;
  var quote = source.codeUnitAt(i);
  var triple =
      i + 2 < source.length &&
      source.codeUnitAt(i + 1) == quote &&
      source.codeUnitAt(i + 2) == quote;
  i++;
  if (triple) i += 2;
  List<int> units = <int>[];
  var interpolated = false;
  var fragment = tokenStart;
  while (i < source.length) {
    var c = source.codeUnitAt(i);
    if (c == quote &&
        (!triple ||
            i + 2 < source.length &&
                source.codeUnitAt(i + 1) == quote &&
                source.codeUnitAt(i + 2) == quote)) {
      i++;
      if (triple) i += 2;
      var kind = tokenString;
      if (interpolated) kind = tokenStringTail;
      tokens.add(Token(kind, String.fromCharCodes(units), fragment, i, -1));
      scanner.position = i;
      return;
    }
    if (!raw &&
        c == 36 &&
        i + 1 < source.length &&
        (source.codeUnitAt(i + 1) == 123 ||
            scanLetter(source.codeUnitAt(i + 1)))) {
      interpolated = true;
      tokens.add(
        Token(tokenStringPart, String.fromCharCodes(units), fragment, i, -1),
      );
      units = <int>[];
      var start = i;
      i++;
      var braced = source.codeUnitAt(i) == 123;
      if (braced) i++;
      tokens.add(Token(tokenInterpolationStart, r'${', start, i, -1));
      if (braced) {
        scanner.position = i;
        scanCode(scanner, true);
        i = scanner.position;
        if (i == source.length) scanError('unterminated interpolation', start);
        tokens.add(Token(tokenInterpolationEnd, '}', i, i + 1, -1));
        i++;
      } else {
        start = i;
        i++;
        while (i < source.length &&
            source.codeUnitAt(i) != 36 &&
            (scanLetter(source.codeUnitAt(i)) ||
                scanDigit(source.codeUnitAt(i))))
          i++;
        tokens.add(
          Token(tokenIdentifier, source.substring(start, i), start, i, -1),
        );
        tokens.add(Token(tokenInterpolationEnd, '}', i, i, -1));
      }
      fragment = i;
      continue;
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
  scanError('unterminated string', tokenStart);
}

void scanCode(Scanner scanner, bool interpolation) {
  var source = scanner.source;
  var tokens = scanner.tokens;
  var i = scanner.position;
  var braces = 0;
  while (i < source.length) {
    var tokenStart = i;
    var c = source.codeUnitAt(i);
    if (c == 125 && interpolation && braces == 0) {
      scanner.position = i;
      return;
    }
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
      scanner.position = i;
      scanString(scanner, raw, tokenStart);
      i = scanner.position;
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
      if (three == '>>>' ||
          three == '<<=' ||
          three == '>>=' ||
          three == '~/=' ||
          three == '??=')
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
          two == '??' ||
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
    if (c == 123) braces++;
    if (c == 125) braces--;
    i += size;
  }
  scanner.position = i;
}

List<Token> scanTokens(String source) {
  var scanner = Scanner(source, <Token>[], 0);
  scanCode(scanner, false);
  scanner.tokens.add(Token(tokenEnd, '', source.length, source.length, -1));
  return scanner.tokens;
}
