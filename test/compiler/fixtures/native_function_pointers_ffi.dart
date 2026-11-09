import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'native_function_pointers.dart';

final class NativeFunctionPointers() {
  final _library = NativeAssets(Target.host())
      .open('compiler/native_function_pointers');

  late final increment = _library.lookup<NativeFunction<UnaryNative>>(
    'increment',
  );
  late final decrement = _library.lookup<NativeFunction<UnaryNative>>(
    'decrement',
  );
  late final factory = _library.lookup<NativeFunction<FactoryNative>>(
    'identity',
  );
  late final identity = _library.lookupFunction<FactoryNative, FactoryNative>(
    'identity',
  );
  late final nested = _library
      .lookupFunction<
        FactoryPointer Function(FactoryPointer),
        FactoryPointer Function(FactoryPointer)
      >('nested');
  late final fromAddress = _library
      .lookupFunction<UnaryPointer Function(Int64), UnaryPointer Function(int)>(
        'fromAddress',
      );
  late final address = _library
      .lookupFunction<Int64 Function(UnaryPointer), int Function(UnaryPointer)>(
        'address',
      );
  late final opaque = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('opaque');
  late final select = _library.lookupFunction<SelectNative, SelectDart>(
    'select',
  );
  late final sameAddress = _library
      .lookupFunction<
        Int64 Function(UnaryPointer, Pointer<Void>),
        int Function(UnaryPointer, Pointer<Void>)
      >('sameAddress');
  late final differentAddress = _library
      .lookupFunction<
        Int64 Function(Pointer<Void>, UnaryPointer),
        int Function(Pointer<Void>, UnaryPointer)
      >('differentAddress');

  void close() => _library.close();
}
