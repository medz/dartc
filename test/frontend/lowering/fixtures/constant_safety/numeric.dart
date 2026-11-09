const integer = 9007199254740993;
const floating = 9007199254740992.0;
const unsafeEqual = integer == floating;
const unsafeUnequal = integer != floating;
const unsafeLess = floating < integer;
const unsafeLessEqual = integer <= floating;
const unsafeGreater = integer > floating;
const unsafeGreaterEqual = floating >= integer;
const unsafeSelected = unsafeEqual ? 1 : 2;
const safeExact = 42 == 42.0;
const safeLargeDifferent = integer != 1.0;
const safeZeros = -0.0 == 0;
// ignore: unnecessary_nan_comparison
const safeNaN = double.nan == integer;
const safeStrings = 'value' == 'value';

class const Compared(bool value) {
  final bool value = value;
}

const unsafeNested = Compared(unsafeEqual);
