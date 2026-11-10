import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ObjectMembers() {
  final _library = NativeAssets(Target.host()).open('compiler/object_members');
  late final call = _library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'objectMembers',
      );

  void close() => _library.close();
}
