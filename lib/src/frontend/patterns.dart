import '../ast.dart';
import '../constants.dart';
import '../members.dart';
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

class PatternLengthRange {
  final int type;
  final int start;
  final int end;

  PatternLengthRange(this.type, this.start, this.end);
}

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
  List<CheckedMemberRead> fields = const <CheckedMemberRead>[];
  List<PatternLengthRange> lengths = const <PatternLengthRange>[];

  CheckedPattern(this.syntax, this.input, this.matched, this.remaining);
}

int patternListRest(AstPattern syntax) {
  for (var i = 0; i < syntax.children.length; i++)
    if (syntax.children[i].kind == patternRest) return i;
  return -1;
}

bool patternSkipsRead(AstPattern syntax) {
  return syntax.kind == patternVariable &&
      syntax.text == '_' &&
      syntax.type == null;
}

bool patternLengthsCover(List<PatternLengthRange> ranges, int input) {
  input = typeNonNullable(input);
  if (!typeIsList(input)) return false;
  var next = 0;
  while (true) {
    var end = next - 1;
    for (var range in ranges) {
      if (range.start <= next && typeIsSubtype(input, range.type)) {
        if (range.end < 0) return true;
        if (range.end > end) end = range.end;
      }
    }
    if (end < next) return false;
    next = end + 1;
  }
}

bool patternIsTotal(CheckedPattern pattern) {
  var coverage = pattern.coverage;
  if (patternLengthsCover(pattern.lengths, pattern.input))
    coverage |= patternSpaceOther;
  return (coverage & patternRequiredSpace(pattern.input)) ==
      patternRequiredSpace(pattern.input);
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
  CheckedMemberRead Function(int, String, int) readMember,
) {
  var result = CheckedPattern(syntax, input, input, input);
  var kind = syntax.kind;
  if (kind == patternVariable) {
    var type = syntax.type;
    var declared = type == null
        ? (input == tNull ? tDynamic : input)
        : resolveType(context.symbols, type);
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
  } else if (kind == patternList) {
    var element = nullableType(tObject);
    if (syntax.type != null)
      element = resolveType(context.symbols, syntax.type!);
    else if (typeIsList(typeNonNullable(input)))
      element = typeArgument(typeNonNullable(input));
    else if (input == tDynamic)
      element = tDynamic;
    var type = listType(element);
    result.tested = type;
    result.matched = patternMatchedType(input, type);
    result.children = <CheckedPattern>[];
    var total = true;
    var rest = patternListRest(syntax);
    for (var child in syntax.children) {
      var checked = checkPattern(
        context,
        child,
        child.kind == patternRest ? type : element,
        variableTypes,
        readMember,
      );
      result.children.add(checked);
      if (!patternIsTotal(checked)) total = false;
    }
    if (total) {
      var count = syntax.children.length - (rest >= 0 ? 1 : 0);
      result.lengths = <PatternLengthRange>[
        PatternLengthRange(type, count, rest >= 0 ? -1 : count),
      ];
      if (rest >= 0 && count == 0) {
        result.coverage = patternTypeSpace(input, type);
        result.remaining = patternRemainingType(input, type);
      }
    }
  } else if (kind == patternRest) {
    result.coverage = patternSpaceAll;
    result.remaining = tNever;
    if (syntax.children.isNotEmpty) {
      var child = checkPattern(
        context,
        syntax.children[0],
        input,
        variableTypes,
        readMember,
      );
      result.children = <CheckedPattern>[child];
      result.coverage = child.coverage;
      result.lengths = child.lengths;
      result.remaining = child.remaining;
    }
  } else if (kind == patternObject) {
    var type = resolveObjectPatternType(context.symbols, syntax.type!, input);
    result.tested = type;
    result.matched = patternMatchedType(input, type);
    result.children = <CheckedPattern>[];
    result.fields = <CheckedMemberRead>[];
    var total = true;
    for (var field in syntax.fields) {
      var member = readMember(type, field.name, field.token);
      var child = checkPattern(
        context,
        field.pattern,
        member.type,
        variableTypes,
        readMember,
      );
      result.fields.add(member);
      result.children.add(child);
      if (!patternIsTotal(child)) total = false;
    }
    if (total) {
      result.coverage = patternTypeSpace(input, type);
      result.remaining = patternRemainingType(input, type);
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
    var left = checkPattern(
      context,
      syntax.children[0],
      input,
      variableTypes,
      readMember,
    );
    var next = kind == patternAnd ? left.matched : left.remaining;
    if (next == tNever) next = input;
    var right = checkPattern(
      context,
      syntax.children[1],
      next,
      variableTypes,
      readMember,
    );
    result.children = <CheckedPattern>[left, right];
    if (kind == patternAnd) {
      result.matched = right.matched;
      result.remaining = joinTypes(left.remaining, right.remaining);
      result.coverage = left.coverage & right.coverage;
    } else {
      result.matched = joinTypes(left.matched, right.matched);
      result.remaining = right.remaining;
      result.coverage = left.coverage | right.coverage;
      result.lengths = <PatternLengthRange>[...left.lengths, ...right.lengths];
    }
  } else {
    var type = kind == patternCast
        ? resolveType(context.symbols, syntax.type!)
        : typingNonNull(input);
    result.tested = type;
    var inner = checkPattern(
      context,
      syntax.children[0],
      type,
      variableTypes,
      readMember,
    );
    result.children = <CheckedPattern>[inner];
    result.matched = inner.matched;
    result.remaining = inner.remaining;
    result.coverage = inner.coverage;
    result.lengths = inner.lengths;
    if (kind == patternNullCheck) {
      result.remaining = joinTypes(tNull, result.remaining);
      result.coverage &= ~patternSpaceNull;
    } else if (kind == patternNullAssert) {
      result.coverage |= patternSpaceNull;
    } else if (kind == patternCast && patternIsTotal(inner)) {
      result.coverage = patternSpaceAll;
    }
  }
  if (patternLengthsCover(result.lengths, input)) {
    result.remaining =
        typeCanBeNull(input) && (result.coverage & patternSpaceNull) == 0
        ? tNull
        : tNever;
  }
  return result;
}
