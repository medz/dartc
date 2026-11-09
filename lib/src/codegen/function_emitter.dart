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

/// The disjoint physical resources used by current scalar representations.
enum RegisterBank() {
  general,
  floating,
}

/// Emits one function with explicit operand registers.
abstract interface class FunctionEmitter<R>() {
  /// The calling rules for the explicit output platform.
  CallingConvention<R> get convention;

  /// The registers this generator makes available to its allocator.
  List<R> get allocatableRegisters;

  /// The physical bank containing [register].
  RegisterBank bank(R register);

  /// Copies 64 bits within or between register banks without changing flags.
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

  /// Loads all 64 bits of [value] into a general [destination] register.
  void loadImmediate(R destination, int value);

  /// Converts a signed integer into a floating register without changing inputs.
  void convertIntToDouble(R destination, R source);

  /// Truncates a finite double in the range [-2^63, 2^63) into a general register.
  void truncateDoubleToInt(R destination, R source);

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

  /// The selected IEEE double addition.
  BinaryEncoding<R> get addDouble;

  /// The selected IEEE double subtraction.
  BinaryEncoding<R> get subtractDouble;

  /// The selected IEEE double multiplication, without contraction.
  BinaryEncoding<R> get multiplyDouble;

  /// The selected IEEE double division.
  BinaryEncoding<R> get divideDouble;

  /// Whether double negation needs a distinct general temporary register.
  bool get negationNeedsTemporary;

  /// Flips a double's sign, changing only [destination], [temporary] and flags.
  void negateDouble(R destination, R source, R? temporary);

  /// Selects a materialized 0/1 comparison, with no live flags after emission.
  BinaryEncoding<R> comparison(Comparison comparison, {bool floating = false});

  /// Emits a jump to a local destination.
  void jump(Label target);

  /// Emits a jump taken for zero, preserving registers but possibly changing flags.
  void jumpIfZero(R value, Label target);

  /// Loads a word from a slot in the current frame.
  void loadStack(R destination, int offset);

  /// Saves a word to a slot in the current frame.
  void storeStack(R source, int offset);

  /// Reads a native 64-bit word; [destination] may alias [base].
  void loadMemory(R destination, R base);

  /// Writes a native 64-bit word without changing either input register.
  void storeMemory(R source, R base);

  /// Emits an unresolved direct call and returns its instruction field.
  Fixup call();

  /// Resolves local branches, returns immutable bytes and closes the assembler.
  Uint8List finish();
}
