import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class ObjectValues() {
  final _library = NativeAssets(Target.host()).open('codegen/object_values');

  late final integer = _library
      .lookupFunction<Int16 Function(Int64), int Function(int)>(
        'integer_field',
      );
  late final floating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'double_field',
      );
  late final boolean = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('bool_field');
  late final nested = _library.lookupFunction<Int64 Function(), int Function()>(
    'nested_field',
  );
  late final stack = _library.lookupFunction<Int64 Function(), int Function()>(
    'stack_references',
  );
  late final rotate = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('rotate');
  late final checkNull = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('check_null');

  void close() => _library.close();
}
