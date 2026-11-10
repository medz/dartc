import 'dart:ffi';

import 'package:dartc/target.dart';

import '../../support/native_assets.dart';

final class BoxedValues() {
  final _library = NativeAssets(Target.host()).open('codegen/boxed_values');

  late final integer = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'generic_integer',
      );
  late final floating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'generic_floating',
      );
  late final boolean = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'generic_boolean',
      );
  late final stack = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'boxed_stack',
      );
  late final runtimeBoolean = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'runtime_boolean',
      );

  late final discard = _library
      .lookupFunction<Int64 Function(), int Function()>('discard_void');
  late final markedTypes = _library
      .lookupFunction<Int64 Function(), int Function()>('marked_types');
  late final absentTypes = _library
      .lookupFunction<Int64 Function(), int Function()>('absent_types');

  late final refinedInteger = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'refine_integer',
      );
  late final refinedFloating = _library
      .lookupFunction<Double Function(Int64), double Function(int)>(
        'refine_floating',
      );
  late final pointerIsNull = _library
      .lookupFunction<Int64 Function(Int64), int Function(int)>('pointer_test');

  int isNull(String operation) => _library
      .lookupFunction<Int64 Function(), int Function()>('box_$operation')();

  double unboxFloating(String operation) =>
      _library.lookupFunction<Double Function(), double Function()>(
        'unbox_floating_$operation',
      )();

  int unboxInteger(String operation) =>
      _library.lookupFunction<Int64 Function(), int Function()>(
        'unbox_integer_$operation',
      )();

  void close() => _library.close();
}
