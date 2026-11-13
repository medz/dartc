import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class FunctionValues() {
  final _library = NativeAssets(Target.host()).open('compiler/function_values');

  late final staticCalls = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'staticCalls',
      );
  late final staticIdentity = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'staticIdentity',
      );
  late final genericCalls = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('genericCalls');
  late final functionTypes = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'functionTypes',
      );
  late final constructors = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('constructors');
  late final constructorIdentity = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'constructorIdentity',
      );

  late final constructorDefaults = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'constructorDefaults',
      );

  late final effects = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('effects');

  void close() => _library.close();
}
