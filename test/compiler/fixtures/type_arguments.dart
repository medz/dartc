import 'dart:async';
import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart'
    show Base, Child, Marked, Box, Projected, churn, value;

typedef Pair = (int, {bool flag});
typedef FunctionA = T Function<T extends num>(T);
typedef FunctionB = U Function<U extends num>(U);
typedef VoidType = void;
typedef Top = Object?;
typedef FutureObject = FutureOr<Object>;

Type typeOf<T>() => T;

class const TypeTag<T>(final int number);

int check<T>(Object? item, int count) {
  var result =
      (item is T ? 1 : 0) | (item is! T ? 2 : 0) | (item is T? ? 4 : 0);
  churn(count);
  try {
    final converted = item as T;
    result |= 8;
    churn(count);
    try {
      result |= identity<T>(converted!, 0) == null ? 0 : 16;
    } on TypeError {
      result |= 32;
    }
  } on TypeError {
    result |= 64;
  } finally {
    result |= 128;
  }
  return result;
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int openChecks(int kind, int mode, int count) {
  final item = value(mode, 17);
  return switch (kind) {
    0 => check<int>(item, count),
    1 => check<double>(item, count),
    2 => check<bool>(item, count),
    3 => check<int?>(item, count),
    4 => check<Null>(item, count),
    5 => check<Never>(item, count),
    6 => check<Base>(item, count),
    7 => check<Child>(item, count),
    8 => check<Box<int>>(item, count),
    9 => check<Box<num>>(item, count),
    10 => check<Box<int?>>(item, count),
    11 => check<Box<Base>>(item, count),
    12 => check<Box<FutureOr<num>>>(item, count),
    13 => check<Box<num Function(int)>>(item, count),
    14 => check<Box<({num n, Object b})>>(item, count),
    15 => check<FutureOr<int?>>(item, count),
    16 => check<dynamic>(item, count),
    17 => check<VoidType>(item, count),
    18 => check<Object>(item, count),
    _ => check<Object?>(item, count),
  };
}

T wordAs<T>(int value, int count) {
  final converted = value as T;
  churn(count);
  return converted;
}

T doubleAs<T>(double value, int count) {
  final converted = value as T;
  churn(count);
  return converted;
}

int? promotedWord<T>(int value, int count) {
  if (value is T) {
    churn(count);
    return value;
  }
  return null;
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int wordCast(int mode, int value, int count) {
  try {
    return switch (mode) {
      0 => wordAs<int>(value, count),
      1 => wordAs<int?>(value, count)!,
      2 => wordAs<num>(value, count) as int,
      4 => promotedWord<int>(value, count) ?? -999,
      5 => promotedWord<num>(value, count) as int,
      6 => promotedWord<double>(value, count) == null ? -999 : 1,
      _ => wordAs<double>(value, count) as int,
    };
  } on TypeError {
    return -999;
  }
}

@Export<Double Function(Double, Int64)>()
double doubleCast(double value, int count) => doubleAs<double>(value, count);

class FunctionProjection<T>() extends Box<T Function<U>(U)>;
class LeftProjection<T>() extends Box<List<T?>>;
class RightProjection<T>() implements Box<List<T?>>;
class DiamondProjection<T>()
    extends LeftProjection<T>
    implements RightProjection<T>;
typedef RecursiveResult = X Function<X extends FutureOr<X>>();
typedef RecursiveObject = Object Function<X extends FutureOr<X>>();
typedef RecursiveTop = Object? Function<X extends FutureOr<X>>();
typedef ProjectedResult = FunctionProjection<X> Function<X>();
typedef ExplicitResult = Box<X Function<Y>(Y)> Function<X>();
typedef CapturedResult = Box<Y Function<Y>(X)> Function<X>();

int subtype<T>(Object item, int count) {
  churn(count);
  return item is TypeTag<T> ? 1 : 0;
}

@Export<Int64 Function(Int64)>()
int subtypeStress(int count) {
  var result = 0;
  for (var i = 0; i < count; i++) {
    result += subtype<ExplicitResult>(const TypeTag<ProjectedResult>(1), 0);
  }
  return result;
}

@Export<Int64 Function(Int64, Int64)>()
int subtypeShapes(int mode, int count) => switch (mode) {
  0 => subtype<num Function(int)>(const TypeTag<int Function(num)>(1), count),
  1 => subtype<int Function(num)>(const TypeTag<num Function(int)>(1), count),
  2 => subtype<int Function(int)>(
    const TypeTag<int Function(int, [bool])>(1),
    count,
  ),
  3 => subtype<int Function(int, [bool])>(
    const TypeTag<int Function(int)>(1),
    count,
  ),
  4 => subtype<num Function({required int value})>(
    const TypeTag<int Function({num value})>(1),
    count,
  ),
  5 => subtype<num Function({int value})>(
    const TypeTag<int Function({required num value})>(1),
    count,
  ),
  6 => subtype<num Function({required int value})>(
    const TypeTag<int Function({num value, bool flag})>(1),
    count,
  ),
  7 => subtype<num Function({required int value})>(
    const TypeTag<int Function({num value, required bool flag})>(1),
    count,
  ),
  8 => subtype<num Function<X extends num>()>(
    const TypeTag<X Function<X extends num>()>(1),
    count,
  ),
  9 => subtype<X Function<X extends num>()>(
    const TypeTag<num Function<X extends num>()>(1),
    count,
  ),
  10 => subtype<RecursiveTop>(const TypeTag<RecursiveResult>(1), count),
  11 => subtype<RecursiveObject>(const TypeTag<RecursiveResult>(1), count),
  12 => subtype<ExplicitResult>(const TypeTag<ProjectedResult>(1), count),
  13 => subtype<CapturedResult>(const TypeTag<ProjectedResult>(1), count),
  14 => subtype<void Function<X extends int>()>(
    const TypeTag<void Function<X extends num>()>(1),
    count,
  ),
  15 => subtype<Function>(const TypeTag<RecursiveResult>(1), count),
  16 => subtype<Box<List<num?>>>(
    const TypeTag<DiamondProjection<int>>(1),
    count,
  ),
  17 => subtype<Box<List<int>>>(
    const TypeTag<DiamondProjection<int>>(1),
    count,
  ),
  18 => subtype<RightProjection<num>>(
    const TypeTag<DiamondProjection<int>>(1),
    count,
  ),
  19 => subtype<RightProjection<String>>(
    const TypeTag<DiamondProjection<int>>(1),
    count,
  ),
  _ => subtype<Child>(const TypeTag<DiamondProjection<int>>(1), count),
};

int compareRuntime(Object? object, Type expected, int count) {
  final before = object.runtimeType;
  churn(count);
  return (before == expected ? 1 : 0) |
      (object.runtimeType == expected ? 2 : 0);
}

int heapType<T>(int count) =>
    compareRuntime(typeOf<Box<T>>(), (int).runtimeType, count);

@Export<Int64 Function(Int64, Int64)>()
int runtimeTypes(int mode, int count) {
  if (mode == 23) return heapType<int>(count);
  if (mode == 16) {
    churn(count);
    return null.runtimeType == Null ? 3 : 0;
  }
  if (mode == 17) {
    final pointer = Pointer<Int64>.fromAddress(0);
    churn(count);
    return (pointer.runtimeType == typeOf<Pointer<Never>>() ? 1 : 0) |
        (pointer is Pointer<Double> && pointer.runtimeType != Null ? 2 : 0);
  }
  if (mode == 18) {
    return compareRuntime(
      const TypeTag<List<int>>(7),
      TypeTag<List<int>>,
      count,
    );
  }
  if (mode >= 19 && mode <= 21) {
    churn(count);
    return switch (mode) {
      19 => 1.runtimeType == int ? 3 : 0,
      20 => 1.5.runtimeType == double ? 3 : 0,
      _ => true.runtimeType == bool ? 3 : 0,
    };
  }
  if (mode == 22) {
    return compareRuntime(int, (int).runtimeType, count);
  }
  final expected = switch (mode) {
    0 => int,
    1 => double,
    2 => bool,
    3 => Null,
    4 => Base,
    5 => Child,
    6 => Marked,
    7 => Box<int>,
    8 => Box<num>,
    9 => Box<int?>,
    10 => Projected<int>,
    11 => Box<Child>,
    12 => Box<Base>,
    13 => Box<FutureOr<int>>,
    14 => typeOf<Box<int Function(num)>>(),
    _ => typeOf<Box<({int n, bool b})>>(),
  };
  return compareRuntime(value(mode, 5), expected, count);
}

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
