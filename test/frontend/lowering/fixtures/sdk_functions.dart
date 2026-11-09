import 'dart:async';

import 'sdk_export.dart' as sdk;

int nonnegative(int value) => sdk.RangeError.checkNotNegative(value);

int range(int start, int? end, int length) =>
    RangeError.checkValidRange(start, end, length);

int index(int value, int length) =>
    RangeError.checkValidIndex(value, null, null, length);

int throughValue(int value) {
  final check = RangeError.checkNotNegative;
  return check(value);
}

void ignoredFuture() => unawaited(null);

int checkNotNegative(int value) => value - 5;

int local(int value) => checkNotNegative(value);
