import 'dart:collection';
import 'dart:typed_data';

import 'package:dartc/diagnostics.dart';
import 'package:dartc/source.dart';

import 'token_kind.dart';

part 'keywords.dart';
part 'literals.dart';
part 'recovery.dart';
part 'token.dart';

/// Which comments a scan retains alongside its tokens.
enum CommentRetention {
  /// All line and block comments in the source.
  all,

  /// Only comments before the first language token, after any script tag.
  leading,
}

/// Scans [source] using current Dart lexical rules.
///
/// Reports malformed input and continues without rewriting the source or
/// inserting synthetic delimiters. The token list ends with one EOF token.
/// Comments are returned separately; whitespace and a leading BOM are skipped.
/// Tokens from an unterminated string contain only the available source text.
/// Bracket matching, keyword restrictions, language-version selection, and
/// literal value conversion belong to later stages.
ScanResult scan(SourceFile source, {CommentRetention comments = .all}) =>
    _Scanner(source, headerOnly: comments == .leading).scan();

/// Scans a range starting at a normal Dart token boundary outside a string or interpolation.
///
/// Offsets refer to the original snapshot. A token that crosses the requested
/// end is scanned through its lexical boundary, including any interpolations.
/// The EOF offset gives the
/// actual end, which callers can compare with [range].
({TokenSequence tokens, List<Diagnostic> diagnostics}) scanFragment(
  SourceSpan range,
) {
  final scanner = _Scanner(range.source, headerOnly: true)
    .._offset = range.start;
  final result = scanner.scan(range.end);
  return (tokens: result.tokens, diagnostics: result.diagnostics);
}

/// A read-only, random-access sequence of tokens from one scan.
final class TokenSequence._(final List<Token> _items) extends Iterable<Token> {
  /// Returns the token at [index].
  Token operator [](int index) => _items[index];
  @override
  Token elementAt(int index) => _items[index];
  @override
  int get length => _items.length;
  @override
  Token get first => _items.first;
  @override
  Token get last => _items.last;
  @override
  Iterator<Token> get iterator => _items.iterator;
}

/// The immutable tokens, comments, and diagnostics from one source snapshot.
final class ScanResult {
  /// The scanned source snapshot.
  final SourceFile source;

  /// Source-ordered tokens, including a final EOF token.
  final TokenSequence tokens;

  /// Source-ordered line and block comments, including documentation comments.
  final List<Token> comments;

  /// Lexical errors in discovery order.
  final List<Diagnostic> diagnostics;

  ScanResult._(this.source, this.tokens, this.comments, this.diagnostics);

  /// Returns tokens suitable for syntax recovery, preserving lexical diagnostics.
  ///
  /// The strict tokens in this result retain every invalid character.
  ScanResult recovered() {
    if (!hasErrors) return this;
    final reports = [...diagnostics];
    final items = _recoverTokens(this, reports);
    return identical(items, tokens._items)
        ? this
        : ScanResult._(
            source,
            TokenSequence._(items),
            comments,
            UnmodifiableListView(reports),
          );
  }

  /// Whether scanning found a lexical error.
  bool get hasErrors => diagnostics.isNotEmpty;
}

final class _Scanner(
  final SourceFile source, {
  final bool recovering = false,
  final bool headerOnly = false,
}) {
  final String _text = source.text;
  final _tokens = <Token>[];
  final _comments = <Token>[];
  List<Diagnostic>? _diagnostics;
  _Interpolation? _interpolation;
  var _offset = 0;

  ScanResult scan([int? end]) {
    final limit = end ?? _text.length;
    if (_offset == 0 && limit > 0 && _peek() == 0xFEFF) _offset++;
    if (end == null) {
      while (_offset < limit) {
        _token();
      }
    } else {
      while (_offset < _text.length &&
          (_offset < limit || _interpolation != null)) {
        if (_isSpace(_text.codeUnitAt(_offset))) {
          _offset++;
        } else {
          _token();
        }
      }
    }
    for (var state = _interpolation; state != null; state = state.parent) {
      _report(
        'scanner.unterminated_interpolation',
        "Expected '}' to end the string interpolation.",
        state.interpolationStart,
        _offset,
      );
    }
    _emit(.eof, _offset);
    return ScanResult._(
      source,
      TokenSequence._(_tokens),
      _comments.isEmpty ? const [] : UnmodifiableListView(_comments),
      _diagnostics == null ? const [] : UnmodifiableListView(_diagnostics!),
    );
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
    _tokens.add(Token._scanned(kind, source, start, _offset));
  }

  void _report(String code, String message, int start, int end) {
    (_diagnostics ??= []).add(
      Diagnostic(
        code: code,
        severity: .error,
        message: message,
        span: SourceSpan(source, start, end),
      ),
    );
  }

  void _identifier(int first, {bool allowDollar = true}) {
    final start = _offset;
    var end = start + 1;
    final steps = _keywords.steps;
    var state = first < 64 ? 0 : steps[first & 63];
    while (state != 0 && end < _text.length) {
      final code = _text.codeUnitAt(end);
      final next = code >> 6 == 1 ? steps[state * 64 + (code & 63)] : 0;
      if (next == 0) break;
      state = next;
      end++;
    }
    if (end < _text.length &&
        _isIdentifierPart(_text.codeUnitAt(end), allowDollar)) {
      state = 0;
      do {
        end++;
      } while (end < _text.length &&
          _isIdentifierPart(_text.codeUnitAt(end), allowDollar));
    }
    _offset = end;
    _emit(_keywords.kinds[state] ?? .identifier, start);
  }

  void _token() {
    var start = _offset;
    var code = _text.codeUnitAt(start);
    if (_isSpace(code)) {
      do {
        if (++start == _text.length) {
          _offset = start;
          return;
        }
        code = _text.codeUnitAt(start);
      } while (_isSpace(code));
      _offset = start;
    }
    if (code == 0x27 || code == 0x22) {
      _startString(raw: false);
      return;
    }
    if (code == 0x72) {
      final next = _peek(1);
      if (next == 0x27 || next == 0x22) {
        _startString(raw: true);
        return;
      }
    }
    if (_isIdentifierStart(code)) {
      _identifier(code);
      return;
    }
    if (_isDigit(code) || (code == 0x2E && _isDigit(_peek(1)))) {
      _number();
      return;
    }
    if (code == 0x2F) {
      final next = _peek(1);
      if (next == 0x2F || next == 0x2A) {
        _comment(line: next == 0x2F);
        return;
      }
    }
    if (start == 0 && code == 0x23 && _peek(1) == 0x21) {
      _offset = _lineEnd(_offset);
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
        _interpolation?.braceDepth++;
        kind = .leftBrace;
      case 0x7D:
        if (_interpolation case final state?) {
          if (state.braceDepth == 0) {
            _interpolation = state.parent;
            _emit(.interpolationEnd, start);
            _stringContent(
              state.stringStart,
              state.quote,
              state.width,
              raw: false,
              segmentStart: _offset,
            );
            return;
          }
          state.braceDepth--;
        }
        kind = .rightBrace;
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
        if (recovering) {
          switch (_invalidRole(code)) {
            case _InvalidRole.skip:
              return;
            case _InvalidRole.identifier:
              _offset = _identifierEnd(_text, _offset);
              _appendIdentifier(_tokens, source, start, _offset);
              return;
            case _InvalidRole.other:
              break;
          }
        }
    }
    _emit(kind, start);
  }

  int _lineEnd(int offset) {
    while (offset + 2 <= _text.length) {
      if (_isLineBreak(_text.codeUnitAt(offset))) return offset;
      if (_isLineBreak(_text.codeUnitAt(offset + 1))) return offset + 1;
      offset += 2;
    }
    while (offset < _text.length && !_isLineBreak(_text.codeUnitAt(offset))) {
      offset++;
    }
    return offset;
  }

  void _comment({required bool line}) {
    final start = _offset;
    final keep =
        !headerOnly ||
        _tokens.isEmpty ||
        _tokens.length == 1 && _tokens.first.kind == .scriptTag;
    if (line) {
      final end = _lineEnd(start + 2);
      if (keep) _comments.add(Token._scanned(.lineComment, source, start, end));
      _offset = end < _text.length ? end + 1 : end;
      return;
    }
    _offset += 2;
    var depth = 1;
    while (_offset < _text.length && depth > 0) {
      final code = _text.codeUnitAt(_offset);
      if (code == 0x2F && _peek(1) == 0x2A) {
        depth++;
        _offset += 2;
      } else if (code == 0x2A && _peek(1) == 0x2F) {
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
    if (keep) {
      _comments.add(Token._scanned(.blockComment, source, start, _offset));
    }
  }
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

bool _isHexDigit(int code) =>
    _isDigit(code) ||
    (code >= 0x41 && code <= 0x46) ||
    (code >= 0x61 && code <= 0x66);

bool _isIdentifierStart(int code, {bool allowDollar = true}) {
  final lower = code | 0x20;
  return (lower >= 0x61 && lower <= 0x7A) ||
      code == 0x5F ||
      (allowDollar && code == 0x24);
}

bool _isIdentifierPart(int code, bool allowDollar) =>
    _isIdentifierStart(code, allowDollar: allowDollar) || _isDigit(code);

bool _isLineBreak(int code) => code == 0x0A || code == 0x0D;

bool _isSpace(int code) => code == 0x20 || code == 0x09 || _isLineBreak(code);
