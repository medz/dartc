import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/target.dart';
import 'package:dartc/assembler/x64.dart';

import 'function_emitter.dart';
import 'binary_encoding.dart';
import 'integer_generator.dart';

/// Generates x86-64 integer functions for the selected operating system.
final class X64CodeGenerator(Target target)
    extends IntegerCodeGenerator<Register> {
  this : super(target, () => _X64Emitter(Assembler(), X64Abi(target))) {
    if (target.architecture != .x64) {
      throw ArgumentError('Expected an x64 target.');
    }
  }
}

final class _X64Emitter(
  final Assembler assembler,
  @override final X64Abi convention,
) implements FunctionEmitter<Register> {
  @override
  List<Register> get allocatableRegisters => const [
    .rax,
    .rcx,
    .rdx,
    .rsi,
    .rdi,
    .r8,
    .r9,
    .r10,
    .r11,
  ];

  @override
  void move(Register destination, Register source) =>
      assembler.move(destination, source);

  @override
  void prologue(FrameLayout<Register> frame) =>
      convention.emitPrologue(assembler, frame);

  @override
  void epilogue(FrameLayout<Register> frame) =>
      convention.emitEpilogue(assembler, frame);

  @override
  void ret() => assembler.ret();

  @override
  Label label() => assembler.label();

  @override
  void bind(Label label) => assembler.bind(label);

  @override
  void loadImmediate(Register destination, int value) =>
      assembler.loadImmediate(destination, value);

  @override
  BinaryEncoding<Register> get add => _binary(assembler.add);

  @override
  BinaryEncoding<Register> get subtract => _binary(assembler.subtract);

  @override
  BinaryEncoding<Register> get multiply => _binary(assembler.multiply);

  @override
  BinaryEncoding<Register> get bitAnd => _binary(assembler.bitAnd);

  @override
  BinaryEncoding<Register> get bitOr => _binary(assembler.bitOr);

  @override
  BinaryEncoding<Register> get bitXor => _binary(assembler.bitXor);

  BinaryEncoding<Register> _binary(void Function(Register, Register) emit) =>
      .new(
        (destination, _, right) => emit(destination, right),
        reuseLeft: true,
      );

  @override
  BinaryEncoding<Register> comparison(Comparison comparison) {
    final Condition condition = switch (comparison) {
      .equal => .equal,
      .notEqual => .notEqual,
      .lessThan => .lessThan,
      .lessOrEqual => .lessOrEqual,
      .greaterThan => .greaterThan,
      .greaterOrEqual => .greaterOrEqual,
    };
    return .new((destination, left, right) {
      assembler.compare(left, right);
      assembler.setCondition(destination, condition);
    });
  }

  @override
  void jump(Label target) => assembler.jump(target);

  @override
  void jumpIfZero(Register value, Label target) {
    assembler.test(value);
    assembler.jumpCondition(.equal, target);
  }

  @override
  void loadStack(Register destination, int offset) =>
      assembler.loadStack(destination, offset);

  @override
  void storeStack(Register source, int offset) =>
      assembler.storeStack(source, offset);

  @override
  Fixup call() => assembler.call();

  @override
  Uint8List finish() => assembler.finish();
}
