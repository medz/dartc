import 'package:dartc/lir.dart';

import 'allocate.dart';
import 'selection.dart';

/// A branch destination inside the code being assembled.
abstract interface class CodeLabel();

/// Registers that a kind of processor has for what functions do with them.
final class const MachineRegisters({
  /// Those that values may occupy.
  required final Map<RegisterBank, RegisterSet> values,

  /// Those that pass arguments, in order.
  required final Map<RegisterBank, List<int>> arguments,

  /// Those that hold results.
  required final Map<RegisterBank, int> results,

  /// Those that hold operands and results which have no register, within one
  /// operation.
  required final Map<RegisterBank, List<int>> operands,

  /// Those that hold values on the way from one place to another: of a cycle,
  /// and between stack words.
  required final Map<RegisterBank, int> cycles,
  required final int carrier,

  /// Those that hold what is called or continued at, and the frame for that.
  required final int callee,
  required final int resumedFrame,

  /// Those where an exception and its trace are when they are caught, which are
  /// the first ones that pass arguments.
  required final List<int> caught,
}) {
  /// Where a call's arguments are passed, in order.
  ///
  /// The stack has those without a register, in order. This agrees with what
  /// systems do for 64-bit values.
  List<Location> argumentLocations(LirSignature signature, StackArea area) {
    final used = {for (final bank in RegisterBank.values) bank: 0};
    var words = 0;
    Location next(RegisterBank bank) {
      final registers = arguments[bank]!, index = used[bank]!;
      if (index == registers.length) return OnStack(area, words++);
      used[bank] = index + 1;
      return InRegister(bank, registers[index]);
    }

    return [for (final type in signature.parameters) next(.of(type))];
  }

  /// How many of a call's arguments are passed on the stack.
  int stackWords(LirSignature signature) {
    var words = 0, floats = 0;
    for (final type in signature.parameters) {
      type == .f64 ? floats++ : words++;
    }
    return _excess(words, .word) + _excess(floats, .float);
  }

  int _excess(int count, RegisterBank bank) {
    final registers = arguments[bank]!.length;
    return count > registers ? count - registers : 0;
  }

  /// The register holding a call's result.
  Location resultLocation(LirType type) {
    final bank = RegisterBank.of(type);
    return InRegister(bank, results[bank]!);
  }
}

/// The largest frames that may reach below the limit of the stack, where there
/// is much more.
const littleFrame = 4096;

/// What a kind of processor does for functions.
///
/// From the stack pointer up, a frame holds outgoing arguments, spilled values,
/// preserved registers and the saved frame and return addresses.
abstract interface class Machine() implements Abilities {
  MachineRegisters get registers;

  /// Where the next instruction will be.
  int get offset;

  /// Makes a frame of [bytes], after calling a function that throws unless the
  /// stack has so many left if it [checksStack], or a little less. Calls
  /// [onCheck] after that call.
  void enter(
    int bytes, {
    required bool checksStack,
    required void Function() onCheck,
  });

  /// Leaves the frame and returns.
  void leave();

  /// Finds the stack again in a frame of [bytes].
  void restoreStack(int bytes);

  void copy(InRegister from, InRegister to);

  /// Makes [register] have [value].
  void constant(int register, int value);

  /// Loads or stores a word at any [offset] from the stack pointer, or from the
  /// frame address if [fromFrame].
  void access(
    InRegister register,
    int offset, {
    required bool fromFrame,
    required bool store,
  });

  /// As above, words that are one after the other from [offset] on.
  void accessAll(List<InRegister> registers, int offset, {required bool store});

  void call(String symbol, LirSignature signature);
  void callRegister(int register);

  /// Continues at the address in one register with a frame in another.
  void resume();

  CodeLabel label();
  void bind(CodeLabel label);
  void jump(CodeLabel label);

  /// Jumps if [register] is 0, or only if it is not.
  void jumpIfZero(int register, CodeLabel label, {required bool isZero});

  /// Jumps if [comparison] of [operands] [holds], or only if it does not. The
  /// right one is [immediate] if that is given.
  void jumpIf(
    Compare comparison,
    List<int> operands,
    CodeLabel label, {
    required bool holds,
    int? immediate,
  });

  /// Stops the program, where code never comes.
  void breakpoint();

  /// Computes [instruction] into [result], which may equal any operand. What is
  /// on its right is [immediate] if that is given, and its index is a number of
  /// what it loads if it [isScaled].
  void operation(
    LirInstruction instruction,
    int result,
    List<int> operands, {
    int? immediate,
    bool isScaled = false,
  });

  /// Stores register [value] at [base] plus the register [index], if any, which
  /// is a number of what it stores if it [isScaled].
  void store(
    Store store,
    int base,
    int? index,
    int value, {
    bool isScaled = false,
  });
}
