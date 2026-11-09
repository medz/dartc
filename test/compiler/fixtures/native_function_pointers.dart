import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef UnaryNative = Int64 Function(Int8);
typedef UnaryPointer = Pointer<NativeFunction<UnaryNative>>;
typedef FactoryNative = UnaryPointer Function(UnaryPointer);
typedef FactoryPointer = Pointer<NativeFunction<FactoryNative>>;

@Export<UnaryNative>()
int increment(int value) => value + 7;

@Export<UnaryNative>()
int decrement(int value) => value - 11;

@Export<FactoryNative>()
UnaryPointer identity(UnaryPointer pointer) => relay(pointer);

UnaryPointer relay(UnaryPointer pointer) => pointer;

@Export<FactoryPointer Function(FactoryPointer)>()
FactoryPointer nested(FactoryPointer pointer) => pointer;

@Export<UnaryPointer Function(Int64)>()
UnaryPointer fromAddress(int address) => .fromAddress(address);

@Export<Int64 Function(UnaryPointer)>()
int address(UnaryPointer pointer) => pointer.address;

@Export<Pointer<Void> Function(Pointer<Void>)>()
Pointer<Void> opaque(Pointer<Void> pointer) => pointer;

// Dart pointer equality compares addresses regardless of element types.
@Export<Int64 Function(UnaryPointer, Pointer<Void>)>()
int sameAddress(UnaryPointer left, Pointer<Void> right) =>
    // ignore: unrelated_type_equality_checks
    left == right ? 1 : 0;

@Export<Int64 Function(Pointer<Void>, UnaryPointer)>()
int differentAddress(Pointer<Void> left, UnaryPointer right) =>
    // ignore: unrelated_type_equality_checks
    left != right ? 1 : 0;

typedef SelectNative = UnaryPointer Function(
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  Int64,
);
typedef SelectDart = UnaryPointer Function(
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  UnaryPointer,
  int,
);

@Export<SelectNative>()
UnaryPointer select(
  UnaryPointer a,
  UnaryPointer b,
  UnaryPointer c,
  UnaryPointer d,
  UnaryPointer e,
  UnaryPointer f,
  UnaryPointer g,
  UnaryPointer h,
  UnaryPointer i,
  UnaryPointer j,
  int count,
) {
  final saved = j;
  var left = a, right = i;
  for (var k = 0; k < count; k++) {
    final old = left;
    left = relay(right);
    right = old;
  }
  return count < 0 ? saved : left;
}
