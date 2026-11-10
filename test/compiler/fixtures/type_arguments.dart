import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show Box, churn;

typedef Pair = (int, {bool flag});
typedef FunctionA = T Function<T extends num>(T);
typedef FunctionB = U Function<U extends num>(U);
typedef VoidType = void;
typedef Top = Object?;
typedef FutureObject = FutureOr<Object>;

Type typeOf<T>() => T;

int inspect<T>(Type expected, int depth, int count) {
  if (depth > 0) return inspect<T>(expected, depth - 1, count);
  churn(count);
  return T == expected ? 1 : 0;
}

int forward<A, B>(int depth, int count) =>
    inspect<B>(typeOf<A>(), depth, count);

@Export<Int64 Function(Int64, Int64, Int64)>()
int types(int mode, int depth, int count) => switch (mode) {
  0 => forward<int, int>(depth, count),
  1 => forward<int, num>(depth, count),
  2 => forward<double, double>(depth, count),
  3 => forward<int?, int>(depth, count),
  4 => forward<Never?, Null>(depth, count),
  5 => forward<Never, Null>(depth, count),
  6 => forward<Box<int>, Box<num>>(depth, count),
  7 => forward<Pair, (int, {bool flag})>(depth, count),
  8 => forward<FunctionA, FunctionB>(depth, count),
  9 => forward<dynamic, Top>(depth, count),
  10 => forward<VoidType, dynamic>(depth, count),
  11 => forward<FutureObject, Object>(depth, count),
  12 => forward<FutureOr<int>, FutureOr<num>>(depth, count),
  _ => forward<FutureOr<int?>, FutureOr<int?>>(depth, count),
};

int many<A, B, C, D, E, F, G, H, I, J>(
  int a,
  int b,
  double c,
  int depth,
  int count,
) {
  if (depth > 0) {
    return many<A, B, C, D, E, F, G, H, I, J>(a, b, c, depth - 1, count);
  }
  churn(count);
  return a +
      b +
      (c > 0 ? 1 : 0) +
      (A == int ? 2 : 0) +
      (B == double ? 4 : 0) +
      (C == bool ? 8 : 0) +
      (D == Null ? 16 : 0) +
      (E == Never ? 32 : 0) +
      (F == (Box<int>) ? 64 : 0) +
      (G == (Box<num>) ? 128 : 0) +
      (H == Pair ? 256 : 0) +
      (I == FunctionA ? 512 : 0) +
      (J == Top ? 1024 : 0);
}

@Export<Int64 Function(Int64, Int64, Double, Int64, Int64)>()
int stack(int a, int b, double c, int depth, int count) =>
    many<
      int,
      double,
      bool,
      Null,
      Never,
      Box<int>,
      Box<num>,
      Pair,
      FunctionB,
      Top
    >(a, b, c, depth, count);

T identity<T>(T value, int count) {
  churn(count);
  return value;
}

@Export<Int64 Function(Int64, Int64)>()
int integer(int value, int count) => identity<int>(value, count);

@Export<Double Function(Double, Int64)>()
double floating(double value, int count) => identity<double>(value, count);

typedef RecordOf<T> = (T, {Box<T> box, bool flag});
typedef FunctionOf<T> = T Function(T, {required Box<T> item, int count});
typedef FunctionInt = int Function(int, {int count, required Box<int> item});
typedef FunctionRequired = int Function(
  int, {
  required int count,
  required Box<int> item,
});
typedef GenericOf<T> = T Function<U extends num>(U, T);
typedef NestedOf<T> = T Function<U>(U Function<V>(V, U));
typedef NestedInt = int Function<X>(X Function<Y>(Y, X));
typedef CapturedInt = int Function<X>(X Function<Y>(X, Y));
typedef NamedPair<A, B> = void Function({A first, B second});
typedef ReversedPair<A, B> = void Function({B second, A first});

int optional<A, B>(int count) => inspect<A?>(typeOf<B>(), 2, count);
int union<A, B>(int count) => inspect<FutureOr<A>>(typeOf<B>(), 2, count);
int namedOrder<A, B>(int count) =>
    inspect<NamedPair<A, B>>(typeOf<NamedPair<int, bool>>(), 2, count) &
    inspect<ReversedPair<A, B>>(typeOf<NamedPair<int, bool>>(), 2, count);

int shape<T>(int mode, int count) => switch (mode) {
  0 => inspect<Box<T>>(typeOf<Box<int>>(), 2, count),
  1 => inspect<RecordOf<T>>(
    typeOf<(int, {bool flag, Box<int> box})>(),
    2,
    count,
  ),
  2 => inspect<FunctionOf<T>>(FunctionInt, 2, count),
  3 => inspect<FunctionOf<T>>(FunctionRequired, 2, count),
  4 => inspect<GenericOf<T>>(
    typeOf<int Function<X extends num>(X, int)>(),
    2,
    count,
  ),
  5 => inspect<NestedOf<T>>(NestedInt, 2, count),
  _ => inspect<NestedOf<T>>(CapturedInt, 2, count),
};

int grow<T>(Type expected, int depth, int count) {
  if (depth > 0) return grow<Box<T>>(expected, depth - 1, count);
  churn(count);
  return T == expected ? 1 : 0;
}

int unequal<T>(Object? other, int count) {
  churn(count);
  return T != other ? 1 : 0;
}

@Export<Int64 Function(Int64, Int64)>()
int structures(int mode, int count) => switch (mode) {
  0 => optional<int, int?>(count),
  1 => optional<int?, int?>(count),
  2 => optional<Never, Null>(count),
  3 => optional<Null, Null>(count),
  4 => optional<dynamic, dynamic>(count),
  5 => optional<VoidType, VoidType>(count),
  6 => optional<Object, Top>(count),
  7 => optional<FutureOr<int?>, FutureOr<int?>>(count),
  8 => union<Never, Future<Never>>(count),
  9 => union<Null, Future<Null>?>(count),
  10 => union<dynamic, dynamic>(count),
  11 => union<VoidType, VoidType>(count),
  12 => union<Object, Object>(count),
  13 => union<Top, Top>(count),
  14 => union<int, FutureOr<int>>(count),
  15 => union<int?, FutureOr<int?>>(count),
  >= 16 && <= 22 => shape<int>(mode - 16, count),
  23 => grow<int>(typeOf<Box<Box<Box<int>>>>(), 3, count),
  24 => grow<int>(typeOf<Box<Box<int>>>(), 3, count),
  25 => unequal<Box<int>>(typeOf<Box<int>>(), count),
  26 => unequal<Box<int>>(typeOf<Box<num>>(), count),
  27 => unequal<Box<int>>(null, count),
  28 => unequal<Box<int>>(Box<int>(), count),
  _ => namedOrder<int, bool>(count),
};

typedef Bounded<T> = U Function<U extends T>(U);
typedef ConcreteInt = int Function<U extends int>(int);
typedef Empty = Never Function<U extends Never>(Never);
typedef BoundedOptional<T> = U? Function<U extends T>(U?, FutureOr<U>);
typedef EmptyOptional = Null Function<U extends Never>(Null, Future<Never>);
typedef BoundedChain<T> = U Function<V extends T, U extends V>(V, U);
typedef EmptyChain = Never Function<V extends Never, U extends Never>(
  Never,
  Never,
);
typedef BoundedNested<T> = U Function<U extends T>(
  U Function<V extends U>(V, U),
);
typedef EmptyNested = Never Function<U extends Never>(
  Never Function<V extends Never>(Never, Never),
);

int bound<T>(int mode, Type expected, int count) => switch (mode) {
  0 => inspect<Bounded<T>>(expected, 2, count),
  1 => inspect<BoundedOptional<T>>(expected, 2, count),
  2 => inspect<BoundedChain<T>>(expected, 2, count),
  _ => inspect<BoundedNested<T>>(expected, 2, count),
};

int underBound<T extends U, U>(Type expected, int count) =>
    inspect<Bounded<T>>(expected, 2, count);

@Export<Int64 Function(Int64, Int64)>()
int bounds(int mode, int count) => switch (mode) {
  0 => bound<Never>(0, Empty, count),
  1 => bound<int>(0, typeOf<Bounded<int>>(), count),
  2 => bound<int>(0, ConcreteInt, count),
  3 => bound<Null>(0, typeOf<Bounded<Null>>(), count),
  4 => bound<dynamic>(0, typeOf<Bounded<dynamic>>(), count),
  5 => bound<VoidType>(0, typeOf<Bounded<VoidType>>(), count),
  6 => bound<Never>(1, EmptyOptional, count),
  7 => bound<Top>(1, typeOf<BoundedOptional<Top>>(), count),
  8 => bound<Never>(2, EmptyChain, count),
  9 => bound<int>(2, typeOf<BoundedChain<int>>(), count),
  10 => bound<Never>(3, typeOf<BoundedNested<Never>>(), count),
  11 => bound<int>(3, typeOf<BoundedNested<int>>(), count),
  12 => bound<Box<int>>(0, typeOf<Bounded<Box<int>>>(), count),
  13 => bound<FutureOr<Null>>(0, typeOf<Bounded<FutureOr<Null>>>(), count),
  14 => bound<Bounded<int>>(3, typeOf<BoundedNested<Bounded<int>>>(), count),
  15 => underBound<Never, Top>(Empty, count),
  16 => underBound<int, num>(typeOf<Bounded<int>>(), count),
  _ => bound<Never>(3, EmptyNested, count),
};
