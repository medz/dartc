import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_addresses.dart' show AddressState;

const nativeAddressSymbols = {
  'borrowed-addresses': {'memmove': 'memmove'},
};

final class NativeAddresses() {
  final _library = NativeAssets(Target.host())
      .open('compiler/native_addresses');

  late final integerLists = _library
      .lookupFunction<Int64 Function(Int32), int Function(int)>('integerLists');
  late final floatingLists = _library
      .lookupFunction<Double Function(Bool), double Function(bool)>(
        'floatingLists',
      );
  late final compounds = _library
      .lookupFunction<AddressState Function(), AddressState Function()>(
        'compounds',
      );
  late final subviews = _library
      .lookupFunction<Bool Function(), bool Function()>('subviews');
  late final ordered = _library
      .lookupFunction<
        Int64 Function(Pointer<Uint8>, Bool),
        int Function(Pointer<Uint8>, bool)
      >('ordered');

  void close() => _library.close();
}
