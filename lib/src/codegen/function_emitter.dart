import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';

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
  /// The calling convention bound to this function's instruction buffer.
  CallingConvention<R> get convention;

  /// Creates a local code destination.
  Label label();

  /// Binds a local destination at the next instruction.
  void bind(Label label);

  /// Loads all 64 bits of [value] into [destination].
  void loadImmediate(R destination, int value);

  /// Adds with 64-bit wrapping, allowing any operand registers to coincide.
  ///
  /// Only [destination] and condition flags may be overwritten.
  void add(R destination, R left, R right);

  /// Subtracts with the same register and flag constraints as [add].
  void subtract(R destination, R left, R right);

  /// Produces a 0/1 result, permitting any input/output register aliases.
  ///
  /// Only [destination] and condition flags may change.
  void compare(R destination, R left, R right, Comparison comparison);

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
