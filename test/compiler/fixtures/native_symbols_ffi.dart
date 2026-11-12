import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_symbols_types.dart';

final class NativeSymbols(String fixture) {
  final _library = NativeAssets(Target.host()).open('compiler/$fixture');
  late final exchangeInteger = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'exchangeInteger',
      );
  late final storeFloat = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'storeFloat',
      );
  late final readFloat = _library
      .lookupFunction<Double Function(), double Function()>('readFloat');
  late final storeBool = _library
      .lookupFunction<Bool Function(Bool), bool Function(bool)>('storeBool');
  late final integerAddress = _library
      .lookupFunction<Pointer<Int16> Function(), Pointer<Int16> Function()>(
        'integerAddress',
      );
  late final doubleAddress = _library
      .lookupFunction<Pointer<Double> Function(), Pointer<Double> Function()>(
        'doubleAddress',
      );
  late final pointerAddress = _library
      .lookupFunction<
        Pointer<Pointer<Int16>> Function(),
        Pointer<Pointer<Int16>> Function()
      >('pointerAddress');
  late final exchangePointer = _library
      .lookupFunction<
        Pointer<Int16> Function(Pointer<Int16>),
        Pointer<Int16> Function(Pointer<Int16>)
      >('exchangePointer');
  late final storePair = _library
      .lookupFunction<Void Function(NativePair), void Function(NativePair)>(
        'storePair',
      );
  late final readPair = _library
      .lookupFunction<NativePair Function(), NativePair Function()>('readPair');
  late final pairAddress = _library
      .lookupFunction<
        Pointer<NativePair> Function(),
        Pointer<NativePair> Function()
      >('pairAddress');
  late final readConstant = _library
      .lookupFunction<Int64 Function(), int Function()>('readConstant');
  late final functionAddress = _library
      .lookupFunction<
        Pointer<NativeFunction<Int64 Function(Int64)>> Function(),
        Pointer<NativeFunction<Int64 Function(Int64)>> Function()
      >('functionAddress');
  late final callAddress = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('callAddress');

  void close() => _library.close();
}
