import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'doubles.dart'
    show
        BinaryNative,
        BinaryDart,
        UnaryNative,
        UnaryDart,
        MixedNative,
        MixedDart;

final class DoubleLibrary() {
  final _library = NativeAssets(Target.host()).open('compiler/doubles');
  final _storage = NativeAssets(Target.host()).open('compiler/doubles_storage');
  late final memory = _storage.lookup<Int64>('counter');
  late final binary = [
    for (final name in ['add', 'subtract', 'multiply', 'divide'])
      _library.lookupFunction<BinaryNative, BinaryDart>(name),
  ];
  late final negate = _library.lookupFunction<UnaryNative, UnaryDart>('negate');
  late final pressure = _library.lookupFunction<UnaryNative, UnaryDart>(
    'pressure',
  );
  late final constants = [
    for (final name in ['negativeZero', 'tiny', 'infinity', 'nan'])
      _library.lookupFunction<Double Function(), double Function()>(name),
  ];
  late final comparisons = _library
      .lookupFunction<
        Int64 Function(Double, Double),
        int Function(double, double)
      >('comparisons');
  late final rotate = _library
      .lookupFunction<
        Double Function(Double, Double, Int64),
        double Function(double, double, int)
      >('rotate');
  late final mixed = _library.lookupFunction<MixedNative, MixedDart>('mixed');
  late final forward = _library.lookupFunction<MixedNative, MixedDart>(
    'forward',
  );
  late final constantsInCall = _library
      .lookupFunction<
        Double Function(Pointer<Int64>),
        double Function(Pointer<Int64>)
      >('constantsInCall');

  void close() {
    _library.close();
    _storage.close();
  }
}
