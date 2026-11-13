import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_callbacks.dart';

final class NativeCallables() {
  final _library = NativeAssets(Target.host())
      .open('compiler/native_callables');
  late final create = _library
      .lookupFunction<
        Pointer<NativeFunction<Unary>> Function(Int64),
        Pointer<NativeFunction<Unary>> Function(int)
      >('create');
  late final releaseLast = _library
      .lookupFunction<Bool Function(), bool Function()>('releaseLast');
  late final mixed = _library
      .lookupFunction<
        Pointer<NativeFunction<Mixed>> Function(Double),
        Pointer<NativeFunction<Mixed>> Function(double)
      >('mixed');
  late final compound = _library
      .lookupFunction<
        Pointer<NativeFunction<Change>> Function(Int64),
        Pointer<NativeFunction<Change>> Function(int)
      >('compound');
  late final thread = _library
      .lookupFunction<
        Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
        Function(),
        Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
        Function()
      >('threadEntry');
  late final _closeAll = _library
      .lookupFunction<Void Function(), void Function()>('closeAll');

  void close() {
    _closeAll();
    _library.close();
  }
}
