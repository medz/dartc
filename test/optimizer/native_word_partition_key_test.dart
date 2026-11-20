import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_memory.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final word = NativeScalarType(Int64),
      layout = NativeLayout(const Target(.linux, .x64));
  FlowMemory set(FlowMemory m, int n, int value) =>
      m.write(8 * n, word, FlowValue.constant(Constant.integer(value)), layout);
  FlowMemory join(FlowMemory a, FlowMemory b) =>
      a.join(b, nativeWords: ((_) => false, (_) => false));
  for (final size in [2, 3, 5]) {
    test(
      'removing the former representative canonicalizes the surviving partition of $size words',
      () {
        final cold = FlowMemory(0, 64);
        var hot = cold;
        for (var i = 0; i < size; i++) hot = set(hot, i, i + 10);
        final after = set(join(cold, hot), 0, 77);
        final before = join(set(cold, 0, 77), set(hot, 0, 77));
        for (var i = 0; i < size; i++)
          expect(
            after.read(8 * i, word, layout),
            before.read(8 * i, word, layout),
          );
        print(
          'size=$size sameState=${after == before} extraJoin=${join(after, before) != after}',
        );
        expect(after, before);
        expect(after.hashCode, before.hashCode);
        expect(join(after, before), after);
      },
    );
  }
}
