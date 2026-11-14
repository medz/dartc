@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/native_names.dart';
import 'fixtures/native_names_other.dart' as other;

void main() {
  test(
    'C names preserve distinct Dart types, private fields and callback layouts',
    () {
      final library = NativeAssets(Target.host()).open('compiler/native_names');
      addTearDown(library.close);
      final combine = library
          .lookupFunction<
            Point Function(Point, other.Point),
            Point Function(Point, other.Point)
          >('combine');
      final state = library
          .lookupFunction<State Function(Int64), State Function(int)>(
            'makeState',
          );
      final convert = library
          .lookupFunction<
            other.Point Function(Pointer<NativeFunction<ConvertPoint>>, Point),
            other.Point Function(Pointer<NativeFunction<ConvertPoint>>, Point)
          >('convertPoint');
      final input = Struct.create<Point>()
        ..x = 1.25
        ..y = -2.5;
      final amount = Struct.create<other.Point>()..value = 4;
      final result = combine(input, amount);
      expect((result.x, result.y), (5.25, -10.0));
      expect((input.x, input.y), (1.25, -2.5));
      final stored = state(0x123456789);
      expect((stored.value, stored.register), (0x123456789, 17));
      final callback = NativeCallable<ConvertPoint>.isolateLocal(
        (Point value) =>
            Struct.create<other.Point>()..value = (value.x * value.y).toInt(),
      );
      addTearDown(callback.close);
      expect(convert(callback.nativeFunction, result).value, -52);
    },
  );
}
