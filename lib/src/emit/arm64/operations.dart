import 'dart:typed_data';

import 'package:dartc/lir.dart';

import 'assembler.dart';
import 'convention.dart';

/// Emits operations whose operands and result are in registers.
final class Arm64Operations(final Arm64Assembler _assembler) {
  /// Computes [instruction] into [d]; [d] may equal any operand.
  void emit(LirInstruction instruction, int d, List<int> operands) {
    switch (instruction) {
      case ConstInt(:final value):
        _assembler.constant(d, value);
      case ConstFloat(:final value):
        final bits = ByteData(8)..setFloat64(0, value);
        _assembler
          ..constant(leftScratch, bits.getInt64(0))
          ..bitsToFloat(d, leftScratch);
      case SymbolAddress(:final symbol):
        _assembler.address(d, symbol);
      case IntBinary(:final op):
        _integer(op, d, operands[0], operands[1]);
      case FloatBinary(:final op):
        _float(op, d, operands[0], operands[1]);
      case FloatUnary(op: .neg):
        _assembler.fneg(d, operands[0]);
      case FloatUnary(op: .sqrt):
        _assembler.fsqrt(d, operands[0]);
      case Compare(left: LirValue(type: .f64), :final relation):
        _assembler
          ..fcmp(operands[0], operands[1])
          ..cset(d, _floatCondition(relation));
      case Compare(:final relation):
        _assembler
          ..cmp(operands[0], operands[1])
          ..cset(d, _condition(relation));
      case Convert(:final op):
        _convert(op, d, operands[0]);
      case PtrAdd():
        _assembler.add(d, operands[0], operands[1]);
      case ConstNull() || Load() || Store() || LirCall():
        throw StateError('Unchecked instruction: $instruction');
    }
  }

  void _integer(IntOp op, int d, int l, int r) {
    switch (op) {
      case .add:
        _assembler.add(d, l, r);
      case .sub:
        _assembler.sub(d, l, r);
      case .mul:
        _assembler.mul(d, l, r);
      case .div:
        _assembler.sdiv(d, l, r);
      case .rem:
        _assembler
          ..sdiv(farScratch, l, r)
          ..msub(d, farScratch, r, l);
      case .and:
        _assembler.and(d, l, r);
      case .or:
        _assembler.orr(d, l, r);
      case .xor:
        _assembler.eor(d, l, r);
      case .shl:
        _assembler.lsl(d, l, r);
      case .sar:
        _assembler.asr(d, l, r);
      case .shr:
        _assembler.lsr(d, l, r);
    }
  }

  void _float(FloatOp op, int d, int l, int r) {
    switch (op) {
      case .add:
        _assembler.fadd(d, l, r);
      case .sub:
        _assembler.fsub(d, l, r);
      case .mul:
        _assembler.fmul(d, l, r);
      case .div:
        _assembler.fdiv(d, l, r);
    }
  }

  void _convert(Conversion op, int d, int n) {
    switch (op) {
      case .intToFloat:
        _assembler.intToFloat(d, n);
      case .floatToInt:
        _assembler.floatToInt(d, n);
      case .intBitsToFloat:
        _assembler.bitsToFloat(d, n);
      case .floatBitsToInt:
        _assembler.floatToBits(d, n);
      case .intToPtr || .ptrToInt:
        // Integers and addresses share one form.
        _assembler.mov(d, n);
    }
  }

  static Condition _condition(Relation relation) => switch (relation) {
    .eq => .eq,
    .ne => .ne,
    .lt => .lt,
    .le => .le,
    .gt => .gt,
    .ge => .ge,
    .ult => .lo,
    .ule => .ls,
    .ugt => .hi,
    .uge => .hs,
  };

  /// Conditions that are false, or true for `ne`, when an operand is NaN.
  static Condition _floatCondition(Relation relation) => switch (relation) {
    .eq => .eq,
    .ne => .ne,
    .lt => .mi,
    .le => .ls,
    .gt => .gt,
    .ge => .ge,
    _ => throw StateError('Unchecked float comparison: $relation'),
  };
}
