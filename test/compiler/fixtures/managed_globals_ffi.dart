import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ManagedGlobals() {
  final _library = NativeAssets(Target.host()).open('compiler/managed_globals');

  late final collect = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('collect');
  late final graph = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('graph');
  late final writeInteger = _library
      .lookupFunction<Void Function(Int64), void Function(int)>('writeInteger');
  late final readInteger = _library
      .lookupFunction<Int64 Function(), int Function()>('readInteger');
  late final writeDouble = _library
      .lookupFunction<Void Function(Double), void Function(double)>(
        'writeDouble',
      );
  late final readDouble = _library
      .lookupFunction<Double Function(), double Function()>('readDouble');
  late final nullableState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'nullableState',
      );
  late final binding = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('binding');
  late final initialization = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'initialization',
      );

  void close() => _library.close();
}
