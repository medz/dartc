import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class MemberCalls() {
  final _library = NativeAssets(Target.host()).open('compiler/member_calls');
  late final call = _library
      .lookupFunction<
        Int64 Function(Int64, Int64, Double, Int64),
        int Function(int, int, double, int)
      >('memberCalls');

  void close() => _library.close();
}
