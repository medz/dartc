import '../ast.dart';
import '../constants.dart';
import '../resolve_type.dart';
import '../source.dart';
import '../types.dart';
import '../typing.dart';

// Coverage atoms for the currently represented scalar domains. Other types
// require a total pattern; adding destructuring requires richer spaces.
const int patternSpaceNull = 1;
const int patternSpaceTrue = 2;
const int patternSpaceFalse = 4;
const int patternSpaceOther = 8;
const int patternSpaceAll = 15;

class CheckedPattern {
  final AstPattern syntax;
  final int input;
  int matched;
  int remaining;
  int coverage = 0;
  int tested = -1;
  int variableType = -1;
  ConstantValue? constant;
  List<CheckedPattern> children = const <CheckedPattern>[];

  CheckedPattern(this.syntax, this.input, this.matched, this.remaining);
}

Never patternError(ConstantContext context, int token, String message) {
  var source = context.symbols.program;
  sourceError(source, source.tokens[token], message);
}

int patternRequiredSpace(int type) {
  if (type == tNever) return 0;
  if (type == tNull) return patternSpaceNull;
  var result = typeCanBeNull(type) ? patternSpaceNull : 0;
  return result |
      (typeNonNullable(type) == tBool
          ? patternSpaceTrue | patternSpaceFalse
          : patternSpaceOther);
}

int patternTypeSpace(int input, int tested) {
  var result = typeCanBeNull(tested) ? patternSpaceNull : 0;
  if (typeIsSubtype(tBool, tested))
    result |= patternSpaceTrue | patternSpaceFalse;
  if (input == tVoid) input = tDynamic;
  if (typeIsSubtype(typingNonNull(input), tested)) result |= patternSpaceOther;
  return result;
}

int patternMatchedType(int input, int tested) {
  var type = meetTypes(input, tested);
  return type == tNever && input != tNever ? tested : type;
}

int patternRemainingType(int input, int tested) {
  if (typeIsSubtype(input, tested)) return tNever;
  if (typeCanBeNull(tested)) return typingNonNull(input);
  if (input != tDynamic &&
      input != tVoid &&
      typeCanBeNull(input) &&
      typeIsSubtype(typingNonNull(input), tested))
    return tNull;
  return input;
}

CheckedPattern checkPattern(
  ConstantContext context,
  AstPattern syntax,
  int input,
  List<int> variableTypes,
) {
  var result = CheckedPattern(syntax, input, input, input);
  var kind = syntax.kind;
  if (kind == patternVariable) {
    var type = syntax.type;
    var declared = type == null ? input : resolveType(context.symbols, type);
    result.variableType = declared;
    result.tested = type == null ? -1 : declared;
    result.matched = type == null ? input : patternMatchedType(input, declared);
    result.remaining = type == null
        ? tNever
        : patternRemainingType(input, declared);
    result.coverage = type == null
        ? patternSpaceAll
        : patternTypeSpace(input, declared);
    var binding = syntax.binding;
    if (binding >= 0) {
      if (variableTypes[binding] >= 0 && variableTypes[binding] != declared)
        patternError(
          context,
          syntax.token,
          'logical-or pattern variable types differ',
        );
      variableTypes[binding] = declared;
    }
  } else if (kind == patternConstant || kind == patternRelational) {
    var value = evaluateConstant(
      context,
      syntax.constant!,
      input,
      syntax.constantContext,
    );
    result.constant = value;
    if (kind == patternRelational &&
        typingBinary(
              syntax.text,
              input == tVoid ? tDynamic : input,
              value.type == tVoid ? tDynamic : value.type,
            ) <
            0)
      patternError(
        context,
        syntax.token,
        'invalid relational pattern operands',
      );
    var equality = kind == patternConstant || syntax.text == '==';
    if (value.kind == tNull && (equality || syntax.text == '!=')) {
      if (equality) {
        result.coverage = patternSpaceNull;
        result.matched = tNull;
        result.remaining = typingNonNull(input);
      } else {
        result.coverage =
            patternSpaceTrue | patternSpaceFalse | patternSpaceOther;
        result.matched = typingNonNull(input);
        result.remaining = tNull;
      }
    } else if (value.kind == tBool && equality) {
      result.coverage = value.integer == 0
          ? patternSpaceFalse
          : patternSpaceTrue;
    }
    if (kind == patternRelational) result.coverage = 0;
  } else if (kind == patternAnd || kind == patternOr) {
    var left = checkPattern(context, syntax.children[0], input, variableTypes);
    var next = kind == patternAnd ? left.matched : left.remaining;
    if (next == tNever) next = input;
    var right = checkPattern(context, syntax.children[1], next, variableTypes);
    result.children = <CheckedPattern>[left, right];
    if (kind == patternAnd) {
      result.matched = right.matched;
      result.remaining = joinTypes(left.remaining, right.remaining);
      result.coverage = left.coverage & right.coverage;
    } else {
      result.matched = joinTypes(left.matched, right.matched);
      result.remaining = right.remaining;
      result.coverage = left.coverage | right.coverage;
    }
  } else {
    var type = kind == patternCast
        ? resolveType(context.symbols, syntax.type!)
        : typingNonNull(input);
    result.tested = type;
    var inner = checkPattern(context, syntax.children[0], type, variableTypes);
    result.children = <CheckedPattern>[inner];
    result.matched = inner.matched;
    result.remaining = inner.remaining;
    result.coverage = inner.coverage;
    if (kind == patternNullCheck) {
      result.remaining = joinTypes(tNull, result.remaining);
      result.coverage &= ~patternSpaceNull;
    } else if (kind == patternNullAssert) {
      result.coverage |= patternSpaceNull;
    } else if (kind == patternCast &&
        (inner.coverage & patternRequiredSpace(type)) ==
            patternRequiredSpace(type)) {
      result.coverage = patternSpaceAll;
    }
  }
  return result;
}
