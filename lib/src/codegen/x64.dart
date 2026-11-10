import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/target.dart';
import 'package:dartc/assembler/x64.dart';

import 'function_emitter.dart';
import 'binary_encoding.dart';
import 'scalar_generator.dart';

/// Generates x86-64 scalar functions for the selected operating system.
final class X64CodeGenerator(Target target)
    extends ScalarCodeGenerator<CpuRegister> {
  this : super(target, () => _X64Emitter(Assembler(), X64Abi(target))) {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }
}

final class _X64Emitter(
  final Assembler assembler,
  @override final X64Abi convention,
) implements FunctionEmitter<CpuRegister> {
  @override
  int get position => assembler.length;

  @override
  Uint8List start(void Function() body, FrameLayout<CpuRegister>? frame) {
    final mac = convention.target.operatingSystem == .macos;
    frame ??= mac
        ? convention.frameLayout(
            localBytes: 0,
            localAlignment: 1,
            savedRegisters: [],
            outgoingStackBytes: 0,
          )
        : null;
    if (frame != null) {
      if (!mac) {
        assembler
          ..loadImmediate(.r11, 0)
          ..push(.r11);
      }
      convention.emitPrologue(assembler, frame);
    }
    body();
    if (mac) {
      assembler.loadImmediate(.rax, 0);
      convention.emitEpilogue(assembler, frame!);
    } else {
      abort(0);
    }
    return assembler.finish();
  }

  @override
  Register get heapRegister => .r15;

  @override
  Register get failureRegister => .r11;

  @override
  Register get exceptionRegister => .rax;

  @override
  Register get traceRegister => .rdx;

  @override
  void stackAddress(CpuRegister destination, int offset) {
    assembler
      ..move(destination as Register, .rsp)
      ..addImmediate(destination, offset);
  }

  void _systemCall(int linux, int macos) => assembler
    ..loadImmediate(
      .rax,
      convention.target.operatingSystem == .macos ? 0x2000000 + macos : linux,
    )
    ..syscall();

  @override
  Uint8List mapMemory() {
    final done = assembler.label();
    final mac = convention.target.operatingSystem == .macos;
    assembler
      ..move(.rsi, .rdi)
      ..loadImmediate(.rdi, 0)
      ..loadImmediate(.rdx, 3)
      ..loadImmediate(.r10, mac ? 0x1002 : 0x22)
      ..loadImmediate(.r8, -1)
      ..loadImmediate(.r9, 0);
    _systemCall(9, 197);
    if (mac) {
      assembler.jumpCondition(.aboveOrEqual, done);
    } else {
      assembler
        ..test(.rax)
        ..jumpCondition(.greaterOrEqual, done);
    }
    assembler
      ..loadImmediate(.rax, 0)
      ..bind(done)
      ..loadImmediate(.r11, 0)
      ..ret();
    return assembler.finish();
  }

  @override
  Uint8List unmapMemory() {
    final done = assembler.label();
    _systemCall(11, 73);
    assembler
      ..test(.rax)
      ..jumpCondition(.equal, done);
    abort(71);
    assembler
      ..bind(done)
      ..loadImmediate(.r11, 0)
      ..ret();
    return assembler.finish();
  }

  @override
  void abort(int status) {
    assembler.loadImmediate(.rdi, status);
    _systemCall(231, 1);
  }

  @override
  void reportFailure(void Function(Fixup) message, int length) {
    address(Register.rsi, message);
    assembler
      ..loadImmediate(.rdi, 2)
      ..loadImmediate(.rdx, length);
    _systemCall(1, 4);
    abort(255);
  }

  @override
  void address(CpuRegister destination, void Function(Fixup) reference) =>
      reference(assembler.address(destination as Register));

  @override
  List<CpuRegister> get allocatableRegisters => [
    ...const <Register>[.rax, .rcx, .rdx, .rsi, .rdi, .r8, .r9, .r10, .r11],
    ...FloatRegister.values,
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
  }) => assembler.lea(
    destination as Register,
    base as Register,
    index as Register,
    scale: scale,
  );

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
    void Function(T, T) emit,
  ) => .new(
    (destination, _, right) => emit(destination as T, right as T),
    reuseLeft: true,
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
    if (floating) return _floatingComparison(comparison);
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => .lessThan,
      .lessOrEqual => .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      assembler.compare(left as Register, right as Register);
      assembler.setCondition(destination as Register, condition);
    });
  }

  @override
  bool get negationNeedsTemporary => true;

  @override
  void negateDouble(
    CpuRegister destination,
    CpuRegister source,
    CpuRegister? temporary,
  ) {
    final scratch = temporary as Register;
    assembler
      ..moveBitsToGeneral(scratch, source as FloatRegister)
      ..complementBit(scratch, 63)
      ..moveBitsToDouble(destination as FloatRegister, scratch);
  }

  BinaryEncoding<CpuRegister> _floatingComparison(Comparison comparison) =>
      .new((d, l, r) {
        final destination = d as Register,
            left = l as FloatRegister,
            right = r as FloatRegister;
        final reversed = comparison == .lessThan || comparison == .lessOrEqual;
        assembler.compareDouble(
          reversed ? right : left,
          reversed ? left : right,
        );
        if (comparison == .equal || comparison == .notEqual) {
          final unordered = assembler.label(), done = assembler.label();
          assembler.jumpCondition(.parity, unordered);
          assembler.setCondition(
            destination,
            comparison == .equal ? .equal : .notEqual,
          );
          assembler.jump(done);
          assembler.bind(unordered);
          assembler.loadImmediate(destination, comparison == .notEqual ? 1 : 0);
          assembler.bind(done);
        } else {
          assembler.setCondition(
            destination,
            comparison == .lessOrEqual || comparison == .greaterOrEqual
                ? .aboveOrEqual
                : .above,
          );
        }
      });

  @override
  void jump(Label target) => assembler.jump(target);

  @override
  void jumpIfZero(CpuRegister value, Label target) {
    assembler.test(value as Register);
    assembler.jumpCondition(.equal, target);
  }

  @override
  void loadStack(
    CpuRegister destination,
    int offset, {
    int bytes = 8,
    bool signed = false,
  }) => switch (destination) {
    Register() => assembler.load(
      destination,
      .rsp,
      offset,
      bytes: bytes,
      signed: signed,
    ),
    FloatRegister() =>
      bytes == 4
          ? assembler.loadFloat(destination, .rsp, offset)
          : assembler.loadDouble(destination, .rsp, offset),
  };

  @override
  void storeStack(CpuRegister source, int offset, {int bytes = 8}) =>
      switch (source) {
        Register() => assembler.store(source, .rsp, offset, bytes: bytes),
        FloatRegister() =>
          bytes == 4
              ? assembler.storeFloat(source, .rsp, offset)
              : assembler.storeDouble(source, .rsp, offset),
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
