import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ConstructorEffects() {
  final _library = NativeAssets(Target.host())
      .open('compiler/constructor_effects');
  late final construct = _library
      .lookupFunction<Int64 Function(Int64, Bool), int Function(int, bool)>(
        'construct',
      );
  late final remember = _library
      .lookupFunction<Void Function(Int64), void Function(int)>('remember');
  late final count = _library.lookupFunction<Int64 Function(), int Function()>(
    'count',
  );

  late final recoverDepth = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('recoverDepth');

  void close() => _library.close();
}
