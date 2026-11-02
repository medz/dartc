part of 'scanner.dart';

final class _Interpolation(
  final int stringStart,
  final int quote,
  final int width,
  final int interpolationStart,
) {
  int braceDepth = 0;
}

extension _LiteralScanning on _Scanner {
  void _number() {
    final start = _offset;
    if (_peek() == 0x30 && (_peek(1) == 0x78 || _peek(1) == 0x58)) {
      _offset += 2;
      if (!_digits(hex: true)) {
        _report(
          'scanner.missing_hex_digit',
          'Expected a hexadecimal digit after the prefix.',
          start,
          _offset,
        );
      }
      _emit(.hexadecimalInteger, start);
      return;
    }
    var kind = TokenKind.integer;
    if (_take(0x2E)) {
      kind = .doubleLiteral;
      _digits();
    } else {
      _digits();
      if (_peek() == 0x2E && _isDigit(_peek(1))) {
        _offset++;
        _digits();
        kind = .doubleLiteral;
      }
    }
    if (_peek() == 0x65 || _peek() == 0x45) {
      final exponent = _offset++;
      if (_peek() == 0x2B || _peek() == 0x2D) _offset++;
      if (!_digits()) {
        _report(
          'scanner.missing_exponent_digit',
          'Expected a digit in the exponent.',
          exponent,
          _offset,
        );
      }
      kind = .doubleLiteral;
    }
    _emit(kind, start);
  }

  bool _digits({bool hex = false}) {
    var found = false;
    while (_offset < _text.length) {
      if (hex ? _isHexDigit(_peek()) : _isDigit(_peek())) {
        found = true;
        _offset++;
      } else if (_peek() == 0x5F) {
        final start = _offset;
        while (_peek() == 0x5F) {
          _offset++;
        }
        if (!found || !(hex ? _isHexDigit(_peek()) : _isDigit(_peek()))) {
          _report(
            'scanner.invalid_digit_separator',
            'Digit separators must occur between digits.',
            start,
            _offset,
          );
        }
      } else {
        break;
      }
    }
    return found;
  }

  void _startString({required bool raw}) {
    final start = _offset;
    if (raw) _offset++;
    final quote = _peek();
    final width = _peek(1) == quote && _peek(2) == quote ? 3 : 1;
    _offset += width;
    _stringContent(start, quote, width, raw: raw, segmentStart: start);
  }

  void _stringContent(
    int start,
    int quote,
    int width, {
    required bool raw,
    required int segmentStart,
  }) {
    while (_offset < _text.length) {
      final code = _peek();
      if (code == quote &&
          (width == 1 || (_peek(1) == code && _peek(2) == code))) {
        _offset += width;
        _emit(
          segmentStart != start ? .stringEnd : .stringLiteral,
          segmentStart,
        );
        return;
      }
      if (width == 1 && _isLineBreak(code)) {
        break;
      }
      if (!raw && code == 0x5C) {
        _escape(width == 3);
      } else if (!raw && code == 0x24) {
        final next = _peek(1);
        if (next != 0x7B && !_isIdentifierStart(next, allowDollar: false)) {
          _report(
            'scanner.invalid_interpolation',
            "Expected an identifier or '{' after the dollar sign.",
            _offset,
            _offset + 1,
          );
          _offset++;
          continue;
        }
        _emit(
          segmentStart != start ? .stringMiddle : .stringStart,
          segmentStart,
        );
        final dollar = _offset++;
        if (_take(0x7B)) {
          _emit(.interpolationStart, dollar);
          _interpolations.add(_Interpolation(start, quote, width, dollar));
          return;
        }
        _emit(.interpolationIdentifier, dollar);
        _identifier(allowDollar: false);
        segmentStart = _offset;
      } else {
        _offset++;
      }
    }
    _report(
      'scanner.unterminated_string',
      'Expected a closing string delimiter.',
      start,
      _offset,
    );
    _emit(segmentStart != start ? .stringEnd : .stringLiteral, segmentStart);
  }

  void _escape(bool multiline) {
    final start = _offset++;
    final code = _peek();
    if (code == -1 || (!multiline && _isLineBreak(code))) return;
    _offset++;
    if (code != 0x78 && code != 0x75) return;
    if (code == 0x75 && _take(0x7B)) {
      var count = 0;
      var value = 0;
      while (_isHexDigit(_peek())) {
        if (count < 6) value = value * 16 + _hexValue(_peek());
        count++;
        _offset++;
      }
      final closed = _take(0x7D);
      if (!closed || count == 0 || count > 6 || value > 0x10FFFF) {
        _report(
          'scanner.invalid_escape',
          'Expected a Unicode escape with one to six hex digits in range 0..10FFFF.',
          start,
          _offset,
        );
      }
    } else {
      final count = code == 0x78 ? 2 : 4;
      var read = 0;
      while (read < count && _isHexDigit(_peek())) {
        read++;
        _offset++;
      }
      if (read != count) {
        _report(
          'scanner.invalid_escape',
          'Expected $count hexadecimal digits in the escape.',
          start,
          _offset,
        );
      }
    }
  }
}

int _hexValue(int code) =>
    _isDigit(code) ? code - 0x30 : (code | 0x20) - 0x61 + 10;
