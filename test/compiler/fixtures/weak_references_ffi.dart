import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class WeakReferences() {
  final _library = NativeAssets(Target.host()).open('compiler/weak_references');

  late final create = _library
      .lookupFunction<Void Function(Double, Int8), void Function(double, int)>(
        'create',
      );
  late final read = _library
      .lookupFunction<Double Function(), double Function()>('read');
  late final release = _library
      .lookupFunction<Void Function(), void Function()>('release');
  late final readOther = _library
      .lookupFunction<Double Function(), double Function()>('readOther');
  late final retainRead = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'retainRead',
      );
  late final local = _library
      .lookupFunction<
        Double Function(Double, Int64),
        double Function(double, int)
      >('local');
  late final constantTarget = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'constantTarget',
      );
  late final objectKinds = _library
      .lookupFunction<Int8 Function(Int64), int Function(int)>('objectKinds');
  late final churn = _library
      .lookupFunction<Double Function(Int64), double Function(int)>('churn');
  late final rejects = _library
      .lookupFunction<Int8 Function(Int64), int Function(int)>('rejects');

  void close() => _library.close();
}
