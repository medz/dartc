import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';
import 'stack_helpers.dart' show TenNative;

typedef TenDart = int Function(
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
);

final class StackCalls() {
  final _library = NativeAssets(Target.host()).open('compiler/stack_calls');
  late final weighted = _library.lookupFunction<TenNative, TenDart>(
    'weighted10',
  );
  late final last = _library.lookupFunction<TenNative, TenDart>('last10');
  late final forward = _library.lookupFunction<TenNative, TenDart>('forward10');
  late final rotate = _library.lookupFunction<TenNative, TenDart>('rotate10');

  void close() => _library.close();
}
