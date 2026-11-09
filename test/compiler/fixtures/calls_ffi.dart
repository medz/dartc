import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Calls() {
  final _library = NativeAssets(Target.host()).open('compiler/calls');
  late final calls = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'calls',
      );
  late final repeated = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('repeated');
  late final sameOperands = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('sameOperands');
  late final literalCall = _library
      .lookupFunction<Int64 Function(), int Function()>('literalCall');
  late final unusedCall = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('unusedCall');
  late final pressure = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('pressure');

  bool hasSymbol(String name) => _library.providesSymbol(name);
  void close() => _library.close();
}
