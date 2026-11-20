import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/src/optimizer/flow_memory.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  const offset = ObjectHeader.fieldsOffset;
  final arm = NativeLayout(const Target(.macos, .arm64));
  final x64 = NativeLayout(const Target(.linux, .x64));
  final word = NativeScalarType(Int64);
  final rawByte = NativeScalarType(Uint8);
  final storage = [
    word,
    NativeScalarType(Double),
    NativeScalarType(Bool),
    NativeScalarType(Int32),
    rawByte,
  ];

  final c = ClassType(null, 'Backing');
  FlowObject owner() =>
      FlowObject(NewPayload(c, const Constant.integer(0)), Object());

  test(
    'scalar reads follow byte versions, not allocation or structural hash',
    () {
      final a = owner(), b = owner();
      final empty = FlowMemory(offset, 8);
      final pointer = empty.write(
        offset,
        word,
        FlowValue.address(FlowAddress(a, 12)),
        arm,
      );
      final overwritten = pointer.write(
        offset,
        word,
        FlowValue.address(FlowAddress(b, -4)),
        arm,
      );
      final joined = pointer.join(overwritten);
      final partial = joined.write(
        offset + 2,
        rawByte,
        FlowValue.constant(const Constant.integer(13)),
        x64,
      );
      final copied = empty.copyFrom(offset, joined, offset, 8);
      final remapped = joined.map((v) => v.mapObjects((o) => o == a ? b : o));
      final unknown = partial.invalidate(),
          released = joined.invalidate(release: true);
      final memories = [
        empty,
        pointer,
        overwritten,
        joined,
        partial,
        copied,
        remapped,
        unknown,
        released,
        FlowMemory(offset, 2),
        FlowMemory(offset, null),
        FlowMemory(offset, 0),
        FlowMemory(offset, 8).write(
          offset,
          word,
          FlowValue.constant(const Constant.integer(-1)),
          arm,
        ),
      ];
      final beforeHashes = memories.map((m) => m.hashCode).toList();
      for (final layout in [arm, x64, arm]) {
        for (final m in [...memories, ...memories.reversed]) {
          for (final codec in [...storage, ...storage.reversed]) {
            final reference = m.read(offset, codec, layout);
            final first = m.readScalarPayload(codec, layout),
                repeated = m.readScalarPayload(codec, layout);
            expect(first, reference);
            expect(repeated, same(first));
            expect(repeated, reference);
            expect(repeated.hashCode, reference.hashCode);
            expect(first.references, reference.references);
          }
        }
      }
      expect(memories.map((m) => m.hashCode), orderedEquals(beforeHashes));
      expect(pointer.readScalarPayload(word, arm).addresses.single.base, a);
      expect(overwritten.readScalarPayload(word, arm).addresses.single.base, b);
      expect(
        remapped.readScalarPayload(word, arm).addresses.map((p) => p.base),
        everyElement(b),
      );
    },
  );

  test('the same bytes are interpreted by the selected scalar codec', () {
    final m = FlowMemory.bytes([
      ...List<int>.filled(offset, 0),
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      128,
    ]);
    expect(
      (m.readScalarPayload(word, arm).constant as ScalarConstant).value,
      -0x8000000000000000,
    );
    final d =
        (m.readScalarPayload(NativeScalarType(Double), x64).constant
                    as ScalarConstant)
                .value
            as double;
    expect(d.isNegative, isTrue);
    expect(
      (m.readScalarPayload(NativeScalarType(Bool), arm).constant
              as ScalarConstant)
          .value,
      false,
    );
    expect(
      (m.readScalarPayload(word, x64).constant as ScalarConstant).value,
      -0x8000000000000000,
    );
  });
}
