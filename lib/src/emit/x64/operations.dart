import 'dart:typed_data';

import 'package:dartc/lir.dart';

import 'assembler.dart';
import 'registers.dart';

const _rax = X64Assembler.rax, _rcx = X64Assembler.rcx;
const _rdx = X64Assembler.rdx;

/// Emits operations whose operands and result are in registers.
///
/// They may change rax and, once they have read operands from there, the other
/// scratch registers.
final class X64Operations(final X64Assembler _assembler) {
  /// Computes [instruction] into [d]; [d] may equal any operand.
  void emit(
    LirInstruction instruction,
    int d,
    List<int> operands, {
    bool isScaled = false,
  }) {
    switch (instruction) {
      case ConstInt(:final value):
        _assembler.constant(d, value);
      case ConstFloat(:final value):
        final bits = ByteData(8)..setFloat64(0, value);
        _assembler
          ..constant(_rax, bits.getInt64(0))
          ..bitsToFloat(d, _rax);
      case SymbolAddress(:final symbol) || StaticObject(:final symbol):
        _assembler.address(d, symbol);
      case IntBinary(:final op):
        _integer(op, d, operands[0], operands[1]);
      case FloatBinary(:final op):
        _float(op, d, operands[0], operands[1]);
      case FloatUnary(op: .neg):
        _negate(d, operands[0]);
      case FloatUnary(op: .sqrt):
        _assembler.floatBinary(.sqrt, d, operands[0]);
      case Compare(left: LirValue(type: .f64), :final relation):
        _compareFloats(relation, d, operands[0], operands[1]);
      case Compare(:final relation):
        _assembler
          ..binary(.cmp, operands[0], operands[1])
          ..setByte(_rax, _condition(relation))
          ..extendByte(d, _rax);
      case Convert(:final op):
        _convert(op, d, operands[0]);
      case PtrAdd():
        _assembler.lea(d, Memory(operands[0], index: operands[1]));
      case Load(:final width, :final offset, :final index):
        final at = Memory(
          operands[0],
          offset: offset,
          index: index == null ? null : operands[1],
          isScaled: isScaled,
        );
        _assembler.loadWidth(width, d, at);
      case FrameAddress():
        _assembler.mov(d, X64Assembler.rbp);
      case ConstNull():
        _assembler.constant(d, 0);
      case Store() || LirCall() || Resume():
        throw StateError('Unchecked instruction: $instruction');
    }
  }

  /// Stores register [value] at [base] plus the register [index], if any.
  void store(
    Store store,
    int base,
    int? index,
    int value, {
    bool isScaled = false,
  }) => _assembler.storeWidth(
    store.width,
    value,
    Memory(base, offset: store.offset, index: index, isScaled: isScaled),
    scratch: rightFloatScratch,
  );

  /// d = l op [value], which the instruction can have.
  void immediate(IntOp op, int d, int l, int value) {
    switch (op) {
      case .add:
        _assembler.lea(d, Memory(l, offset: value));
      case .sub:
        _assembler.lea(d, Memory(l, offset: -value));
      case .mul:
        _assembler.imulImmediate(d, l, value);
      case .and:
        _copy(d, l);
        _assembler.binaryImmediate(.and, d, value);
      case .or:
        _copy(d, l);
        _assembler.binaryImmediate(.or, d, value);
      case .xor:
        _copy(d, l);
        _assembler.binaryImmediate(.xor, d, value);
      case .shl:
        _copy(d, l);
        _assembler.shiftImmediate(.shl, d, value);
      case .sar:
        _copy(d, l);
        _assembler.shiftImmediate(.sar, d, value);
      case .shr:
        _copy(d, l);
        _assembler.shiftImmediate(.shr, d, value);
      case .div || .rem:
        throw StateError('${op.name} has no immediate.');
    }
  }

  /// Computes whether register [l] is in [relation] to [value] into [d].
  void setComparison(Relation relation, int d, int l, int value) => _assembler
    ..binaryImmediate(.cmp, l, value)
    ..setByte(_rax, _condition(relation))
    ..extendByte(d, _rax);

  void jumpIf(
    Compare comparison,
    List<int> operands,
    Label label, {
    required bool holds,
    int? immediate,
  }) {
    final relation = comparison.relation;
    if (comparison.left.type != .f64) {
      immediate == null
          ? _assembler.binary(.cmp, operands[0], operands[1])
          : _assembler.binaryImmediate(.cmp, operands[0], immediate);
      _assembler.jumpIf(_condition(relation), label, holds: holds);
      return;
    }
    final [l, r] = operands;
    switch (relation) {
      case .lt || .le:
        _assembler
          ..fcmp(r, l)
          ..jumpIf(
            relation == .lt ? .above : .aboveOrEqual,
            label,
            holds: holds,
          );
      case .gt || .ge:
        _assembler
          ..fcmp(l, r)
          ..jumpIf(
            relation == .gt ? .above : .aboveOrEqual,
            label,
            holds: holds,
          );
      default:
        _assembler.fcmp(l, r);
        if ((relation == .eq) == holds) {
          // Equal, and none of them is NaN.
          final skip = Label();
          _assembler
            ..jumpIf(.parity, skip)
            ..jumpIf(.equal, label)
            ..bind(skip);
        } else {
          _assembler
            ..jumpIf(.parity, label)
            ..jumpIf(.notEqual, label);
        }
    }
  }

  void _integer(IntOp op, int d, int l, int r) {
    switch (op) {
      case .add:
        _assembler.lea(d, Memory(l, index: r));
      case .sub:
        _through(.sub, d, l, r);
      case .mul:
        if (d == r) {
          _assembler.imul(d, l);
        } else {
          _copy(d, l);
          _assembler.imul(d, r);
        }
      case .div:
        _divide(d, l, r, wantsRest: false);
      case .rem:
        _divide(d, l, r, wantsRest: true);
      case .and:
        _commute(.and, d, l, r);
      case .or:
        _commute(.or, d, l, r);
      case .xor:
        _commute(.xor, d, l, r);
      case .shl:
        _shift(.shl, d, l, r);
      case .sar:
        _shift(.sar, d, l, r);
      case .shr:
        _shift(.shr, d, l, r);
    }
  }

  void _copy(int d, int m) {
    if (d != m) _assembler.mov(d, m);
  }

  void _commute(WordOp op, int d, int l, int r) {
    if (d == r) {
      _assembler.binary(op, d, l);
    } else {
      _copy(d, l);
      _assembler.binary(op, d, r);
    }
  }

  void _through(WordOp op, int d, int l, int r) {
    if (d != r || d == l) {
      _copy(d, l);
      _assembler.binary(op, d, r);
      return;
    }
    _assembler
      ..mov(_rax, l)
      ..binary(op, _rax, r)
      ..mov(d, _rax);
  }

  /// The count has to be in rcx, which is kept elsewhere meanwhile.
  void _shift(UnaryOp op, int d, int l, int r) {
    const kept = leftScratch;
    _assembler
      ..mov(_rax, l)
      ..mov(kept, _rcx);
    _copy(_rcx, r);
    _assembler
      ..unary(op, _rax)
      ..mov(_rcx, kept)
      ..mov(d, _rax);
  }

  /// Divides rdx and rax. The first one is kept elsewhere meanwhile.
  ///
  /// The processor cannot divide by -1 where the result is too large.
  void _divide(int d, int l, int r, {required bool wantsRest}) {
    const kept = leftScratch, result = rightScratch;
    final divisor = r == _rdx ? rightScratch : r;
    final special = Label(), done = Label();
    _assembler.mov(_rax, l);
    _copy(divisor, r);
    _assembler
      ..mov(kept, _rdx)
      ..binaryImmediate(.cmp, divisor, -1)
      ..jumpIf(.equal, special)
      ..cqo()
      ..unary(.idiv, divisor)
      ..jump(done)
      ..bind(special)
      ..unary(.neg, _rax)
      ..constant(_rdx, 0)
      ..bind(done)
      ..mov(result, wantsRest ? _rdx : _rax)
      ..mov(_rdx, kept)
      ..mov(d, result);
  }

  void _float(FloatOp op, int d, int l, int r) {
    final (code, commutes) = switch (op) {
      .add => (DoubleOp.add, true),
      .sub => (DoubleOp.sub, false),
      .mul => (DoubleOp.mul, true),
      .div => (DoubleOp.div, false),
    };
    if (d == r && d != l) {
      if (commutes) {
        _assembler.floatBinary(code, d, l);
        return;
      }
      // It is no scratch register, as results are only in the first of those.
      _assembler.fmov(rightFloatScratch, r);
      r = rightFloatScratch;
    }
    if (d != l) _assembler.fmov(d, l);
    _assembler.floatBinary(code, d, r);
  }

  void _negate(int d, int n) {
    _assembler
      ..constant(_rax, -0x8000000000000000)
      ..bitsToFloat(rightFloatScratch, _rax);
    if (d != n) _assembler.fmov(d, n);
    _assembler.fxor(d, rightFloatScratch);
  }

  /// All but `ne` are false when an operand is NaN, which looks like being
  /// below and equal.
  void _compareFloats(Relation relation, int d, int l, int r) {
    switch (relation) {
      case .lt || .le:
        _assembler
          ..fcmp(r, l)
          ..setByte(_rax, relation == .lt ? .above : .aboveOrEqual);
      case .gt || .ge:
        _assembler
          ..fcmp(l, r)
          ..setByte(_rax, relation == .gt ? .above : .aboveOrEqual);
      case .eq || .ne:
        final isEqual = relation == .eq;
        _assembler
          ..fcmp(l, r)
          ..setByte(_rax, isEqual ? .equal : .notEqual)
          ..setByte(rightScratch, isEqual ? .noParity : .parity)
          ..binary(isEqual ? .and : .or, _rax, rightScratch);
      default:
        throw StateError('Unchecked float comparison: $relation');
    }
    _assembler.extendByte(d, _rax);
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
      case .intToPtr || .ptrToInt || .intToRef || .refToInt:
        // Integers, addresses and references share one form.
        _copy(d, n);
    }
  }

  static Condition _condition(Relation relation) => switch (relation) {
    .eq => .equal,
    .ne => .notEqual,
    .lt => .less,
    .le => .lessOrEqual,
    .gt => .greater,
    .ge => .greaterOrEqual,
    .ult => .below,
    .ule => .belowOrEqual,
    .ugt => .above,
    .uge => .aboveOrEqual,
  };
}
