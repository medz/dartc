import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ControlFlow() {
  final _library = NativeAssets(Target.host()).open('compiler/control_flow');
  late final choose = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'choose',
      );
  late final conditional = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'conditional',
      );
  late final relations = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'relations',
      );
  late final shortCircuit = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'shortCircuit',
      );
  late final whileLoop = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('whileLoop');
  late final doLoop = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('doLoop');
  late final forLoop = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('forLoop');
  late final recursive = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('recursive');
  late final rotate = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('rotate');
  late final loopCalls = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('loopCalls');
  late final foreverWithExit = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'foreverWithExit',
      );

  late final nestedTransfers = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'nestedTransfers',
      );

  late final deferredLocals = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'deferredLocals',
      );
  late final deferredDouble = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('deferredDouble');
  late final deferredPointer = _library
      .lookupFunction<
        Pointer<Int64> Function(Pointer<Int64>, Int64),
        Pointer<Int64> Function(Pointer<Int64>, int)
      >('deferredPointer');

  void close() => _library.close();
}
