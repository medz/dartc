import 'dart:ffi';

import 'package:dartc/interop.dart';

import 'type_checks.dart' show churn;

final class Box<T>(final T value);

T relay<T>(T value) => value;

@Export<Int64 Function(Pointer<Int64>, Int64)>()
int pointerValues(Pointer<Int64> pointer, int count) {
  final Object view = relay(pointer);
  final box = Box<Pointer<Int64>>(pointer);
  late Pointer<Int64> lazy = box.value;
  Pointer<Int64> read() => lazy;
  Object? Function() wide = read;
  final same = identical;
  churn(count);
  var flags = same(pointer, view) && same(wide(), pointer) ? 1 : 0;
  if (same(box.value, pointer)) flags |= 2;
  final other = Pointer<Int64>.fromAddress(pointer.address);
  final Object otherView = other;
  if (pointer == other && view == otherView && !same(pointer, other)) {
    flags |= 4;
  }
  if (pointer.hashCode == other.hashCode &&
      view.hashCode == pointer.address.hashCode) {
    flags |= 8;
  }
  if (view is Pointer<Double> &&
      (view as Pointer<Int64>).address == pointer.address) {
    flags |= 16;
  }
  if (pointer.runtimeType == Pointer<Never>) flags |= 32;
  lazy = pointer + 2;
  churn(count);
  if (read().address == pointer.address + 16 && !same(read(), pointer)) {
    flags |= 64;
  }
  try {
    relay<Object>(1) as Pointer<Int64>;
  } on TypeError {
    if (same(view, pointer)) flags |= 128;
  }
  final nullable = relay<Pointer<Int64>?>(pointer);
  if (same(nullable, pointer) && nullable != null && !same(pointer, null)) {
    flags |= 256;
  }
  return flags;
}

Pointer<Int64>? savedPointer;
Object? savedView;

@Export<Int64 Function(Int64, Int64, Int64)>()
int persistentPointer(int mode, int address, int count) {
  if (mode == 0) {
    savedPointer = Pointer<Int64>.fromAddress(address);
    savedView = relay(savedPointer);
  }
  churn(count);
  return identical(savedPointer, savedView) && savedPointer!.address == address
      ? 1
      : 0;
}

@Export<Int64 Function(Int64, Int64, Double, Double)>()
int scalarIdentity(int a, int b, double x, double y) {
  final same = identical;
  final Object left = a, right = b, first = x, second = y;
  return (identical(a, b) ? 1 : 0) |
      (same(left, right) ? 2 : 0) |
      (identical(x, y) ? 4 : 0) |
      (same(first, second) ? 8 : 0) |
      (!same(left, first) ? 16 : 0) |
      (same(null, null) && same(true, true) && !same(true, 1) ? 32 : 0);
}

typedef EchoNative = Pointer<Void> Function(Pointer<Void>);
typedef EchoDart = Pointer<Void> Function(Pointer<Void>);

EchoDart convert(Pointer<NativeFunction<EchoNative>> address) =>
    address.asFunction<EchoDart>();

@Export<
  Int64 Function(Pointer<NativeFunction<EchoNative>>, Pointer<Void>, Int64)
>()
int indirectPointer(
  Pointer<NativeFunction<EchoNative>> address,
  Pointer<Void> pointer,
  int count,
) {
  final call = convert(address);
  final first = call(pointer);
  final Object view = relay(first);
  churn(count);
  final second = call(first);
  return identical(first, view) &&
          first == second &&
          second.address == pointer.address
      ? 1
      : 0;
}

Pointer<T> reinterpret<T extends NativeType>(Pointer<Void> pointer) =>
    pointer.cast<T>();

final class Caster() {
  int cast<T>() => 7;
}

@Export<Int64 Function(Pointer<Void>, Int64)>()
int pointerCasts(Pointer<Void> pointer, int count) {
  final direct = pointer.cast<Int64>();
  final generic = reinterpret<Double>(pointer);
  final cast = pointer.cast;
  final typed = pointer.cast<Pointer<Int8>>;
  final function = cast<NativeFunction<EchoNative>>;
  churn(count);
  final indirect = typed();
  final opaque = function();
  Pointer<Void>? nullable = pointer.address == 0 ? null : pointer;
  var flags = direct.address == pointer.address ? 1 : 0;
  if (generic.address == pointer.address) flags |= 2;
  if (indirect.address == pointer.address) flags |= 4;
  if (opaque.address == pointer.address) flags |= 8;
  if (nullable?.cast<Int64>().address ==
      (pointer.address == 0 ? null : pointer.address)) {
    flags |= 16;
  }
  final view = reinterpret<Never>(pointer);
  churn(count);
  if (view == pointer && view.runtimeType == Pointer<Never>) flags |= 32;
  final custom = Caster();
  Caster? maybeCaster = pointer.address == 0 ? null : custom;
  final method = maybeCaster?.cast;
  if (method?.call<int>() != (pointer.address == 0 ? null : 7)) return -1;
  if (custom.cast<int>() == 7 && custom.cast<double>() == 7) flags |= 64;
  return flags;
}

typedef NativeBinder = F Function<F extends Function>({bool isLeaf});

NativeBinder retainBinder(Pointer<NativeFunction<EchoNative>> pointer) =>
    pointer.asFunction;

F invokeBinder<F extends Function>(NativeBinder bind, bool leaf) =>
    bind<F>(isLeaf: leaf);

@Export<
  Int64 Function(
    Pointer<NativeFunction<EchoNative>>,
    Pointer<Void>,
    Int64,
    Int64,
  )
>()
int asFunctionValues(
  Pointer<NativeFunction<EchoNative>> pointer,
  Pointer<Void> value,
  int mode,
  int count,
) {
  final bind = retainBinder(pointer);
  final specialized = pointer.asFunction<EchoDart>;
  final explicit = NativeFunctionPointer<EchoNative>(pointer).asFunction;
  Pointer<NativeFunction<EchoNative>>? nullable = pointer.address == 0
      ? null
      : pointer;
  final optional = nullable?.asFunction;
  final dynamic dynamicBind = bind;
  pointer = Pointer.fromAddress(0);
  churn(count);
  try {
    if (mode == 6) {
      final call = bind<Pointer<NativeType> Function(Pointer<Never>)>();
      churn(count);
      return call(value.cast<Never>()) == value ? 1 : 0;
    }
    final call = switch (mode) {
      0 => bind<EchoDart>(),
      1 => specialized(),
      2 => invokeBinder<EchoDart>(bind, count != 0),
      3 => dynamicBind<EchoDart>(isLeaf: count != 0) as EchoDart,
      4 => explicit<EchoDart>(isLeaf: true),
      5 => optional?.call<EchoDart>(),
      _ => bind<EchoDart>.call(isLeaf: false),
    };
    if (call == null) return 2;
    churn(count);
    return call(value) == value ? 1 : 0;
  } on UnsupportedError {
    return -1;
  }
}

@Export<Int64 Function(Int64)>()
int invalidFunctionType(int mode) {
  final bind = Pointer<NativeFunction<Int32 Function(Int32)>>.fromAddress(0)
      .asFunction;
  try {
    switch (mode) {
      case 0:
        bind<int Function(int)>();
      case 1:
        bind<int Function(int?)>();
      case 2:
        bind<num Function(int)>();
      case 3:
        bind<void Function(int)>();
      case 4:
        bind<int Function(num)>();
      case 5:
        bind<double Function(double)>();
      case 6:
        bind<int Function(int, {int? extra})>();
      case 7:
        bind<int Function([int])>();
      case 8:
        bind<int Function<T>(int)>();
      case 9:
        bind<Function>();
      case 10:
        bind<int Function()>();
      case 11:
        bind<int? Function(int)>();
      default:
        bind();
    }
    return 0;
  } on ArgumentError {
    return 1;
  } on UnsupportedError {
    return -1;
  }
}
