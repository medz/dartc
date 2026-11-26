import 'value.dart';

/// An operation executed in order inside a block.
sealed class LirInstruction() extends LirValue {
  /// The operands, in evaluation order.
  List<LirValue> get inputs;
}

/// A 64-bit integer constant.
final class ConstInt(final int value) extends LirInstruction {
  @override
  LirType get type => .i64;
  @override
  List<LirValue> get inputs => const [];
}

/// A double constant, preserving its exact bits.
final class ConstFloat(final double value) extends LirInstruction {
  @override
  LirType get type => .f64;
  @override
  List<LirValue> get inputs => const [];
}

/// The null reference.
final class ConstNull() extends LirInstruction {
  @override
  LirType get type => .ref;
  @override
  List<LirValue> get inputs => const [];
}

/// The address of a function, external function or data symbol.
final class SymbolAddress(final String symbol) extends LirInstruction {
  @override
  LirType get type => .ptr;
  @override
  List<LirValue> get inputs => const [];
}

/// The object that exists from the start under [symbol].
final class StaticObject(final String symbol) extends LirInstruction {
  @override
  LirType get type => .ref;
  @override
  List<LirValue> get inputs => const [];
}

/// The address of this function's frame, for the runtime to find others.
final class FrameAddress() extends LirInstruction {
  @override
  LirType get type => .i64;
  @override
  List<LirValue> get inputs => const [];
}

/// Continues at [code] in the function whose frame is at [frame], on the edge
/// for a throw. Nothing after it runs.
final class Resume(
  final LirValue frame,
  final LirValue code,
  final LirValue exception,
  final LirValue trace,
) extends LirInstruction {
  @override
  LirType? get type => null;
  @override
  List<LirValue> get inputs => [frame, code, exception, trace];
}

/// Integer arithmetic on 64-bit words; add, sub and mul wrap.
enum IntOp() {
  add,
  sub,
  mul,

  /// Truncating division; the divisor is not 0, and min / -1 is min.
  div,

  /// Remainder with the dividend's sign; the divisor is not 0.
  rem,
  and,
  or,
  xor,

  /// Shifts require an amount from 0 to 63.
  shl,
  sar,
  shr,
}

final class IntBinary(final IntOp op, final LirValue left, final LirValue right)
    extends LirInstruction {
  @override
  LirType get type => .i64;
  @override
  List<LirValue> get inputs => [left, right];
}

enum FloatOp() {
  add,
  sub,
  mul,
  div,
}

final class FloatBinary(
  final FloatOp op,
  final LirValue left,
  final LirValue right,
) extends LirInstruction {
  @override
  LirType get type => .f64;
  @override
  List<LirValue> get inputs => [left, right];
}

enum FloatUnaryOp() {
  neg,
  sqrt,
}

final class FloatUnary(final FloatUnaryOp op, final LirValue operand)
    extends LirInstruction {
  @override
  LirType get type => .f64;
  @override
  List<LirValue> get inputs => [operand];
}

/// An ordering or equality test.
enum Relation() {
  eq,
  ne,
  lt,
  le,
  gt,
  ge,

  /// Unsigned integer orderings.
  ult,
  ule,
  ugt,
  uge;

  bool get isEquality => this == eq || this == ne;
  bool get isUnsigned => index >= ult.index;
}

/// Compares two values of one type, producing 0 or 1.
///
/// Integers admit every relation, doubles every signed relation with IEEE
/// semantics for NaN, references and addresses only equality.
final class Compare(
  final Relation relation,
  final LirValue left,
  final LirValue right,
) extends LirInstruction {
  @override
  LirType get type => .i64;
  @override
  List<LirValue> get inputs => [left, right];
}

enum Conversion(final LirType from, final LirType to) {
  intToFloat(.i64, .f64),

  /// Truncates toward zero; the operand is finite and in the i64 range.
  floatToInt(.f64, .i64),
  intBitsToFloat(.i64, .f64),
  floatBitsToInt(.f64, .i64),
  intToPtr(.i64, .ptr),
  ptrToInt(.ptr, .i64),

  /// An object where the runtime has put one, or what stands for an odd number.
  intToRef(.i64, .ref),

  /// Where an object is, which is even, or the odd number.
  refToInt(.ref, .i64),
}

final class Convert(final Conversion op, final LirValue operand)
    extends LirInstruction {
  @override
  LirType get type => op.to;
  @override
  List<LirValue> get inputs => [operand];
}

/// The address [offset] bytes after [base].
final class PtrAdd(final LirValue base, final LirValue offset)
    extends LirInstruction {
  @override
  LirType get type => .ptr;
  @override
  List<LirValue> get inputs => [base, offset];
}

/// How a value is stored in memory, little-endian.
enum Width(final int bytes, final LirType type) {
  i8(1, .i64),
  u8(1, .i64),
  i16(2, .i64),
  u16(2, .i64),
  i32(4, .i64),
  u32(4, .i64),
  i64(8, .i64),

  /// A single-precision double, rounded when stored.
  f32(4, .f64),
  f64(8, .f64),
  ref(8, .ref),
  ptr(8, .ptr);

  /// How far numbers of it are shifted to be bytes.
  int get shift => bytes.bitLength - 1;
}

/// Reads [width] at [offset] bytes after [base], a reference or an address.
///
/// [index] adds a further run-time byte offset. Only managed objects hold
/// references, so a `ref` access needs a reference base.
final class Load(
  final Width width,
  final LirValue base, {
  final int offset = 0,
  final LirValue? index,
}) extends LirInstruction {
  @override
  LirType get type => width.type;
  @override
  List<LirValue> get inputs => [base, ?index];
}

/// Writes the low bytes of [value] under the same addressing as [Load].
final class Store(
  final Width width,
  final LirValue base,
  final LirValue value, {
  final int offset = 0,
  final LirValue? index,
}) extends LirInstruction {
  @override
  LirType? get type => null;
  @override
  List<LirValue> get inputs => [base, ?index, value];
}

/// An operation that may run the collector and may throw.
///
/// These, and no others, are safepoints.
sealed class LirCall() extends LirInstruction {
  /// The types of the call's inputs, excluding a callee address.
  LirSignature get signature;

  /// Where in the source it is made, for traces of the stack.
  LirPlace? place;
}

/// A place in the source: the function that is there, its file and its line,
/// and the call that [outer] is at if its body replaced that call.
final class LirPlace(
  final String function,
  final String uri,
  final int line, [
  final LirPlace? outer,
]);

/// Calls a function or external function of this module.
final class Call(
  final String symbol,
  @override final LirSignature signature,
  Iterable<LirValue> arguments,
) extends LirCall {
  final List<LirValue> arguments = .unmodifiable(arguments);
  @override
  LirType? get type => signature.result;
  @override
  List<LirValue> get inputs => arguments;
}

/// Calls the function at [address], which must have [signature].
final class CallIndirect(
  final LirValue address,
  @override final LirSignature signature,
  Iterable<LirValue> arguments,
) extends LirCall {
  final List<LirValue> arguments = .unmodifiable(arguments);
  @override
  LirType? get type => signature.result;
  @override
  List<LirValue> get inputs => [address, ...arguments];
}

/// Allocates a zero-filled object of [size] bytes.
final class Alloc(final LirValue size) extends LirCall {
  @override
  LirSignature get signature => LirSignature([.i64], .ref);
  @override
  LirType get type => .ref;
  @override
  List<LirValue> get inputs => [size];
}
