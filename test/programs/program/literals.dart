// 0
int? case0() {
  return 0;
}

// 1_000
int? case1000() {
  return 1_000;
}

// 0xFF
int? case0xff() {
  return 0xFF;
}

// 0xffffffffffffffff
int? case0xffffffffffffffff() {
  return 0xffffffffffffffff;
}

// -9223372036854775808
int? case9223372036854775808() {
  return -9223372036854775808;
}

// -(0xffffffffffffffff)
int? case0xffffffffffffffffToo() {
  return -(0xffffffffffffffff);
}

// -0x8000000000000000
int? case0x8000000000000000() {
  return -0x8000000000000000;
}

// - 5
int? case5() {
  return -5;
}

// an int literal can be a double
int? anIntLiteralCanBeADouble() {
  double a = 1, b = -0;
  return a / 4 == 0.25 && 1 / b < 0 ? 1 : 0;
}

void main() {
  print(case0()); // expect: 0
  print(case1000()); // expect: 1000
  print(case0xff()); // expect: 255
  print(case0xffffffffffffffff()); // expect: -1
  print(case9223372036854775808()); // expect: -9223372036854775808
  print(case0xffffffffffffffffToo()); // expect: 1
  print(case0x8000000000000000()); // expect: -9223372036854775808
  print(case5()); // expect: -5
  print(anIntLiteralCanBeADouble()); // expect: 1
}
