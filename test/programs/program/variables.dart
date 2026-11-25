// assignments nest inside others
int? assignmentsNestInsideOthers() {
  var x = 0, y = 0, z = 0;
  if (1 < 2) {
    x = (y = 4);
    z = -(y += 1);
  }
  return x * 100 + y * 10 - z;
}

// assignments hide behind operators
int? assignmentsHideBehindOperators() {
  var x = 0, y = 0;
  if (1 < 2) {
    x = -(y = 4);
  }
  return y * 10 - x;
}

// a variable may stay unassigned on one side
int? aVariableMayStayUnassignedOnOneSide() {
  var n = 1;
  int x;
  if (n > 0) {
    x = 5;
    n += x;
  }
  return n;
}

// a constant of any type may go unused
int? aConstantOfAnyTypeMayGoUnused() {
  const s = "a";
  return 3;
}

// declared, assigned and stepped
int? declaredAssignedAndStepped() {
  var a = 1, b = 2;
  int c;
  c = a = b + 3;
  a += 2;
  b -= 1;
  c *= 2;
  return a * 1000 + b * 100 + c;
}

// steps before and after
int? stepsBeforeAndAfter() {
  var y = 1;
  final z = y++ + y++ * ++y;
  y--;
  --y;
  return z * 10 + y;
}

// compound assignment reads first
int? compoundAssignmentReadsFirst() {
  int x = 3;
  x += (x = 5) + x;
  return x;
}

// every compound operator
int? everyCompoundOperator() {
  var x = 100;
  x -= 1;
  x *= 3;
  x ~/= 2;
  x %= 50;
  x <<= 4;
  x >>= 1;
  x |= 3;
  x &= 0x7f;
  x ^= 5;
  x >>>= 1;
  var d = 1.0;
  d += 1;
  d /= 4;
  d *= 3;
  d -= 1;
  var b = true;
  b &= false;
  b |= true;
  b ^= false;
  return d == 0.5 && b ? x : 0;
}

// inner variables hide outer ones
int? innerVariablesHideOuterOnes() {
  var x = 1;
  {
    var x = 2;
    x++;
  }
  return x;
}

// a variable may be assigned later
int? aVariableMayBeAssignedLater() {
  int x;
  bool b;
  if (1 < 2) {
    x = 5;
    b = true;
  } else {
    x = 6;
    b = false;
  }
  return b ? x : 0;
}

void main() {
  print(assignmentsNestInsideOthers()); // expect: 455
  print(assignmentsHideBehindOperators()); // expect: 44
  print(aVariableMayStayUnassignedOnOneSide()); // expect: 6
  print(aConstantOfAnyTypeMayGoUnused()); // expect: 3
  print(declaredAssignedAndStepped()); // expect: 7110
  print(stepsBeforeAndAfter()); // expect: 92
  print(compoundAssignmentReadsFirst()); // expect: 13
  print(everyCompoundOperator()); // expect: 3
  print(innerVariablesHideOuterOnes()); // expect: 1
  print(aVariableMayBeAssignedLater()); // expect: 5
}
