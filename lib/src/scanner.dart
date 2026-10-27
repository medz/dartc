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

// Reserved keywords cannot be identifiers; built-in/contextual words can.
bool tokenIsReserved(Token token) {
  if (token.kind != tokenIdentifier) return false;
  var words =
      '|assert|break|case|catch|class|const|continue|default|do|else|enum|extends|false|final|finally|for|if|in|is|new|null|rethrow|return|super|switch|this|throw|true|try|var|void|while|with|';
  return words.indexOf('|' + token.text + '|') >= 0;
}

// Type declaration names exclude built-in identifiers, but retain contextual words.
bool tokenIsTypeDeclarationIdentifier(Token token) {
  if (token.kind != tokenIdentifier || tokenIsReserved(token)) return false;
  var words =
      '|abstract|as|covariant|deferred|dynamic|export|external|extension|factory|Function|get|implements|import|interface|late|library|mixin|operator|part|required|set|static|typedef|';
  return words.indexOf('|' + token.text + '|') < 0;
}

class Scanner {
  String source;
  List<Token> tokens;
  int position;
  int languageMajor = 3;
  int languageMinor = 13;
  int languageOffset = -1;
  String path = '';

  Scanner(this.source, this.tokens, this.position);
}

bool tokenIs(Token token, String text) {
  return (token.kind == tokenSymbol ||
          token.kind == tokenIdentifier ||
          token.kind == tokenEnd) &&
      token.text == text;
}

Never scanError(String message, int offset, [String path = '']) {
  var location = '';
  if (path != '') location = path + ':';
  print('dartc: ' + location + message + ' at offset ' + offset.toString());
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
}

String scanSeparatedInteger(String source, int start, int end) {
  var hexadecimal =
      end - start >= 2 &&
      source.codeUnitAt(start) == 48 &&
      (source.codeUnitAt(start + 1) == 120 ||
          source.codeUnitAt(start + 1) == 88);
  List<int> units = <int>[];
  var digitsStart = start;
  if (hexadecimal) {
    units.add(48);
    units.add(source.codeUnitAt(start + 1));
    digitsStart += 2;
  }
  var i = digitsStart;
  var digit = false;
  while (i < end) {
    var c = source.codeUnitAt(i);
    if (c == 95) {
      var separator = i;
      if (!digit) scanError('digit separators must be between digits', i);
      while (i < end && source.codeUnitAt(i) == 95) i++;
      if (i == end)
        scanError('digit separators must be between digits', separator);
      digit = false;
      continue;
    }
    if (!scanDigit(c) &&
        (!hexadecimal || !(c >= 65 && c <= 70 || c >= 97 && c <= 102))) {
      scanError('invalid integer literal with digit separators', i);
    }
    units.add(c);
    digit = true;
    i++;
  }
  return String.fromCharCodes(units);
}

bool scanVersionAtLeast(Scanner scanner, int major, int minor) {
  return scanner.languageMajor > major ||
      scanner.languageMajor == major && scanner.languageMinor >= minor;
}

int scanComment(String source, int start) {
  var i = start + 2;
  if (source.codeUnitAt(start + 1) == 47) {
    while (i < source.length &&
        source.codeUnitAt(i) != 10 &&
        source.codeUnitAt(i) != 13)
      i++;
    return i;
  }
  var depth = 1;
  while (i + 1 < source.length && depth > 0) {
    if (source.codeUnitAt(i) == 47 && source.codeUnitAt(i + 1) == 42) {
      depth++;
      i += 2;
    } else if (source.codeUnitAt(i) == 42 && source.codeUnitAt(i + 1) == 47) {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }
  if (depth != 0) scanError('unterminated comment', start);
  return i;
}

void scanLanguageVersion(Scanner scanner, int start, int end) {
  if (scanner.languageOffset >= 0) return;
  var source = scanner.source;
  var i = start + 2;
  while (i < end && (source.codeUnitAt(i) == 32 || source.codeUnitAt(i) == 9))
    i++;
  if (i + 5 > end ||
      source.codeUnitAt(i) != 64 ||
      source.codeUnitAt(i + 1) != 100 ||
      source.codeUnitAt(i + 2) != 97 ||
      source.codeUnitAt(i + 3) != 114 ||
      source.codeUnitAt(i + 4) != 116)
    return;
  i += 5;
  while (i < end && (source.codeUnitAt(i) == 32 || source.codeUnitAt(i) == 9))
    i++;
  if (i == end || source.codeUnitAt(i) != 61) return;
  i++;
  while (i < end && (source.codeUnitAt(i) == 32 || source.codeUnitAt(i) == 9))
    i++;
  var digits = i;
  var major = 0;
  while (i < end && scanDigit(source.codeUnitAt(i))) {
    major = major * 10 + source.codeUnitAt(i) - 48;
    i++;
  }
  if (i == digits || i == end || source.codeUnitAt(i) != 46) return;
  i++;
  digits = i;
  var minor = 0;
  while (i < end && scanDigit(source.codeUnitAt(i))) {
    minor = minor * 10 + source.codeUnitAt(i) - 48;
    i++;
  }
  if (i == digits) return;
  while (i < end && (source.codeUnitAt(i) == 32 || source.codeUnitAt(i) == 9))
    i++;
  if (i != end) return;
  scanner.languageMajor = major;
  scanner.languageMinor = minor;
  scanner.languageOffset = start;
}

void scanHeader(Scanner scanner) {
  var source = scanner.source;
  var i = scanner.position;
  if (i == 0 && i < source.length && source.codeUnitAt(i) == 65279) i++;
  if (i == 0 &&
      i + 1 < source.length &&
      source.codeUnitAt(i) == 35 &&
      source.codeUnitAt(i + 1) == 33) {
    while (i < source.length &&
        source.codeUnitAt(i) != 10 &&
        source.codeUnitAt(i) != 13)
      i++;
  }
  while (i < source.length) {
    var c = source.codeUnitAt(i);
    if (c <= 32) {
      i++;
    } else if (c == 47 &&
        i + 1 < source.length &&
        (source.codeUnitAt(i + 1) == 47 || source.codeUnitAt(i + 1) == 42)) {
      var end = scanComment(source, i);
      if (source.codeUnitAt(i + 1) == 47) scanLanguageVersion(scanner, i, end);
      i = end;
    } else {
      break;
    }
  }
  scanner.position = i;
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
    if (c == 47 &&
        i + 1 < source.length &&
        (source.codeUnitAt(i + 1) == 47 || source.codeUnitAt(i + 1) == 42)) {
      i = scanComment(source, i);
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
      var separated = false;
      i++;
      while (i < source.length) {
        var next = source.codeUnitAt(i);
        if (!scanLetter(next) && !scanDigit(next)) break;
        if (next == 95) separated = true;
        i++;
      }
      var text = '';
      if (separated) {
        if (!scanVersionAtLeast(scanner, 3, 6)) {
          scanError(
            'digit separators require language version 3.6',
            start,
            scanner.path,
          );
        }
        text = scanSeparatedInteger(source, start, i);
      } else
        text = source.substring(start, i);
      tokens.add(Token(tokenInteger, text, start, i, -1));
      continue;
    }
    var size = 1;
    var tripleShift = false;
    if (i + 3 < source.length && source.substring(i, i + 4) == '>>>=') {
      size = 4;
      tripleShift = true;
    } else if (i + 2 < source.length) {
      var three = source.substring(i, i + 3);
      tripleShift = three == '>>>';
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
    if (tripleShift && !scanVersionAtLeast(scanner, 2, 14)) size = 2;
    tokens.add(
      Token(tokenSymbol, source.substring(i, i + size), i, i + size, -1),
    );
    if (c == 123) braces++;
    if (c == 125) braces--;
    i += size;
  }
  scanner.position = i;
}

List<Token> scanTokens(Scanner scanner) {
  var source = scanner.source;
  scanCode(scanner, false);
  scanner.tokens.add(Token(tokenEnd, '', source.length, source.length, -1));
  return scanner.tokens;
}
