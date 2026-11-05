// ignore_for_file: unnecessary_type_check

import 'dart:async';

class ValueFuture<T>(final T value) implements Future<T> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw 'future member';
}

FutureOr<T> identity<T>(FutureOr<T> value) => value;
FutureOr<int?> checkedBang(FutureOr<int?> value) => value!;

Object? sample(int kind) => switch (kind) {
  0 => 1,
  1 => null,
  2 => 'bad',
  3 => ValueFuture<int>(1),
  4 => ValueFuture<int?>(null),
  _ => ValueFuture<num>(1.5),
};

String classify(int kind) {
  final value = sample(kind);
  return '${value is FutureOr<int>}:${value is FutureOr<int?>}:'
      '${value is FutureOr<int>?}:${value is Future<num>}';
}

String castAndAssert(int kind) {
  final dynamic value = sample(kind);
  final checked = identity<int?>(value);
  final result = checkedBang(checked);
  return '${result is int}:${result is Future<int?>}:${result == null}';
}

Type represented<T>() => FutureOr<T>;
Type typeOf<T>() => T;
Type nullableRepresented<T>() => typeOf<FutureOr<T>?>();
String normalizedTypes() =>
    '${represented<Never>() == Future<Never>}:'
    '${represented<Null>() == typeOf<Future<Null>?>()}:'
    '${represented<Object>() == Object}:'
    '${represented<Object?>() == typeOf<Object?>()}:'
    '${represented<dynamic>() == dynamic}:'
    '${represented<void>() == typeOf<void>()}:'
    '${nullableRepresented<int?>() == represented<int?>()}:'
    '${represented<Future<Object>>() == Future<Object>}:'
    '${represented<FutureOr<int>>() == represented<int>()}:'
    '${represented<Null>().hashCode == typeOf<Future<Null>?>().hashCode}:'
    '${Alpha == Beta}:${typeOf<Alpha>().hashCode == typeOf<Beta>().hashCode}';

typedef Alpha = FutureOr<T> Function<T>(Future<T>);
typedef Beta = FutureOr<U> Function<U>(Future<U>);

Future<Object> sharedView(FutureOr<Future<Object>> value) => value;
String sharedFutureView(bool nested) {
  final inner = ValueFuture<Object>(1);
  final value = sharedView(nested ? ValueFuture<Future<Object>>(inner) : inner);
  return '${value is Future<Object>}:${value is Future<Future<Object>>}';
}

void callSharedFuture(bool nested) {
  final inner = ValueFuture<Object>(1);
  final FutureOr<Future<Object>> either = nested
      ? ValueFuture<Future<Object>>(inner)
      : inner;
  final Future<Object> value = either;
  value.then((x) => x);
}

void widenedFuture(bool nested) {
  final inner = ValueFuture<int>(1);
  final FutureOr<Future<int>> either = nested
      ? ValueFuture<Future<int>>(inner)
      : inner;
  final Future<Object?> value = either;
  value.then((x) => x);
}

void widenedGeneric<T extends FutureOr<Future<int>>>(T source) {
  final Future<Object?> value = source;
  value.then((x) => x);
}

void callWidenedGeneric(bool nested) {
  final inner = ValueFuture<int>(1);
  if (nested) {
    widenedGeneric<ValueFuture<Future<int>>>(ValueFuture<Future<int>>(inner));
  } else {
    widenedGeneric<ValueFuture<int>>(inner);
  }
}

T recursive<T extends FutureOr<T>>(T value) => value;
String recursiveBound() => '${recursive<int>(1)}:${recursive<Null>(null)}';

T bounded<T extends FutureOr<num>>(T value) => value;
String unionBound() =>
    '${bounded<int>(1)}:${bounded<ValueFuture<int>>(ValueFuture<int>(1)) is Future<int>}';

void subtypeMatrix(
  Never a,
  Null b,
  Object c,
  Object? d,
  dynamic e,
  int f,
  int? g,
  num h,
  Future<int> i,
  Future<num> j,
  Future<int?> k,
  Future<int?>? l,
  FutureOr<int> m,
  FutureOr<int>? n,
  FutureOr<int?> o,
  FutureOr<Future<int>> p,
  FutureOr<Future<Object>> q,
  Future<Object> r,
  FutureOr<Never> s,
  FutureOr<Null> t,
  FutureOr<FutureOr<int>> u,
  FutureOr<FutureOr<Null>> v,
  FutureOr<void> w,
  Future<void> x,
  FutureOr<Object> y,
  FutureOr<Object?> z,
) {}

Future<Object?> widen(FutureOr<Future<int>> value) => value;
bool widenedIdentity(bool nested) {
  final inner = ValueFuture<int>(1);
  final FutureOr<Future<int>> value = nested
      ? ValueFuture<Future<int>>(inner)
      : inner;
  return identical(widen(value), value);
}

bool checkNative(dynamic value) => value is Future<int>;
