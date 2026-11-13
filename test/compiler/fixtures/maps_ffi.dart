import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Maps() {
  final _library = NativeAssets(Target.host()).open('compiler/maps');
  late final basic = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('mapBasic');
  late final order = _library.lookupFunction<Int64 Function(), int Function()>(
    'mapOrder',
  );
  late final nulls = _library.lookupFunction<Int64 Function(), int Function()>(
    'mapNulls',
  );
  late final checked = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('mapChecked');
  late final iteration = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('mapIteration');
  late final algorithms = _library
      .lookupFunction<Int64 Function(), int Function()>('mapAlgorithms');
  late final failures = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('mapFailures');
  late final references = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'mapReferences',
      );
  late final saved = _library.lookupFunction<Int64 Function(), int Function()>(
    'mapSaved',
  );
  late final dispatch = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('mapDispatch');
  late final views = _library.lookupFunction<Int64 Function(), int Function()>(
    'mapViews',
  );
  late final callbackRoots = _library
      .lookupFunction<Int64 Function(), int Function()>('mapCallbackRoots');
  late final constants = _library
      .lookupFunction<Int64 Function(), int Function()>('mapConstants');
  void close() => _library.close();
}
