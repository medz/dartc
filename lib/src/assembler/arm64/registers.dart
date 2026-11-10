/// A physical register used for scalar values.
sealed class const CpuRegister() {
  /// The register number in machine instruction fields.
  int get index;
}

/// A 64-bit general-purpose register or the stack pointer.
enum Register() implements CpuRegister {
  x0,
  x1,
  x2,
  x3,
  x4,
  x5,
  x6,
  x7,
  x8,
  x9,
  x10,
  x11,
  x12,
  x13,
  x14,
  x15,
  x16,
  x17,
  x18,
  x19,
  x20,
  x21,
  x22,
  x23,
  x24,
  x25,
  x26,
  x27,
  x28,
  x29,
  x30,
  sp,
}

/// A condition on the architecture's comparison flags.
enum Condition(final int encoding) {
  equal(0),
  notEqual(1),
  carrySet(2),
  negative(4),
  lowerOrEqual(9),
  lessThan(11),
  lessOrEqual(13),
  greaterThan(12),
  greaterOrEqual(10),
}

/// A SIMD/FP register named by its 64-bit alias.
///
/// Single-precision operations use the low 32 bits of the same register.
enum FloatRegister() implements CpuRegister {
  d0,
  d1,
  d2,
  d3,
  d4,
  d5,
  d6,
  d7,
  d8,
  d9,
  d10,
  d11,
  d12,
  d13,
  d14,
  d15,
  d16,
  d17,
  d18,
  d19,
  d20,
  d21,
  d22,
  d23,
  d24,
  d25,
  d26,
  d27,
  d28,
  d29,
  d30,
  d31,
}
