import 'dart:ffi';

import 'package:dartc/interop.dart';

typedef Unary = Int64 Function(Int64);
typedef Visitor = Int64 Function(Pointer<NativeFunction<Unary>>);
typedef Mixed = Double Function(
  Int8,
  Float,
  Bool,
  Double,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
);

final _calls = <String>[];

int _record(int value) {
  _calls.add('call:$value');
  for (var i = 0; i < 2000; i++) {
    final values = List<int>.filled(16, value + i);
    if (values.first != value + i) throw StateError('lost allocation');
  }
  if (value < 0) throw StateError('callback failure');
  return value * 3;
}

@Export<Pointer<NativeFunction<Unary>> Function()>()
Pointer<NativeFunction<Unary>> integerCallback() =>
    Pointer.fromFunction<Unary>(_record, -70 - 3);

int _identity(int value) => value;
const _intIdentity = _identity;

@Export<Pointer<NativeFunction<Unary>> Function()>()
Pointer<NativeFunction<Unary>> aliasCallback() =>
    Pointer.fromFunction<Unary>(_intIdentity, -1);

double _mixed(
  int a,
  double b,
  bool enabled,
  double c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
  int j,
  int k,
  int l,
) {
  if (!enabled) throw StateError('disabled');
  return a + b + c + d + e + f + g + h + i + j + k + l;
}

@Export<Pointer<NativeFunction<Mixed>> Function()>()
Pointer<NativeFunction<Mixed>> mixedCallback() =>
    Pointer.fromFunction<Mixed>(_mixed, -1.25);

// FFI storage subclasses cannot declare generative constructors.
// ignore: use_primary_constructors
final class CallbackState extends Struct {
  @Int64()
  external int count;
  @Double()
  external double value;
  @Array(2)
  external Array<Int64> entries;
}

typedef Change = CallbackState Function(CallbackState, Bool);
CallbackState _change(Struct source, bool fail) {
  final input = source as CallbackState;
  if (fail) throw StateError('compound failure');
  input.count++;
  input.value *= 2;
  input.entries[1] += input.entries[0];
  return input;
}

@Export<Pointer<NativeFunction<Change>> Function()>()
Pointer<NativeFunction<Change>> compoundCallback() =>
    Pointer.fromFunction<Change>(_change);

typedef PointerChange = Pointer<Int64> Function(Pointer<Int64>, Int64);
Pointer<Int64> _changePointer(Pointer<NativeType> input, int increment) {
  final value = input.cast<Int64>();
  if (increment < 0) throw StateError('pointer failure');
  value.value += increment;
  return value;
}

@Export<Pointer<NativeFunction<PointerChange>> Function()>()
Pointer<NativeFunction<PointerChange>> pointerCallback() =>
    Pointer.fromFunction<PointerChange>(_changePointer);

int _ignore(int value) {
  _calls.add('void:$value');
  if (value < 0) throw StateError('void failure');
  return value;
}

@Export<Pointer<NativeFunction<Void Function(Int64)>> Function()>()
Pointer<NativeFunction<Void Function(Int64)>> voidCallback() =>
    Pointer.fromFunction<Void Function(Int64)>(_ignore);

@Export<Int64 Function()>()
int calls() => _calls.length;

@Export<Int64 Function(Pointer<NativeFunction<Visitor>>)>()
int reenter(Pointer<NativeFunction<Visitor>> visitor) {
  final retained = List<int>.filled(32, 19);
  final result =
      visitor.asFunction<int Function(Pointer<NativeFunction<Unary>>)>()(
        integerCallback(),
      );
  return retained.first + result + retained.last;
}

Pointer<Void> _thread(Pointer<Void> value) => value;

@Export<
  Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>> Function()
>()
Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
threadCallback() =>
    Pointer.fromFunction<Pointer<Void> Function(Pointer<Void>)>(_thread);
