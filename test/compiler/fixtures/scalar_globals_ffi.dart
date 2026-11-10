import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ScalarGlobals() {
  final _library = NativeAssets(Target.host()).open('compiler/scalar_globals');

  late final writeCounter = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('writeCounter');
  late final readCounter = _library
      .lookupFunction<Int64 Function(), int Function()>('readCounter');
  late final addCounter = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('addCounter');
  late final writeFloating = _library
      .lookupFunction<Double Function(Double), double Function(double)>(
        'writeFloating',
      );
  late final readFloating = _library
      .lookupFunction<Double Function(), double Function()>('readFloating');
  late final writeFlag = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('writeFlag');
  late final toggleFlag = _library
      .lookupFunction<Int64 Function(), int Function()>('toggleFlag');
  late final classState = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'classState',
      );
  late final lazyState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('lazyState');
  late final skippedState = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'skippedState',
      );
  late final retryState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('retryState');
  late final writtenState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('writtenState');
  late final recursiveState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'recursiveState',
      );
  late final allocatedState = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'allocatedState',
      );

  void close() => _library.close();
}
