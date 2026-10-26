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
  if (type == tNull) return tNever;
  return typeNonNullable(type);
}

int typingCoalescing(int left, int right) {
  if (left == tVoid) return -1;
  if (left == tNull) return right;
  return joinTypes(typeNonNullable(left), right);
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

int typingBinary(String op, int left, int right) {
  if (left == tVoid || right == tVoid) return -1;
  if (op == '==' || op == '!=') return tBool;
  if (op == '&&' || op == '||') {
    if (typingCondition(left) && typingCondition(right)) return tBool;
    return -1;
  }
  var arithmetic = op == '+' || op == '-' || op == '*' || op == '%';
  var bitwise = op == '&' || op == '|' || op == '^';
  var shift = op == '<<' || op == '>>' || op == '>>>';
  var comparison = op == '<' || op == '<=' || op == '>' || op == '>=';
  if (!arithmetic && !bitwise && !shift && !comparison && op != '~/') return -1;
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
  if (left != tInt && left != tNum) return -1;
  if (bitwise || shift) {
    if (left == tInt && typingAssignable(right, tInt)) return tInt;
    return -1;
  }
  if (!typingAssignable(right, tNum)) return -1;
  if (comparison) return tBool;
  if (op == '~/') return tInt;
  if (arithmetic) {
    if (left == tInt && right == tInt) return tInt;
    return tNum;
  }
  return -1;
}
