import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_floats.dart' show MixedNative, MixedDart;

final class NativeFloats() {
  final _library = NativeAssets(Target.host()).open('compiler/native_floats');
  final _storage = NativeAssets(Target.host())
      .open('compiler/native_floats_storage');
  late final memory = _storage.lookup<Uint8>('counter');
  late final identity = _library
      .lookupFunction<Float Function(Float), double Function(double)>(
        'identity',
      );
  late final widen = _library
      .lookupFunction<Double Function(Float), double Function(double)>('widen');
  late final narrow = _library
      .lookupFunction<Float Function(Double), double Function(double)>(
        'narrow',
      );
  late final internal = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'internal',
      );
  late final fromFloatAddress = _library
      .lookupFunction<
        Pointer<Float> Function(Int64),
        Pointer<Float> Function(int)
      >('fromFloatAddress');
  late final fromDoubleAddress = _library
      .lookupFunction<
        Pointer<Double> Function(Int64),
        Pointer<Double> Function(int)
      >('fromDoubleAddress');
  late final readFloat = _library
      .lookupFunction<
        Double Function(Pointer<Float>),
        double Function(Pointer<Float>)
      >('readFloat');
  late final readDouble = _library
      .lookupFunction<
        Double Function(Pointer<Double>),
        double Function(Pointer<Double>)
      >('readDouble');
  late final writeFloat = _library
      .lookupFunction<
        Double Function(Pointer<Float>, Double),
        double Function(Pointer<Float>, double)
      >('writeFloat');
  late final writeDouble = _library
      .lookupFunction<
        Double Function(Pointer<Double>, Double),
        double Function(Pointer<Double>, double)
      >('writeDouble');
  late final update = _library
      .lookupFunction<
        Double Function(Pointer<Float>, Double),
        double Function(Pointer<Float>, double)
      >('update');
  late final postIncrement = _library
      .lookupFunction<
        Double Function(Pointer<Float>),
        double Function(Pointer<Float>)
      >('postIncrement');
  late final alias = _library
      .lookupFunction<
        Double Function(Pointer<Float>, Pointer<Float>, Double),
        double Function(Pointer<Float>, Pointer<Float>, double)
      >('alias');
  late final mixed = _library.lookupFunction<MixedNative, MixedDart>('mixed');

  void close() {
    _library.close();
    _storage.close();
  }
}
