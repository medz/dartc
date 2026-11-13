import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_callbacks.dart';

final class NativeCallbacks() {
  final _process = DynamicLibrary.process();
  final _plain = NativeAssets(Target.host())
      .open('compiler/native_callbacks_plain');
  late final plain = _plain
      .lookupFunction<
        Pointer<NativeFunction<Float Function(Float)>> Function(),
        Pointer<NativeFunction<Float Function(Float)>> Function()
      >('plainCallback');
  final _library = NativeAssets(Target.host())
      .open('compiler/native_callbacks');
  late final integer = _library
      .lookupFunction<
        Pointer<NativeFunction<Unary>> Function(),
        Pointer<NativeFunction<Unary>> Function()
      >('integerCallback');
  late final alias = _library
      .lookupFunction<
        Pointer<NativeFunction<Unary>> Function(),
        Pointer<NativeFunction<Unary>> Function()
      >('aliasCallback');
  late final mixed = _library
      .lookupFunction<
        Pointer<NativeFunction<Mixed>> Function(),
        Pointer<NativeFunction<Mixed>> Function()
      >('mixedCallback');
  late final compound = _library
      .lookupFunction<
        Pointer<NativeFunction<Change>> Function(),
        Pointer<NativeFunction<Change>> Function()
      >('compoundCallback');
  late final pointer = _library
      .lookupFunction<
        Pointer<NativeFunction<PointerChange>> Function(),
        Pointer<NativeFunction<PointerChange>> Function()
      >('pointerCallback');
  late final empty = _library
      .lookupFunction<
        Pointer<NativeFunction<Void Function(Int64)>> Function(),
        Pointer<NativeFunction<Void Function(Int64)>> Function()
      >('voidCallback');
  late final calls = _library.lookupFunction<Int64 Function(), int Function()>(
    'calls',
  );
  late final reenter = _library
      .lookupFunction<
        Int64 Function(Pointer<NativeFunction<Visitor>>),
        int Function(Pointer<NativeFunction<Visitor>>)
      >('reenter');
  late final thread = _library
      .lookupFunction<
        Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
        Function(),
        Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
        Function()
      >('threadCallback');

  late final allocate = _process
      .lookupFunction<
        Pointer<Void> Function(UintPtr),
        Pointer<Void> Function(int)
      >('malloc');
  late final free = _process
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');

  void close() {
    _plain.close();
    _library.close();
  }
}
