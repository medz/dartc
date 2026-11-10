import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart';
import 'package:dartc/target.dart';

import 'function_emitter.dart';
import 'binary_encoding.dart';
import 'scalar_generator.dart';

/// Generates AArch64 scalar functions for the selected operating system.
final class Arm64CodeGenerator(Target target)
    extends ScalarCodeGenerator<CpuRegister> {
  this : super(target, () => _Arm64Emitter(Assembler(), Arm64Abi(target))) {
    if (target.architecture != .arm64) {
      throw ArgumentError('Expected an ARM64 target.');
    }
  }
}

final class _Arm64Emitter(
  final Assembler assembler,
  @override final Arm64Abi convention,
) implements FunctionEmitter<CpuRegister> {
  @override
  int get position => assembler.length;

  @override
  Uint8List start(void Function() body, FrameLayout<CpuRegister>? frame) {
    frame ??= convention.target.operatingSystem == .macos
        ? convention.frameLayout(
            localBytes: 0,
            localAlignment: 1,
            savedRegisters: [],
            outgoingStackBytes: 0,
          )
        : null;
    if (frame != null) convention.emitPrologue(assembler, frame);
    body();
    if (convention.target.operatingSystem == .macos) {
      assembler.loadImmediate(.x0, 0);
      convention.emitEpilogue(assembler, frame!);
    } else {
      abort(0);
    }
    return assembler.finish();
  }

  @override
  Register get heapRegister => .x28;

  @override
  Register get failureRegister => .x8;

  @override
  void stackAddress(CpuRegister destination, int offset) =>
      assembler.addImmediate(destination as Register, .sp, offset);

  void _systemCall(int linux, int macos) {
    final mac = convention.target.operatingSystem == .macos;
    assembler
      ..loadImmediate(mac ? .x16 : .x8, mac ? macos : linux)
      ..supervisorCall(mac ? 0x80 : 0);
  }

  @override
  Uint8List mapMemory() {
    final done = assembler.label();
    final mac = convention.target.operatingSystem == .macos;
    assembler
      ..move(.x1, .x0)
      ..loadImmediate(.x0, 0)
      ..loadImmediate(.x2, 3)
      ..loadImmediate(.x3, mac ? 0x1002 : 0x22)
      ..loadImmediate(.x4, -1)
      ..loadImmediate(.x5, 0);
    _systemCall(222, 197);
    if (mac) {
      assembler.setCondition(.x9, .carrySet);
    } else {
      assembler.loadImmediate(.x10, 0);
      comparison(.lessThan).emit(Register.x9, Register.x0, Register.x10);
    }
    assembler
      ..branchZero(.x9, done)
      ..loadImmediate(.x0, 0)
      ..bind(done)
      ..loadImmediate(.x8, 0)
      ..ret();
    return assembler.finish();
  }

  @override
  Uint8List unmapMemory() {
    final done = assembler.label();
    _systemCall(215, 73);
    assembler.branchZero(.x0, done);
    abort(71);
    assembler
      ..bind(done)
      ..loadImmediate(.x8, 0)
      ..ret();
    return assembler.finish();
  }

  @override
  void abort(int status) {
    assembler.loadImmediate(.x0, status);
    _systemCall(94, 1);
  }

  @override
  void outOfMemory(void Function(Fixup) message, int length) {
    address(Register.x1, message);
    assembler
      ..loadImmediate(.x0, 2)
      ..loadImmediate(.x2, length);
    _systemCall(64, 4);
    abort(255);
  }

  @override
  void address(CpuRegister destination, void Function(Fixup) reference) {
    final register = destination as Register;
    reference(assembler.pageAddress(register));
    reference(assembler.addPageOffset(register, register));
  }

  @override
  List<CpuRegister> get allocatableRegisters => [
    ...const <Register>[
      .x0,
      .x1,
      .x2,
      .x3,
      .x4,
      .x5,
      .x6,
      .x7,
      .x9,
      .x10,
      .x11,
      .x12,
      .x13,
      .x14,
      .x15,
    ],
    ...FloatRegister.values.take(8),
    ...FloatRegister.values.skip(16),
  ];

  @override
  RegisterBank bank(CpuRegister register) =>
      register is FloatRegister ? .floating : .general;

  @override
  void move(CpuRegister destination, CpuRegister source) {
    switch ((destination, source)) {
      case (final Register d, final Register s):
        assembler.move(d, s);
      case (final FloatRegister d, final FloatRegister s):
        assembler.moveDouble(d, s);
      case (final Register d, final FloatRegister s):
        assembler.moveBitsToGeneral(d, s);
      case (final FloatRegister d, final Register s):
        assembler.moveBitsToDouble(d, s);
    }
  }

  @override
  void prologue(FrameLayout<CpuRegister> frame) =>
      convention.emitPrologue(assembler, frame);

  @override
  void epilogue(FrameLayout<CpuRegister> frame) =>
      convention.emitEpilogue(assembler, frame);

  @override
  void ret() => assembler.ret();

  @override
  Label label() => assembler.label();

  @override
  void bind(Label label) => assembler.bind(label);

  @override
  void loadImmediate(CpuRegister destination, int value) =>
      assembler.loadImmediate(destination as Register, value);

  @override
  void addScaled(
    CpuRegister destination,
    CpuRegister base,
    CpuRegister index, {
    required int scale,
  }) {
    if (scale != 1 && scale != 2 && scale != 4 && scale != 8) {
      throw ArgumentError.value(scale, 'scale', 'Expected 1, 2, 4 or 8.');
    }
    assembler.add(
      destination as Register,
      base as Register,
      index as Register,
      shift: scale.bitLength - 1,
    );
  }

  @override
  void extendInteger(
    CpuRegister register, {
    required int bytes,
    required bool signed,
  }) => assembler.extendInteger(
    register as Register,
    register,
    bytes: bytes,
    signed: signed,
  );

  @override
  void convertIntToDouble(CpuRegister destination, CpuRegister source) =>
      assembler.convertIntToDouble(
        destination as FloatRegister,
        source as Register,
      );

  @override
  void squareRootDouble(CpuRegister destination, CpuRegister source) =>
      assembler.squareRootDouble(
        destination as FloatRegister,
        source as FloatRegister,
      );

  @override
  void truncateDoubleToInt(CpuRegister destination, CpuRegister source) =>
      assembler.truncateDoubleToInt(
        destination as Register,
        source as FloatRegister,
      );

  @override
  void convertFloatToDouble(CpuRegister destination, CpuRegister source) =>
      assembler.convertFloatToDouble(
        destination as FloatRegister,
        source as FloatRegister,
      );

  @override
  void convertDoubleToFloat(CpuRegister destination, CpuRegister source) =>
      assembler.convertDoubleToFloat(
        destination as FloatRegister,
        source as FloatRegister,
      );

  @override
  BinaryEncoding<CpuRegister> get add => _binary(assembler.add);

  @override
  BinaryEncoding<CpuRegister> get subtract => _binary(assembler.subtract);

  @override
  BinaryEncoding<CpuRegister> get multiply => _binary(assembler.multiply);

  @override
  BinaryEncoding<CpuRegister> get bitAnd => _binary(assembler.bitAnd);

  @override
  BinaryEncoding<CpuRegister> get bitOr => _binary(assembler.bitOr);

  @override
  BinaryEncoding<CpuRegister> get bitXor => _binary(assembler.bitXor);

  BinaryEncoding<CpuRegister> _binary<T extends CpuRegister>(
    void Function(T, T, T) emit,
  ) => .new((d, l, r) => emit(d as T, l as T, r as T));

  @override
  bool get negationNeedsTemporary => false;

  @override
  void negateDouble(
    CpuRegister destination,
    CpuRegister source,
    CpuRegister? temporary,
  ) => assembler.negateDouble(
    destination as FloatRegister,
    source as FloatRegister,
  );

  @override
  BinaryEncoding<CpuRegister> get addDouble => _binary(assembler.addDouble);

  @override
  BinaryEncoding<CpuRegister> get subtractDouble =>
      _binary(assembler.subtractDouble);

  @override
  BinaryEncoding<CpuRegister> get multiplyDouble =>
      _binary(assembler.multiplyDouble);

  @override
  BinaryEncoding<CpuRegister> get divideDouble =>
      _binary(assembler.divideDouble);

  @override
  BinaryEncoding<CpuRegister> comparison(
    Comparison comparison, {
    bool floating = false,
  }) {
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => floating ? .negative : .lessThan,
      .lessOrEqual => floating ? .lowerOrEqual : .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      if (floating) {
        assembler.compareDouble(left as FloatRegister, right as FloatRegister);
      } else {
        assembler.compare(left as Register, right as Register);
      }
      assembler.setCondition(destination as Register, condition);
    });
  }

  @override
  void jump(Label target) => assembler.branch(target);

  @override
  void jumpIfZero(CpuRegister value, Label target) =>
      assembler.branchZero(value as Register, target);

  @override
  void loadStack(
    CpuRegister destination,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) => switch (destination) {
    Register() => assembler.load(
      destination,
      .sp,
      offset,
      bytes: bytes,
      signed: signed,
    ),
    FloatRegister() =>
      bytes == 4
          ? assembler.loadFloat(destination, .sp, offset)
          : assembler.loadDouble(destination, .sp, offset),
  };

  @override
  void storeStack(CpuRegister source, int offset, {int bytes = 8}) =>
      switch (source) {
        Register() => assembler.store(source, .sp, offset, bytes: bytes),
        FloatRegister() =>
          bytes == 4
              ? assembler.storeFloat(source, .sp, offset)
              : assembler.storeDouble(source, .sp, offset),
      };

  @override
  Fixup call() => assembler.call();

  @override
  void callRegister(CpuRegister target) =>
      assembler.callRegister(target as Register);

  @override
  void loadMemory(
    CpuRegister destination,
    CpuRegister base, {
    int offset = 0,
    required int bytes,
    required bool signed,
  }) => switch (destination) {
    Register() => assembler.load(
      destination,
      base as Register,
      offset,
      bytes: bytes,
      signed: signed,
    ),
    FloatRegister() =>
      bytes == 4
          ? assembler.loadFloat(destination, base as Register, offset)
          : assembler.loadDouble(destination, base as Register, offset),
  };

  @override
  void storeMemory(
    CpuRegister source,
    CpuRegister base, {
    int offset = 0,
    required int bytes,
  }) => switch (source) {
    Register() => assembler.store(
      source,
      base as Register,
      offset,
      bytes: bytes,
    ),
    FloatRegister() =>
      bytes == 4
          ? assembler.storeFloat(source, base as Register, offset)
          : assembler.storeDouble(source, base as Register, offset),
  };

  @override
  Uint8List finish() => assembler.finish();
}
