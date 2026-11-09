import 'dart:ffi';

import 'effects.dart';

typedef NativeUnary = Int64 Function(Int8);
typedef DartUnary = int Function(int);
typedef FunctionPointer = Pointer<NativeFunction<NativeUnary>>;
const _leaf = 1 + 1 == 2;

DartUnary bind(int address) =>
    FunctionPointer.fromAddress(address).asFunction<DartUnary>();

DartUnary inferred(int address) =>
    FunctionPointer.fromAddress(address).asFunction();

DartUnary leaf(int address) =>
    NativeFunctionPointer(FunctionPointer.fromAddress(address))
        .asFunction<DartUnary>(isLeaf: _leaf);

double Function(double) floating(
  Pointer<NativeFunction<Float Function(Double)>> pointer,
) => pointer.asFunction();

void Function() empty(Pointer<NativeFunction<Void Function()>> pointer) =>
    pointer.asFunction();

Pointer<NativeType> Function(Pointer<Int64>) widenedPointer(
  Pointer<NativeFunction<Pointer<Int64> Function(Pointer<Int64>)>> pointer,
) => pointer.asFunction();

DartUnary capture(int address, int replacement) {
  var pointer = FunctionPointer.fromAddress(address);
  final function = pointer.asFunction<DartUnary>();
  pointer = .fromAddress(replacement);
  tick(pointer.address == replacement ? 1 : -1);
  return function;
}

DartUnary nested(int address) {
  final function = bind(address);
  return (value) => function(value);
}

DartUnary? nullableBinding(int address) {
  final FunctionPointer? pointer = address == 0 ? null : .fromAddress(address);
  return pointer?.asFunction<DartUnary>();
}

int invoke(DartUnary function, int value) => function(value);
int dynamicInvoke(dynamic function, int value) => function(value);

int saved(int first, int second, bool choose, int count, int value) {
  final functions = [bind(first), bind(second)];
  var function = choose ? functions[0] : functions[1];
  var sum = function(value);
  for (var i = 0; i < count; i++) {
    function = functions[i & 1];
    sum += function(value + i);
  }
  return sum;
}

FunctionPointer _receiver(int address) {
  tick(1);
  return .fromAddress(address);
}

int ordered(int address, int value) =>
    _receiver(address).asFunction<DartUnary>()(tick(value));

int nullableCall(int address, int value) =>
    nullableBinding(address)?.call(tick(value)) ?? -1;

int cleanup(int address, int value) {
  try {
    if (value == 0) return 7;
    return 9;
  } finally {
    final function = FunctionPointer.fromAddress(address)
        .asFunction<DartUnary>();
    tick(function(1));
  }
}

extension UserFunction on int {
  T asFunction<T extends Function>({bool isLeaf = false}) =>
      ((int value) => this + value) as T;
}

int custom(int value) => value.asFunction<DartUnary>(isLeaf: probe(2))(3);
