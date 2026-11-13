import 'dart:core';
import 'dart:core' as core;

const integer = 9007199254740993;
const floating = 9007199254740992.0;
const equal = integer == floating;
const unequal = integer != floating;
const less = floating < integer;
const lessEqual = integer <= floating;
const greater = integer > floating;
const greaterEqual = floating >= integer;
const selected = equal ? 1 : 2;
const exact = 42 == 42.0;
const largeDifferent = integer != 1.0;
const zeros = -0.0 == 0;
const signedDoubleZeros = 0.0 == -0.0;
const distinctZeros = identical(0.0, -0.0);
const mixedIdentity = identical(1, 1.0);
const reversedIdentity = core.identical(1.0, 1);
const roundedIdentity = identical(integer, floating);
const zeroIdentity = core.identical(0, -0.0);
const integerIdentity = identical(integer, integer + 0);
const doubleIdentity = core.identical(floating, floating + 0.0);
const double contextualDouble = 1;
const contextualIdentity = identical(contextualDouble, 1.0);

// ignore: unnecessary_nan_comparison
const nan = double.nan == integer;
const strings = 'value' == 'value';
const maximumLess = 0x7fffffffffffffff < 9223372036854775808.0;
const reverseMaximum = 9223372036854775808.0 > 0x7fffffffffffffff;
const minimumEqual = -0x8000000000000000 == -9223372036854775808.0;
const zeroOrders = 0 >= -0.0 && 0 <= -0.0;
const fractional = -1 < -0.5 && 1 > 0.5;
const infinite = 0 < double.infinity && -double.infinity < 0;
// ignore: unnecessary_nan_comparison
const nanRelations = 0 != double.nan && !(0 < double.nan) && !(double.nan >= 0);

class const Compared(bool value) {
  static const greater = integer > floating;
  static const selected = Compared(greater);
  final bool value = value;
}

const nested = Compared(equal);
const literalNested = Compared(integer == floating);
const Compared abbreviated = .selected;
const record = (integer == floating, greater: integer > floating);
const values = [if (equal) 1 else 2, if (integer > floating) 3];
const mapping = {'result': integer != floating};

bool constructedArgument() => const Compared(integer == floating).value;
bool recordExpression() => (const (integer > floating,)).$1;
bool listExpression() => const [integer > floating][0];
bool mapExpression() => const {'result': integer > floating}['result']!;

class const IdentityBox([final bool value = identical(1, 1.0)]) {
  this : assert(!identical(1, 1.0));
}
