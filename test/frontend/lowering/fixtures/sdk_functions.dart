import 'dart:async';
import 'dart:collection';

import 'sdk_export.dart' as sdk;

typedef Bounds = RangeError;
int aliasCheck(int value) => Bounds.checkNotNegative(value);

final class _Values(final int value) with ListMixin<int> {
  @override
  int get length => 1;
  @override
  int operator [](int index) => value;
  @override
  set length(int length) => throw UnsupportedError('fixed');
  @override
  void operator []=(int index, int value) => throw UnsupportedError('fixed');
}

int sdkMixin(int value) => _Values(value).first;

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

int errorPayload(int value) => ArgumentError(value).message as int;

int invalidArgument(int value) =>
    ArgumentError.value(value).invalidValue as int;
