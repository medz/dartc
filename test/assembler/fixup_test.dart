import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:test/test.dart';

void main() {
  for (final (encoding, bytes, offset, minimum, maximum, low, high)
      in <(FixupEncoding, List<int>, int, int, int, int, int)>[
        (
          .arm64Call26,
          [0, 0, 0, 0x94],
          0,
          -0x8000000,
          0x7fffffc,
          0x96000000,
          0x95ffffff,
        ),
        (
          .arm64Branch26,
          [0, 0, 0, 0x14],
          0,
          -0x8000000,
          0x7fffffc,
          0x16000000,
          0x15ffffff,
        ),
        (
          .arm64Zero19,
          [5, 0, 0, 0xb4],
          0,
          -1048576,
          1048572,
          0xb4800005,
          0xb47fffe5,
        ),
        (
          .x64Call32,
          [0xe8, 0, 0, 0, 0],
          1,
          -0x80000000,
          0x7fffffff,
          0x80000000,
          0x7fffffff,
        ),
        (
          .x64Jump32,
          [0xe9, 0, 0, 0, 0],
          1,
          -0x80000000,
          0x7fffffff,
          0x80000000,
          0x7fffffff,
        ),
        (
          .x64Conditional32,
          [0x0f, 0x84, 0, 0, 0, 0],
          2,
          -0x80000000,
          0x7fffffff,
          0x80000000,
          0x7fffffff,
        ),
      ]) {
    test('${encoding.name} validates and patches signed bounds atomically', () {
      final code = Uint8List.fromList(bytes), data = ByteData.sublistView(code);
      final arm = encoding.architecture == .arm64;
      const place = 0x100000000;
      final pc = place + (arm ? 0 : 4);
      encoding.validate(data, offset, unresolved: true);
      for (final (displacement, expected) in [
        (minimum, low),
        (maximum, high),
      ]) {
        encoding.apply(
          data,
          offset,
          placeAddress: place,
          targetAddress: pc + displacement,
        );
        expect(data.getUint32(offset, .little), expected);
      }
      expect(
        () => encoding.validate(data, offset, unresolved: true),
        throwsArgumentError,
      );
      final before = code.toList();
      for (final displacement in [minimum - 4, maximum + 4, if (arm) 2]) {
        expect(
          () => encoding.apply(
            data,
            offset,
            placeAddress: place,
            targetAddress: pc + displacement,
          ),
          throwsArgumentError,
        );
        expect(code, before);
      }
      expect(() => encoding.validate(data, -1), throwsArgumentError);
      expect(
        () => encoding.validate(data, data.lengthInBytes - 3),
        throwsArgumentError,
      );
      final invalid = ByteData(bytes.length);
      expect(
        () => encoding.apply(
          invalid,
          offset,
          placeAddress: place,
          targetAddress: pc,
        ),
        throwsArgumentError,
      );
      expect(invalid.buffer.asUint8List(), everyElement(0));
    });
  }

  test('call fixups carry their field offsets and PC semantics', () {
    final armAssembler = arm.Assembler()..ret();
    final armCall = armAssembler.call();
    final x64Assembler = x64.Assembler()..ret();
    final x64Call = x64Assembler.call();
    expect(armCall.offset, 4);
    expect(x64Call.offset, 2);
    for (final (fixup, bytes, expected) in [
      (armCall, armAssembler.finish(), 0x94000004),
      (x64Call, x64Assembler.finish(), 12),
    ]) {
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      fixup.encoding.apply(
        data,
        fixup.offset,
        placeAddress: 0x1000,
        targetAddress: 0x1008,
        addend: 8,
      );
      expect(data.getUint32(fixup.offset, .little), expected);
    }
  });
}
