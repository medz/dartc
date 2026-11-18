import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ScalarRepresentation() {
  final _library = NativeAssets(Target.host())
      .open('compiler/scalar_representation');

  late final storeScalars = _library
      .lookupFunction<
        Void Function(Int64, Double, Int64),
        void Function(int, double, int)
      >('storeScalars');
  late final scalarEqual = _library
      .lookupFunction<
        Int64 Function(Int64, Double, Int64, Int64),
        int Function(int, double, int, int)
      >('scalarEqual');
  late final replaceScalars = _library
      .lookupFunction<
        Void Function(Int64, Double, Int64),
        void Function(int, double, int)
      >('replaceScalars');
  late final storeLateScalars = _library
      .lookupFunction<
        Void Function(Int64, Double, Int64),
        void Function(int, double, int)
      >('storeLateScalars');
  late final readLateInteger = _library
      .lookupFunction<Int64 Function(), int Function()>('readLateInteger');
  late final readLateFloating = _library
      .lookupFunction<Double Function(), double Function()>('readLateFloating');
  late final readLateFlag = _library
      .lookupFunction<Int64 Function(), int Function()>('readLateFlag');
  late final lateErrors = _library
      .lookupFunction<Int64 Function(), int Function()>('lateErrors');
  late final checkLateBound = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'checkLateBound',
      );
  late final readInteger = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('readInteger');
  late final readFloating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'readFloating',
      );
  late final readFlag = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('readFlag');
  late final storeCaptures = _library
      .lookupFunction<
        Void Function(Int64, Int64, Double, Double, Int64, Int64),
        void Function(int, int, double, double, int, int)
      >('storeCaptures');
  late final capturedInteger = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'capturedInteger',
      );
  late final capturedFloating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'capturedFloating',
      );
  late final capturedFlag = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('capturedFlag');
  late final observeScalar = _library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'observeScalar',
      );
  late final storeMixed = _library
      .lookupFunction<
        Void Function(Int64, Int64, Double, Int64),
        void Function(int, int, double, int)
      >('storeMixed');
  late final observedKind = _library
      .lookupFunction<Int64 Function(), int Function()>('observedKind');
  late final inferredType = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'inferredType',
      );
  late final observedInteger = _library
      .lookupFunction<Int64 Function(), int Function()>('observedInteger');
  late final observedFloating = _library
      .lookupFunction<Double Function(), double Function()>('observedFloating');
  late final storeNumber = _library
      .lookupFunction<
        Void Function(Int64, Int64, Double),
        void Function(int, int, double)
      >('storeNumber');
  late final numberKind = _library
      .lookupFunction<Int64 Function(), int Function()>('numberKind');
  late final numberValue = _library
      .lookupFunction<Double Function(), double Function()>('numberValue');
  late final storeNullable = _library
      .lookupFunction<Void Function(Int64, Double), void Function(int, double)>(
        'storeNullable',
      );
  late final nullablePresent = _library
      .lookupFunction<Int64 Function(), int Function()>('nullablePresent');
  late final nullableValue = _library
      .lookupFunction<Double Function(), double Function()>('nullableValue');
  late final allocatePressure = _library
      .lookupFunction<Void Function(Int64), void Function(int)>(
        'allocatePressure',
      );
  late final pressureSum = _library
      .lookupFunction<Int64 Function(), int Function()>('pressureSum');

  void close() => _library.close();
}
