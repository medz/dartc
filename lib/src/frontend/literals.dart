import '../ast.dart';
import '../binary64.dart';
import '../scanner.dart';
import '../source.dart';
import '../types.dart';

bool isNegatedIntegerLiteral(AstExpression expression) {
  return expression.kind == astUnary &&
      expression.text == '-' &&
      expression.children[0].kind == astInteger &&
      // Parentheses remain in token positions even though the AST omits them.
      expression.children[0].token == expression.token + 1;
}

int _literalDigit(int unit) {
  if (scanDigit(unit)) return unit - 48;
  if (unit >= 65 && unit <= 70) return unit - 55;
  if (unit >= 97 && unit <= 102) return unit - 87;
  return -1;
}

int decodeIntegerLiteral(SourceProgram source, AstExpression expression) {
  var negative = expression.kind == astUnary;
  var literal = expression;
  if (negative) literal = expression.children[0];
  var token = source.tokens[literal.token];
  var text = literal.text;
  var hexadecimal =
      text.length >= 2 &&
      text.codeUnitAt(0) == 48 &&
      (text.codeUnitAt(1) == 120 || text.codeUnitAt(1) == 88);
  var position = 0;
  if (hexadecimal) position = 2;
  if (position == text.length)
    sourceError(source, token, 'integer literal requires digits');
  var value = 0;
  var digits = 0;
  var lastDigit = 7;
  if (negative) lastDigit = 8;
  while (position < text.length) {
    var digit = _literalDigit(text.codeUnitAt(position));
    if (digit < 0 || !hexadecimal && digit >= 10)
      sourceError(source, token, 'invalid integer literal');
    if (hexadecimal) {
      if (digits != 0 || digit != 0) digits++;
      if (digits > 16)
        sourceError(source, token, 'integer literal exceeds 64 bits');
      value = (value << 4) | digit;
    } else {
      // Accumulate in the negative domain, where MIN is representable.
      if (value < -922337203685477580 ||
          value == -922337203685477580 && digit > lastDigit)
        sourceError(source, token, 'integer literal is outside int64 range');
      value = value * 10 - digit;
    }
    position++;
  }
  if (hexadecimal) {
    if (negative) {
      if (value < 0 && value != -9223372036854775808)
        sourceError(
          source,
          token,
          'negative integer literal is outside int64 range',
        );
      return -value;
    }
    return value;
  }
  if (negative) return value;
  return -value;
}

int decodeDoubleLiteral(SourceProgram source, AstExpression expression) {
  final value = binary64Parse(expression.text);
  if (value == null)
    sourceError(
      source,
      source.tokens[expression.token],
      'invalid double literal',
    );
  return value;
}

int decodeIntegerAsDouble(SourceProgram source, AstExpression expression) {
  final text = expression.kind == astUnary
      ? '-' + expression.children[0].text
      : expression.text;
  final bits = binary64IntegerLiteral(text);
  if (bits == null)
    sourceError(
      source,
      source.tokens[expression.token],
      'integer literal has no exact double representation',
    );
  return bits;
}

bool doubleContext(int type) => type >= 0 && typeNonNullable(type) == tDouble;
