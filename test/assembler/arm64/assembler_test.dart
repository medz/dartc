import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart';
import 'package:test/test.dart';

void main() {
  test(
    'encodes register fields and signed constants without literal pools',
    () {
      final assembler = Assembler()
        ..move(.x9, .x1)
        ..add(.x0, .x9, .x2)
        ..subtract(.x30, .x29, .x28)
        ..loadImmediate(.x3, -1)
        ..ret();
      final data = ByteData.sublistView(assembler.finish());
      expect(
        [
          for (var offset = 0; offset < data.lengthInBytes; offset += 4)
            data.getUint32(offset, .little),
        ],
        [
          0xaa0103e9,
          0x8b020120,
          0xcb1c03be,
          0xd29fffe3,
          0xf2bfffe3,
          0xf2dfffe3,
          0xf2ffffe3,
          0xd65f03c0,
        ],
      );
      expect(assembler.finish, throwsStateError);
    },
  );
  test('encodes wrapping multiplication and bitwise register operations', () {
    final assembler = Assembler()
      ..multiply(.x0, .x1, .x2)
      ..bitAnd(.x30, .x29, .x28)
      ..bitOr(.x9, .x9, .x2)
      ..bitXor(.x3, .x4, .x3)
      ..multiply(.x7, .x7, .x7);
    final bytes = ByteData.sublistView(assembler.finish());
    expect(
      [
        for (var offset = 0; offset < bytes.lengthInBytes; offset += 4)
          bytes.getUint32(offset, .little),
      ],
      [0x9b027c20, 0x8a1c03be, 0xaa020129, 0xca030083, 0x9b077ce7],
    );
  });
  test('validates stack operands before writing bytes', () {
    final assembler = Assembler();
    for (final emit in [
      assembler.add,
      assembler.subtract,
      assembler.multiply,
      assembler.bitAnd,
      assembler.bitOr,
      assembler.bitXor,
    ]) {
      expect(() => emit(.sp, .x0, .x1), throwsArgumentError);
      expect(() => emit(.x0, .sp, .x1), throwsArgumentError);
      expect(() => emit(.x0, .x1, .sp), throwsArgumentError);
    }
    expect(() => assembler.loadImmediate(.sp, 1), throwsArgumentError);
    expect(() => assembler.load(.x0, .sp, 32768), throwsRangeError);
    expect(() => assembler.store(.x0, .sp, 1), throwsArgumentError);
    expect(() => assembler.addImmediate(.sp, .sp, 0x1000000), throwsRangeError);
    expect(() => assembler.compare(.sp, .x0), throwsArgumentError);
    expect(() => assembler.setCondition(.sp, .equal), throwsArgumentError);
    assembler
      ..move(.x29, .sp)
      ..load(.x0, .sp, 8)
      ..store(.x1, .sp, 16);
    final stack = ByteData.sublistView(assembler.finish());
    expect(stack.getUint32(0, .little), 0x910003fd);
    expect(stack.getUint32(4, .little), 0xf94007e0);
    expect(stack.getUint32(8, .little), 0xf9000be1);
  });
  test(
    'resolves forward and backward labels without changing other fields',
    () {
      final assembler = Assembler(),
          start = assembler.label(),
          end = assembler.label();
      assembler
        ..bind(start)
        ..compare(.x0, .x3)
        ..setCondition(.x9, .lessThan)
        ..branchZero(.x5, end)
        ..branch(start)
        ..bind(end)
        ..ret();
      final bytes = assembler.finish(), data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, .little), 0xeb03001f);
      expect(data.getUint32(4, .little), 0x9a9fa7e9);
      expect(data.getUint32(8, .little), 0xb4000045);
      expect(data.getUint32(12, .little), 0x17fffffd);
      expect(() => bytes[0] = 0, throwsUnsupportedError);
      expect(() => assembler.move(.x0, .x0), throwsStateError);
      expect(() => assembler.ret(), throwsStateError);
      expect(assembler.label, throwsStateError);
      expect(() => assembler.bind(start), throwsStateError);
      expect(assembler.finish, throwsStateError);
    },
  );
  test('rejects foreign, duplicate and unbound labels', () {
    final assembler = Assembler(), label = assembler.label();
    final foreign = Assembler().label();
    expect(() => assembler.bind(foreign), throwsArgumentError);
    expect(() => assembler.branch(foreign), throwsArgumentError);
    expect(assembler.length, 0);
    assembler.bind(label);
    expect(() => assembler.bind(label), throwsStateError);
    assembler.branch(assembler.label());
    expect(assembler.finish, throwsStateError);
    expect(assembler.finish, throwsStateError);
  });
}
