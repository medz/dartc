import 'dart:collection';

import '../diagnostics/diagnostic.dart';
import '../source/source_file.dart';
import '../source/source_span.dart';
import 'keywords.dart';
import 'token.dart';
import 'token_kind.dart';

part 'literals.dart';

/// Scans [source] using current Dart lexical rules.
///
/// Reports malformed input and continues without rewriting the source or
/// inserting synthetic delimiters. The token list ends with one EOF token.
/// Comments are returned separately; whitespace and a leading BOM are skipped.
/// Tokens from an unterminated string contain only the available source text.
/// Bracket matching, keyword restrictions, language-version selection, and
/// literal value conversion belong to later stages.
ScanResult scan(SourceFile source) => _Scanner(source).scan();

/// The immutable tokens, comments, and diagnostics from one source snapshot.
final class ScanResult {
  /// The scanned source snapshot.
  final SourceFile source;

  /// Source-ordered tokens, including a final EOF token.
  final List<Token> tokens;

  /// Source-ordered line and block comments, including documentation comments.
  final List<Token> comments;

  /// Lexical errors in discovery order.
  final List<Diagnostic> diagnostics;

  // The scanner transfers ownership of these lists.
  ScanResult._(
    this.source,
    List<Token> tokens,
    List<Token> comments,
    List<Diagnostic> diagnostics,
  ) : tokens = UnmodifiableListView(tokens),
      comments = UnmodifiableListView(comments),
      diagnostics = UnmodifiableListView(diagnostics);

  /// Whether scanning found a lexical error.
  bool get hasErrors => diagnostics.isNotEmpty;
}

final class _Scanner(final SourceFile source) {
  final String _text = source.text;
  final _tokens = <Token>[];
  final _comments = <Token>[];
  final _diagnostics = <Diagnostic>[];
  final _strings = <_StringState>[];
  var _offset = 0;

  ScanResult scan() {
    if (_peek() == 0xFEFF) _offset++;
    while (_offset < _text.length) {
      if (_strings.isNotEmpty && !_strings.last.inExpression) {
        _stringContent(_strings.last);
      } else {
        _token();
      }
    }
    while (_strings.isNotEmpty) {
      final state = _strings.removeLast();
      if (state.inExpression) {
        _report(
          'scanner.unterminated_interpolation',
          "Expected '}' to end the string interpolation.",
          state.expressionStart!,
          _offset,
        );
      } else {
        _unterminatedString(state);
      }
    }
    _emit(.eof, _offset);
    return ScanResult._(source, _tokens, _comments, _diagnostics);
  }

  int _peek([int ahead = 0]) {
    final index = _offset + ahead;
    return index < _text.length ? _text.codeUnitAt(index) : -1;
  }

  bool _take(int code) {
    if (_peek() != code) return false;
    _offset++;
    return true;
  }

  void _emit(TokenKind kind, int start) {
    _tokens.add(Token(kind, source, start, _offset));
  }

  void _report(String code, String message, int start, int end) {
    _diagnostics.add(
      Diagnostic(
        code: code,
        severity: .error,
        message: message,
        span: SourceSpan(source, start, end),
      ),
    );
  }

  void _identifier({bool allowDollar = true}) {
    final start = _offset;
    var end = start + 1;
    while (end < _text.length) {
      final code = _text.codeUnitAt(end);
      final lower = code | 0x20;
      if ((lower >= 0x61 && lower <= 0x7A) ||
          (code >= 0x30 && code <= 0x39) ||
          code == 0x5F ||
          (allowDollar && code == 0x24)) {
        end++;
      } else {
        break;
      }
    }
    _offset = end;
    _emit(keywordKind(_text, start, end), start);
  }

  void _token() {
    final start = _offset;
    final code = _peek();
    if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
      var end = _offset + 1;
      while (end < _text.length) {
        final next = _text.codeUnitAt(end);
        if (next != 0x20 && next != 0x09 && next != 0x0A && next != 0x0D) break;
        end++;
      }
      _offset = end;
      return;
    }
    if (code == 0x27 || code == 0x22) {
      _startString(raw: false);
      return;
    }
    if (code == 0x72 && (_peek(1) == 0x27 || _peek(1) == 0x22)) {
      _startString(raw: true);
      return;
    }
    if (_isIdentifierStart(code)) {
      _identifier();
      return;
    }
    if (_isDigit(code) || (code == 0x2E && _isDigit(_peek(1)))) {
      _number();
      return;
    }
    if (code == 0x2F && (_peek(1) == 0x2F || _peek(1) == 0x2A)) {
      _comment();
      return;
    }
    if (start == 0 && code == 0x23 && _peek(1) == 0x21) {
      while (_offset < _text.length && !_isLineBreak(_peek())) {
        _offset++;
      }
      _emit(.scriptTag, start);
      return;
    }

    _offset++;
    final TokenKind kind;
    switch (code) {
      case 0x28:
        kind = .leftParen;
      case 0x29:
        kind = .rightParen;
      case 0x5B:
        kind = !_take(0x5D)
            ? .leftBracket
            : _take(0x3D)
            ? .emptyBracketsAssign
            : .emptyBrackets;
      case 0x5D:
        kind = .rightBracket;
      case 0x7B:
        if (_strings.isNotEmpty) _strings.last.braceDepth++;
        kind = .leftBrace;
      case 0x7D:
        if (_strings.isNotEmpty && _strings.last.braceDepth == 0) {
          final state = _strings.last;
          state.expressionStart = null;
          state.segmentStart = _offset;
          kind = .interpolationEnd;
        } else {
          if (_strings.isNotEmpty) _strings.last.braceDepth--;
          kind = .rightBrace;
        }
      case 0x2C:
        kind = .comma;
      case 0x3A:
        kind = .colon;
      case 0x3B:
        kind = .semicolon;
      case 0x40:
        kind = .at;
      case 0x23:
        kind = .hash;
      case 0x2E:
        kind = !_take(0x2E)
            ? .dot
            : !_take(0x2E)
            ? .cascade
            : _take(0x3F)
            ? .nullAwareSpread
            : .spread;
      case 0x3F:
        if (_take(0x3F)) {
          kind = _take(0x3D) ? .ifNullAssign : .ifNull;
        } else if (_take(0x2E)) {
          kind = _take(0x2E) ? .nullAwareCascade : .nullAwareAccess;
        } else {
          kind = .question;
        }
      case 0x3D:
        kind = _take(0x3D)
            ? .equal
            : _take(0x3E)
            ? .arrow
            : .assign;
      case 0x21:
        kind = _take(0x3D) ? .notEqual : .bang;
      case 0x2B:
        kind = _take(0x2B)
            ? .increment
            : _take(0x3D)
            ? .plusAssign
            : .plus;
      case 0x2D:
        kind = _take(0x2D)
            ? .decrement
            : _take(0x3D)
            ? .minusAssign
            : .minus;
      case 0x2A:
        kind = _take(0x3D) ? .starAssign : .star;
      case 0x2F:
        kind = _take(0x3D) ? .slashAssign : .slash;
      case 0x25:
        kind = _take(0x3D) ? .percentAssign : .percent;
      case 0x7E:
        kind = !_take(0x2F)
            ? .tilde
            : _take(0x3D)
            ? .truncateDivideAssign
            : .truncateDivide;
      case 0x26:
        kind = _take(0x26)
            ? .logicalAnd
            : _take(0x3D)
            ? .andAssign
            : .ampersand;
      case 0x7C:
        kind = _take(0x7C)
            ? .logicalOr
            : _take(0x3D)
            ? .orAssign
            : .bar;
      case 0x5E:
        kind = _take(0x3D) ? .xorAssign : .caret;
      case 0x3C:
        kind = _take(0x3C)
            ? (_take(0x3D) ? .shiftLeftAssign : .shiftLeft)
            : (_take(0x3D) ? .lessEqual : .less);
      case 0x3E:
        if (_take(0x3E)) {
          kind = _take(0x3E)
              ? (_take(0x3D) ? .unsignedShiftRightAssign : .unsignedShiftRight)
              : (_take(0x3D) ? .shiftRightAssign : .shiftRight);
        } else {
          kind = _take(0x3D) ? .greaterEqual : .greater;
        }
      default:
        if (code >= 0xD800 &&
            code <= 0xDBFF &&
            _peek() >= 0xDC00 &&
            _peek() <= 0xDFFF) {
          _offset++;
        }
        kind = .invalid;
        _report(
          'scanner.unexpected_character',
          'Unexpected character in Dart source.',
          start,
          _offset,
        );
    }
    _emit(kind, start);
  }

  void _comment() {
    final start = _offset;
    final line = _peek(1) == 0x2F;
    _offset += 2;
    if (line) {
      while (_offset < _text.length && !_isLineBreak(_peek())) {
        _offset++;
      }
    } else {
      var depth = 1;
      while (_offset < _text.length && depth > 0) {
        if (_peek() == 0x2F && _peek(1) == 0x2A) {
          depth++;
          _offset += 2;
        } else if (_peek() == 0x2A && _peek(1) == 0x2F) {
          depth--;
          _offset += 2;
        } else {
          _offset++;
        }
      }
      if (depth != 0) {
        _report(
          'scanner.unterminated_comment',
          "Expected '*/' to end the block comment.",
          start,
          _offset,
        );
      }
    }
    _comments.add(
      Token(line ? .lineComment : .blockComment, source, start, _offset),
    );
  }
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

bool _isHexDigit(int code) =>
    _isDigit(code) ||
    (code >= 0x41 && code <= 0x46) ||
    (code >= 0x61 && code <= 0x66);

bool _isIdentifierStart(int code, {bool allowDollar = true}) =>
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    code == 0x5F ||
    (allowDollar && code == 0x24);

bool _isLineBreak(int code) => code == 0x0A || code == 0x0D;
