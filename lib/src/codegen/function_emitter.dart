import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';

import 'binary_encoding.dart';

/// The signed or equality relation produced by a native scalar comparison.
enum Comparison() {
  equal,
  notEqual,
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
}

/// Emits one function with explicit operand registers.
abstract interface class FunctionEmitter<R>() {
  /// The calling rules for the explicit output platform.
  CallingConvention<R> get convention;

  /// The registers this generator makes available to its allocator.
  List<R> get allocatableRegisters;

  /// Copies a value between registers without changing flags.
  void move(R destination, R source);

  /// Establishes the queried frame before the body.
  void prologue(FrameLayout<R> frame);

  /// Restores the queried frame and returns the already placed result.
  void epilogue(FrameLayout<R> frame);

  /// Returns from a frameless function with the result already placed.
  void ret();

  /// Creates a local code destination.
  Label label();

  /// Binds a local destination at the next instruction.
  void bind(Label label);

  /// Loads all 64 bits of [value] into [destination].
  void loadImmediate(R destination, int value);

  /// The selected 64-bit wrapping addition and its operand constraint.
  BinaryEncoding<R> get add;

  /// The selected 64-bit wrapping subtraction and its operand constraint.
  BinaryEncoding<R> get subtract;

  /// The selected 64-bit wrapping multiplication and its operand constraint.
  BinaryEncoding<R> get multiply;

  /// The selected 64-bit bitwise conjunction and its operand constraint.
  BinaryEncoding<R> get bitAnd;

  /// The selected 64-bit bitwise disjunction and its operand constraint.
  BinaryEncoding<R> get bitOr;

  /// The selected 64-bit bitwise exclusive or and its operand constraint.
  BinaryEncoding<R> get bitXor;

  /// Selects a materialized 0/1 comparison, with no live flags after emission.
  BinaryEncoding<R> comparison(Comparison comparison);

  /// Emits a jump to a local destination.
  void jump(Label target);

  /// Emits a jump taken for zero, preserving registers but possibly changing flags.
  void jumpIfZero(R value, Label target);

  /// Loads a word from a slot in the current frame.
  void loadStack(R destination, int offset);

  /// Saves a word to a slot in the current frame.
  void storeStack(R source, int offset);

  /// Emits an unresolved direct call and returns its instruction field.
  Fixup call();

  /// Resolves local branches, returns immutable bytes and closes the assembler.
  Uint8List finish();
}
