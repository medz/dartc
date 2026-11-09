import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../compiler/fixtures/stack_helpers.dart' show TenNative;
import '../../compiler/fixtures/stack_calls_ffi.dart' show TenDart;
import '../../support/native_assets.dart';

final class StackArguments() {
  final _library = NativeAssets(Target.host()).open('abi/stack_calls');
  late final forward = _library.lookupFunction<TenNative, TenDart>(
    'stack_forward',
  );

  void close() => _library.close();
}
