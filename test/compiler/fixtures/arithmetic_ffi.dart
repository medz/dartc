import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Arithmetic() {
  final _library = NativeAssets(Target.host()).open('compiler/arithmetic');

  late final add = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'native_add',
      );
  late final reverse = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'reverse',
      );
  late final twice = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('twice');
  late final increment = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('increment');
  late final literal = _library
      .lookupFunction<Int64 Function(), int Function()>('literal');
  late final mixed = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64),
        int Function(int, int, int, int, int, int)
      >('mixed');

  void close() => _library.close();
}
