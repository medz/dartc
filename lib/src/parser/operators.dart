part of 'parser.dart';

const _assignmentPrecedence = 1;
const _conditionalPrecedence = 2;
const _equalityPrecedence = 6;
const _relationalPrecedence = 7;
const _prefixPrecedence = 14;

extension on TokenKind {
  int get precedence => switch (this) {
    .assign ||
    .starAssign ||
    .slashAssign ||
    .truncateDivideAssign ||
    .percentAssign ||
    .plusAssign ||
    .minusAssign ||
    .shiftLeftAssign ||
    .shiftRightAssign ||
    .unsignedShiftRightAssign ||
    .andAssign ||
    .xorAssign ||
    .orAssign ||
    .ifNullAssign => _assignmentPrecedence,
    .question => _conditionalPrecedence,
    .ifNull => 3,
    .logicalOr => 4,
    .logicalAnd => 5,
    .bar => 8,
    .caret => 9,
    .ampersand => 10,
    .equal || .notEqual => _equalityPrecedence,
    .less || .lessEqual || .greater || .greaterEqual => _relationalPrecedence,
    .shiftLeft || .shiftRight || .unsignedShiftRight => 11,
    .plus || .minus => 12,
    .star || .slash || .truncateDivide || .percent => 13,
    _ => 0,
  };

  BinaryOperator get binaryOperator => switch (this) {
    .plus => .add,
    .minus => .subtract,
    .star => .multiply,
    .slash => .divide,
    .truncateDivide => .truncateDivide,
    .percent => .remainder,
    .shiftLeft => .shiftLeft,
    .shiftRight => .shiftRight,
    .unsignedShiftRight => .unsignedShiftRight,
    .ampersand => .bitwiseAnd,
    .bar => .bitwiseOr,
    .caret => .bitwiseXor,
    .less => .less,
    .lessEqual => .lessEqual,
    .greater => .greater,
    .greaterEqual => .greaterEqual,
    .equal => .equal,
    .notEqual => .notEqual,
    .logicalAnd => .logicalAnd,
    .logicalOr => .logicalOr,
    .ifNull => .ifNull,
    _ => throw StateError('Not a binary operator: $this'),
  };

  AssignmentOperator get assignmentOperator => switch (this) {
    .assign => .assign,
    .starAssign => .multiply,
    .slashAssign => .divide,
    .truncateDivideAssign => .truncateDivide,
    .percentAssign => .remainder,
    .plusAssign => .add,
    .minusAssign => .subtract,
    .shiftLeftAssign => .shiftLeft,
    .shiftRightAssign => .shiftRight,
    .unsignedShiftRightAssign => .unsignedShiftRight,
    .andAssign => .bitwiseAnd,
    .xorAssign => .bitwiseXor,
    .orAssign => .bitwiseOr,
    .ifNullAssign => .ifNull,
    _ => throw StateError('Not an assignment operator: $this'),
  };

  bool get isIdentifier => switch (this) {
    .identifier ||
    .keywordAbstract ||
    .keywordAs ||
    .keywordAsync ||
    .keywordAwait ||
    .keywordBase ||
    .keywordCovariant ||
    .keywordDeferred ||
    .keywordDynamic ||
    .keywordExport ||
    .keywordExtension ||
    .keywordExternal ||
    .keywordFactory ||
    .keywordFunction ||
    .keywordGet ||
    .keywordHide ||
    .keywordImplements ||
    .keywordImport ||
    .keywordInterface ||
    .keywordLate ||
    .keywordLibrary ||
    .keywordMixin ||
    .keywordOf ||
    .keywordOn ||
    .keywordOperator ||
    .keywordPart ||
    .keywordRequired ||
    .keywordSealed ||
    .keywordSet ||
    .keywordShow ||
    .keywordStatic ||
    .keywordSync ||
    .keywordType ||
    .keywordTypedef ||
    .keywordWhen ||
    .keywordYield => true,
    _ => false,
  };
}
