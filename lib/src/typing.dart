import 'types.dart';

bool typingAssignable(int actual, int expected) {
  if (actual == expected || expected == tVoid) return true;
  return actual != tVoid &&
      (actual == tDynamic || typeIsSubtype(actual, expected));
}

bool typingCondition(int type) {
  return type == tDynamic || typeIsSubtype(type, tBool);
}

bool typingReceiver(int type) {
  return type == tDynamic || !typeCanBeNull(type);
}

int typingNullAssertion(int type) {
  if (type == tVoid) return -1;
  return typingNonNull(type);
}

int typingNonNull(int type) {
  if (type == tNull) return tNever;
  return typeNonNullable(type);
}

int typingCoalescing(int left, int right) {
  if (left == tVoid) return -1;
  if (left == tNull) return right;
  return joinTypes(typeNonNullable(left), right);
}

int typingIterableElement(int type, bool nullAware) {
  if (type == tNever || nullAware && type == tNull) return tNever;
  if (type == tDynamic) return tDynamic;
  if (!nullAware && typeCanBeNull(type)) return -1;
  type = typeNonNullable(typeBound(type));
  if (typeIsList(type)) return typeArgument(type);
  return -1;
}

int typingUnary(String op, int type) {
  if (op == '!') {
    if (typingCondition(type)) return tBool;
  } else if (op == '-') {
    if (type == tDynamic || typeIsSubtype(type, tNum)) return type;
  } else if (op == '~') {
    if (type == tDynamic || typeIsSubtype(type, tInt)) return type;
  }
  return -1;
}

// The receiver is inferred without context. Numeric result context narrows
// only the argument, following the sealed num operator/remainder rules.
int typingBinaryContext(String op, int left, int context) {
  left = typeBound(left);
  if (left == tNever || left == tDynamic) return -1;
  final arithmetic = op == '+' || op == '-' || op == '*' || op == '%';
  final bitwise = op == '&' || op == '|' || op == '^';
  if (left == tString && op == '+') return tString;
  if (left == tBool && bitwise) return tBool;
  if (!typeIsSubtype(left, tNum)) return -1;
  if (bitwise || op == '<<' || op == '>>' || op == '>>>') return tInt;
  if (arithmetic) {
    if (context >= 0 && !typeIsSubtype(tNum, context)) {
      if (typeIsSubtype(tInt, context) && left == tInt) return tInt;
      if (typeIsSubtype(tDouble, context) && left != tDouble) return tDouble;
    }
    return tNum;
  }
  if (op == '/' ||
      op == '~/' ||
      op == '<' ||
      op == '<=' ||
      op == '>' ||
      op == '>=')
    return tNum;
  return -1;
}

int typingBinary(String op, int left, int right) {
  if (left == tVoid || right == tVoid) return -1;
  if (op == '==' || op == '!=') return tBool;
  if (op == '&&' || op == '||') {
    if (typingCondition(left) && typingCondition(right)) return tBool;
    return -1;
  }
  left = typeBound(left);
  right = typeBound(right);
  var arithmetic = op == '+' || op == '-' || op == '*' || op == '%';
  var bitwise = op == '&' || op == '|' || op == '^';
  var shift = op == '<<' || op == '>>' || op == '>>>';
  var comparison = op == '<' || op == '<=' || op == '>' || op == '>=';
  if (!arithmetic &&
      !bitwise &&
      !shift &&
      !comparison &&
      op != '~/' &&
      op != '/')
    return -1;
  if (left == tDynamic) return tDynamic;
  if (left == tNever) return tNever;
  if (left == tString && op == '+') {
    if (typingAssignable(right, tString)) return tString;
    return -1;
  }
  if (left == tBool && bitwise) {
    if (typingAssignable(right, tBool)) return tBool;
    return -1;
  }
  if (left != tInt && left != tDouble && left != tNum) return -1;
  if (bitwise || shift) {
    if (left == tInt && typingAssignable(right, tInt)) return tInt;
    return -1;
  }
  if (!typingAssignable(right, tNum)) return -1;
  if (comparison) return tBool;
  if (op == '~/') return tInt;
  if (op == '/') return tDouble;
  if (arithmetic) {
    if (left == tInt && right == tInt) return tInt;
    if (left == tDouble || right == tDouble) return tDouble;
    return tNum;
  }
  return -1;
}
