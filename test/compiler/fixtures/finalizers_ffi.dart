import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class Finalizers() {
  final _library = NativeAssets(Target.host()).open('compiler/finalizers');
  late final create = _library
      .lookupFunction<Void Function(Double, Int8), void Function(double, int)>(
        'create',
      );
  late final collect = _library
      .lookupFunction<Int64 Function(Int8), int Function(int)>('collect');
  late final release = _library
      .lookupFunction<Void Function(), void Function()>('release');
  late final read = _library
      .lookupFunction<Double Function(), double Function()>('read');
  late final order = _library.lookupFunction<Int64 Function(), int Function()>(
    'order',
  );
  late final count = _library.lookupFunction<Int64 Function(), int Function()>(
    'count',
  );

  void close() => _library.close();
  late final timers = _library.lookupFunction<Void Function(), void Function()>(
    'timers',
  );
  late final periodic = _library
      .lookupFunction<Void Function(), void Function()>('periodic');
  late final multiple = _library
      .lookupFunction<Void Function(), void Function()>('multiple');
  late final zoneMaps = _library
      .lookupFunction<Int64 Function(), int Function()>('zoneMaps');

  late final createInZone = _library
      .lookupFunction<Void Function(), void Function()>('createInZone');
  late final discardOwner = _library
      .lookupFunction<Void Function(), void Function()>('discardOwner');
  late final rejects = _library
      .lookupFunction<Int8 Function(Int8, Int8), int Function(int, int)>(
        'rejects',
      );
  late final reenter = _library
      .lookupFunction<
        Int64 Function(Pointer<NativeFunction<Void Function()>>),
        int Function(Pointer<NativeFunction<Void Function()>>)
      >('reenter');
}
