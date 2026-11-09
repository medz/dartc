import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../compiler/fixtures/native_floats.dart' show MixedNative, MixedDart;
import '../../support/native_assets.dart';

typedef _Unary = Int64 Function(Int64);
typedef _Callback = Pointer<NativeFunction<_Unary>>;

final class NativeCalls({
  final bool indirect = false,
  String asset = 'codegen/native_calls',
}) {
  final _library = NativeAssets(Target.host()).open(asset);
  late final memory = _library.lookup<Int64>('memory');
  int _address(String name) => _library.lookup<Void>('provided_$name').address;

  int Function(int) integer(String name) {
    if (!indirect) {
      return _library.lookupFunction<_Unary, int Function(int)>(name);
    }
    final invoke = _library
        .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
          'indirect_$name',
        );
    return (value) => invoke(_address(name), value);
  }

  double Function(double) _floating(String name) {
    if (!indirect) {
      return _library
          .lookupFunction<Double Function(Double), double Function(double)>(
            name,
          );
    }
    final invoke = _library
        .lookupFunction<
          Double Function(Int64, Double),
          double Function(int, double)
        >('indirect_$name');
    return (value) => invoke(_address(name), value);
  }

  late final argumentFloat = _floating('argumentFloat');
  late final resultFloat = _floating('resultFloat');
  late final _pointer = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Int64>),
        Pointer<Int64> Function(Pointer<Int64>)
      >('pointer');
  late final _indirectPointer = _library
      .lookupFunction<
        Pointer<Int64> Function(Int64, Pointer<Int64>),
        Pointer<Int64> Function(int, Pointer<Int64>)
      >('indirect_pointer');
  Pointer<Int64> pointer(Pointer<Int64> value) =>
      indirect ? _indirectPointer(_address('pointer'), value) : _pointer(value);

  late final _write = _library
      .lookupFunction<
        Int64 Function(Pointer<Int64>, Int64),
        int Function(Pointer<Int64>, int)
      >('write');
  late final _indirectWrite = _library
      .lookupFunction<
        Int64 Function(Int64, Pointer<Int64>, Int64),
        int Function(int, Pointer<Int64>, int)
      >('indirect_write');
  int write(Pointer<Int64> pointer, int value) => indirect
      ? _indirectWrite(_address('write'), pointer, value)
      : _write(pointer, value);

  late final _mixed = _library
      .lookupFunction<
        Double Function(Pointer<Double>, Int64, Double),
        double Function(Pointer<Double>, int, double)
      >('mixed');
  late final _indirectMixed = _library
      .lookupFunction<
        Double Function(Int64, Pointer<Double>, Int64, Double),
        double Function(int, Pointer<Double>, int, double)
      >('indirect_mixed');
  double mixed(Pointer<Double> pointer, int integer, double value) => indirect
      ? _indirectMixed(_address('mixed'), pointer, integer, value)
      : _mixed(pointer, integer, value);
  late final providedMixed = _library.lookupFunction<MixedNative, MixedDart>(
    'provided_mixed',
  );
  late final identity = _library.lookup<NativeFunction<_Unary>>(
    'provided_resultInt64',
  );
  late final repeated = _library
      .lookupFunction<
        Int64 Function(
          Int64,
          Int64,
          Int64,
          Int64,
          Int64,
          Int64,
          Int64,
          Int64,
          _Callback,
          _Callback,
        ),
        int Function(
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          int,
          _Callback,
          _Callback,
        )
      >('repeated');

  void close() => _library.close();
}
