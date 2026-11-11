import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Expandos() {
  final _library = NativeAssets(Target.host()).open('compiler/expandos');
  late final properties = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'properties',
      );
  late final createGraph = _library
      .lookupFunction<Void Function(Int8), void Function(int)>('createGraph');
  late final observeGraph = _library
      .lookupFunction<Double Function(Int8), double Function(int)>(
        'observeGraph',
      );
  late final releaseGraph = _library
      .lookupFunction<Void Function(), void Function()>('releaseGraph');
  late final rejects = _library
      .lookupFunction<Int8 Function(Int64), int Function(int)>('rejects');
  late final checkedValues = _library
      .lookupFunction<Int8 Function(), int Function()>('checkedValues');
  late final identityHashes = _library
      .lookupFunction<Int8 Function(Int64, Double), int Function(int, double)>(
        'identityHashes',
      );

  void close() => _library.close();
}
