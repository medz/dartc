import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class BoundMethods() {
  final _library = NativeAssets(Target.host()).open('compiler/bound_methods');

  late final calls = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'methodCalls',
      );
  late final identity = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'methodIdentity',
      );
  late final generic = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'genericMethods',
      );
  late final checks = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('methodChecks');

  void close() => _library.close();
}
