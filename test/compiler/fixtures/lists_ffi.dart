import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Lists() {
  final _library = NativeAssets(Target.host()).open('compiler/lists');
  late final values = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listValues',
      );
  late final fixed = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listFixed',
      );
  late final resize = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listResize');
  late final references = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listReferences',
      );
  late final saved = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listSaved');
  late final cycles = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listCycles');
  late final failures = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'listFailures',
      );
  late final dispatch = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listDispatch');
  late final factories = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'listFactories',
      );
  late final doubles = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'listDoubles',
      );
  late final order = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('listOrder');

  void close() => _library.close();
}
