/// A physical register used for a 64-bit scalar value.
sealed class const CpuRegister() {
  /// The register number in machine instruction fields.
  int get index;
}

/// A general-purpose register in instruction encoding order.
enum Register() implements CpuRegister {
  rax,
  rcx,
  rdx,
  rbx,
  rsp,
  rbp,
  rsi,
  rdi,
  r8,
  r9,
  r10,
  r11,
  r12,
  r13,
  r14,
  r15,
}

/// A condition on the architecture's comparison flags.
enum Condition(final int encoding) {
  equal(4),
  notEqual(5),
  aboveOrEqual(3),
  above(7),
  parity(10),
  lessThan(12),
  lessOrEqual(14),
  greaterThan(15),
  greaterOrEqual(13),
}

/// A 64-bit floating-point view of an SSE register.
enum FloatRegister() implements CpuRegister {
  xmm0,
  xmm1,
  xmm2,
  xmm3,
  xmm4,
  xmm5,
  xmm6,
  xmm7,
  xmm8,
  xmm9,
  xmm10,
  xmm11,
  xmm12,
  xmm13,
  xmm14,
  xmm15,
}
