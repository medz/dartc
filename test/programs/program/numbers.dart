// harmless constants
int? harmlessConstants() {
  var x = 5;
  return (x << 0) * 10 + x ~/ 1 + x % 1;
}

// int meets double
int? intMeetsDouble() {
  var n = 0;
  if (1 + 0.5 == 1.5) n += 1;
  if (0.5 + 1 == 1.5) n += 2;
  if (7 / 2 == 3.5) n += 4;
  if (9007199254740993 == 9007199254740992.0) n += 8;
  if (1 < 1.5) n += 16;
  if (5 % 3.5 == 1.5) n += 32;
  if (-5.5 % 2 == 0.5) n += 64;
  return n;
}

// bool operators
int? boolOperators() {
  var a = true;
  return (a & false) | (a ^ false) && !(a == false) ? 1 : 0;
}

void main() {
  print(harmlessConstants()); // expect: 55
  print(intMeetsDouble()); // expect: 127
  print(boolOperators()); // expect: 1
}
