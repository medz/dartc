import 'dart:typed_data';

import 'package:dartc/assembler/arm64.dart';
import 'package:test/test.dart';

void main() {
  test('signed division encodes registers and rejects SP without writing', () {
    final assembler = Assembler()
      ..divideSigned(.x0, .x1, .x2)
      ..divideSigned(.x30, .x29, .x28);
    final bytes = ByteData.sublistView(assembler.finish());
    expect(bytes.getUint32(0, .little), 0x9ac20c20);
    expect(bytes.getUint32(4, .little), 0x9adc0fbe);
    final invalid = Assembler();
    expect(() => invalid.divideSigned(.sp, .x0, .x1), throwsArgumentError);
    expect(() => invalid.divideSigned(.x0, .sp, .x1), throwsArgumentError);
    expect(() => invalid.divideSigned(.x0, .x1, .sp), throwsArgumentError);
    expect(invalid.finish(), isEmpty);
    expect(() => assembler.divideSigned(.x0, .x1, .x2), throwsStateError);
  });

  test('supervisor calls encode the immediate and reject overflow', () {
    final assembler = Assembler()
      ..supervisorCall(0)
      ..supervisorCall(0xffff);
    final bytes = ByteData.sublistView(assembler.finish());
    expect(bytes.getUint32(0, .little), 0xd4000001);
    expect(bytes.getUint32(4, .little), 0xd41fffe1);
    final invalid = Assembler();
    for (final value in [-1, 0x10000]) {
      expect(() => invalid.supervisorCall(value), throwsRangeError);
    }
    expect(invalid.finish(), isEmpty);
    expect(() => assembler.supervisorCall(0), throwsStateError);
  });

  test('register branches preserve the return address and reject SP', () {
    final assembler = Assembler()
      ..branchRegister(.x0)
      ..branchRegister(.x16)
      ..branchRegister(.x30);
    final bytes = ByteData.sublistView(assembler.finish());
    expect(bytes.getUint32(0, .little), 0xd61f0000);
    expect(bytes.getUint32(4, .little), 0xd61f0200);
    expect(bytes.getUint32(8, .little), 0xd61f03c0);
    final invalid = Assembler();
    expect(() => invalid.branchRegister(.sp), throwsArgumentError);
    expect(invalid.finish(), isEmpty);
    expect(() => assembler.branchRegister(.x1), throwsStateError);
  });

  test(
    'indirect calls encode register targets and reject SP before writing',
    () {
      final assembler = Assembler()
        ..callRegister(.x0)
        ..callRegister(.x15)
        ..callRegister(.x30);
      final bytes = ByteData.sublistView(assembler.finish());
      expect(bytes.getUint32(0, .little), 0xd63f0000);
      expect(bytes.getUint32(4, .little), 0xd63f01e0);
      expect(bytes.getUint32(8, .little), 0xd63f03c0);
      final invalid = Assembler();
      expect(() => invalid.callRegister(.sp), throwsArgumentError);
      expect(invalid.finish(), isEmpty);
      expect(() => assembler.callRegister(.x1), throwsStateError);
    },
  );

  test(
    'shifted addition encodes scale and rejects invalid operands atomically',
    () {
      final assembler = Assembler()
        ..add(.x0, .x1, .x2, shift: 3)
        ..add(.x30, .x29, .x28, shift: 63);
      final bytes = ByteData.sublistView(assembler.finish());
      expect(bytes.getUint32(0, .little), 0x8b020c20);
      expect(bytes.getUint32(4, .little), 0x8b1cffbe);
      final invalid = Assembler();
      for (final shift in [-1, 64]) {
        expect(
          () => invalid.add(.x0, .x1, .x2, shift: shift),
          throwsRangeError,
        );
      }
      expect(() => invalid.add(.x0, .sp, .x1, shift: 3), throwsArgumentError);
      expect(invalid.finish(), isEmpty);
    },
  );

  test('narrow memory and register operations encode their actual widths', () {
    final a = Assembler()
      ..load(.x0, .x1, 1, bytes: 1, signed: true)
      ..load(.x2, .sp, 2, bytes: 2)
      ..load(.x3, .x4, 4, bytes: 4, signed: true)
      ..store(.x5, .x6, 3, bytes: 1)
      ..store(.x7, .x8, 6, bytes: 2)
      ..store(.x9, .x10, 12, bytes: 4)
      ..extendInteger(.x11, .x12, bytes: 1, signed: true)
      ..extendInteger(.x13, .x14, bytes: 4, signed: false);
    final data = ByteData.sublistView(a.finish());
    expect(
      [
        for (var i = 0; i < data.lengthInBytes; i += 4)
          data.getUint32(i, .little),
      ],
      [
        0x39800420,
        0x794007e2,
        0xb9800483,
        0x39000cc5,
        0x79000d07,
        0xb9000d49,
        0x93401d8b,
        0xd3407dcd,
      ],
    );
    final invalid = Assembler();
    expect(() => invalid.load(.x0, .sp, 4096, bytes: 1), throwsRangeError);
    expect(() => invalid.store(.x0, .sp, 1, bytes: 2), throwsArgumentError);
    expect(() => invalid.load(.x0, .sp, 0, bytes: 3), throwsArgumentError);
    expect(
      () => invalid.extendInteger(.sp, .x0, bytes: 1, signed: true),
      throwsArgumentError,
    );
    expect(invalid.finish(), isEmpty);
  });

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
