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
  bool castInput = false;
  ConstantValue? constant;
  // Ordinals of enum values matched when the pattern does not cover the whole
  // input type.
  List<int> enumValues = const <int>[];
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

// The number of values of an enum type, or -1 for any other type.
int patternEnumCount(ConstantContext context, int type) {
  type = typeNonNullable(type);
  if (!typeIsClass(type)) return -1;
  final syntax = context.classes[typeArgument(type)];
  return syntax.isEnum ? syntax.enumValues.length : -1;
}

// Whether the matched ordinals include every value of the enum type.
bool patternEnumCovers(ConstantContext context, int type, List<int> ordinals) {
  final count = patternEnumCount(context, type);
  if (count < 0) return false;
  final seen = List<bool>.filled(count, false);
  for (final ordinal in ordinals) seen[ordinal] = true;
  for (final covered in seen) if (!covered) return false;
  return true;
}

List<int> _patternUnion(List<int> left, List<int> right) => <int>[
  ...left,
  ...right,
];

// A side whose coverage includes the whole domain constrains nothing.
List<int> _patternIntersection(CheckedPattern left, CheckedPattern right) {
  if ((left.coverage & patternSpaceOther) != 0) return right.enumValues;
  if ((right.coverage & patternSpaceOther) != 0) return left.enumValues;
  final result = <int>[];
  for (final ordinal in left.enumValues)
    for (final other in right.enumValues)
      if (ordinal == other) result.add(ordinal);
  return result;
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

int patternContextType(
  ConstantContext context,
  AstPattern syntax,
  List<int> variableTypes,
) {
  var kind = syntax.kind;
  if (kind == patternAssignedVariable) return variableTypes[syntax.binding];
  if (kind == patternVariable)
    return syntax.type == null
        ? typeSchemaHole()
        : resolveType(context.symbols, syntax.type!, context.typeScope);
  if (kind == patternObject)
    return resolveType(context.symbols, syntax.type!, context.typeScope);
  if (kind == patternCast) return typeSchemaHole();
  if (kind == patternNullAssert)
    return nullableType(
      patternContextType(context, syntax.children[0], variableTypes),
    );
  if (kind == patternAnd)
    return meetTypes(
      patternContextType(context, syntax.children[0], variableTypes),
      patternContextType(context, syntax.children[1], variableTypes),
    );
  if (kind == patternList) {
    if (syntax.type != null)
      return listType(
        resolveType(context.symbols, syntax.type!, context.typeScope),
      );
    var element = typeSchemaHole();
    for (var child in syntax.children) {
      var hint = typeSchemaHole();
      if (child.kind == patternRest) {
        if (child.children.isEmpty) continue;
        hint = patternContextType(context, child.children[0], variableTypes);
        if (!typeIsList(hint)) continue;
        hint = typeArgument(hint);
      } else {
        hint = patternContextType(context, child, variableTypes);
      }
      element = meetTypes(element, hint);
    }
    return listType(element);
  }
  return typeSchemaHole();
}

CheckedPattern checkPattern(
  ConstantContext context,
  AstPattern syntax,
  int input,
  List<int> variableTypes,
  CheckedMemberRead Function(int, String, int) readMember, [
  bool irrefutable = false,
]) {
  var result = CheckedPattern(syntax, input, input, input);
  var kind = syntax.kind;
  if (kind == patternVariable || kind == patternAssignedVariable) {
    var type = syntax.type;
    var assigned = kind == patternAssignedVariable;
    var declared = assigned
        ? variableTypes[syntax.binding]
        : type == null
        ? (input == tNull ? tDynamic : input)
        : resolveType(context.symbols, type, context.typeScope);
    var untyped = type == null && !assigned;
    result.variableType = declared;
    result.tested = untyped ? -1 : declared;
    result.matched = untyped ? input : patternMatchedType(input, declared);
    result.remaining = untyped ? tNever : patternRemainingType(input, declared);
    result.coverage = untyped
        ? patternSpaceAll
        : patternTypeSpace(input, declared);
    var binding = syntax.binding;
    if (binding >= 0 && !assigned) {
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
      element = resolveType(context.symbols, syntax.type!, context.typeScope);
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
        irrefutable,
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
        irrefutable,
      );
      result.children = <CheckedPattern>[child];
      result.coverage = child.coverage;
      result.lengths = child.lengths;
      result.remaining = child.remaining;
    }
  } else if (kind == patternObject) {
    var type = resolveObjectPatternType(
      context.symbols,
      syntax.type!,
      input,
      context.typeScope,
    );
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
        irrefutable,
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
    var expression = syntax.constant!;
    // SDK 3.13 also supplies the matched namespace for <, <=, > and >=.
    if (kind == patternRelational &&
        expression.kind == astStaticShorthand &&
        expression.text != '()')
      expression = resolveStaticShorthand(context.symbols, expression, input);
    var value = evaluateConstant(
      context,
      expression,
      kind == patternConstant
          ? input
          : syntax.text == '==' || syntax.text == '!='
          ? nullableType(tObject)
          : typingBinaryContext(syntax.text, input, -1),
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
    } else if (equality &&
        value.type == typeNonNullable(input) &&
        patternEnumCount(context, input) >= 0) {
      result.enumValues = <int>[value.elements[0].integer];
    }
    if (kind == patternRelational) result.coverage = 0;
  } else if (kind == patternAnd || kind == patternOr) {
    var left = checkPattern(
      context,
      syntax.children[0],
      input,
      variableTypes,
      readMember,
      irrefutable,
    );
    var next = kind == patternAnd ? left.matched : left.remaining;
    if (next == tNever) next = input;
    var right = checkPattern(
      context,
      syntax.children[1],
      next,
      variableTypes,
      readMember,
      irrefutable,
    );
    result.children = <CheckedPattern>[left, right];
    if (kind == patternAnd) {
      result.matched = right.matched;
      result.remaining = joinTypes(left.remaining, right.remaining);
      result.coverage = left.coverage & right.coverage;
      result.enumValues = _patternIntersection(left, right);
    } else {
      result.matched = joinTypes(left.matched, right.matched);
      result.remaining = right.remaining;
      result.coverage = left.coverage | right.coverage;
      result.lengths = <PatternLengthRange>[...left.lengths, ...right.lengths];
      result.enumValues = _patternUnion(left.enumValues, right.enumValues);
    }
  } else {
    var type = kind == patternCast
        ? resolveType(context.symbols, syntax.type!, context.typeScope)
        : typingNonNull(input);
    result.tested = type;
    var inner = checkPattern(
      context,
      syntax.children[0],
      type,
      variableTypes,
      readMember,
      irrefutable,
    );
    result.children = <CheckedPattern>[inner];
    result.matched = inner.matched;
    result.remaining = inner.remaining;
    result.coverage = inner.coverage;
    result.lengths = inner.lengths;
    result.enumValues = inner.enumValues;
    if (kind == patternNullCheck) {
      result.remaining = joinTypes(tNull, result.remaining);
      result.coverage &= ~patternSpaceNull;
    } else if (kind == patternNullAssert) {
      result.coverage |= patternSpaceNull;
    } else if (kind == patternCast && patternIsTotal(inner)) {
      result.coverage = patternSpaceAll;
    }
  }
  if (irrefutable &&
      result.tested >= 0 &&
      (kind == patternVariable ||
          kind == patternAssignedVariable ||
          kind == patternList ||
          kind == patternObject)) {
    if (input == tDynamic)
      result.castInput = result.tested != tDynamic;
    else if (!typeIsSubtype(input, result.tested))
      patternError(
        context,
        syntax.token,
        'matched value is not assignable to pattern type',
      );
  }
  if (patternLengthsCover(result.lengths, input)) {
    result.remaining =
        typeCanBeNull(input) && (result.coverage & patternSpaceNull) == 0
        ? tNull
        : tNever;
  }
  return result;
}
