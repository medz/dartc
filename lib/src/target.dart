enum Target { macosArm64, linuxArm64, linuxX64 }

Target compilationTarget = Target.macosArm64;

int get targetOS => compilationTarget == Target.macosArm64 ? 0 : 1;
bool get targetX64 => compilationTarget == Target.linuxX64;

// The allocator uses only callee-saved registers for unboxed values. Managed
// references remain in described stack slots at calls and safe points.
List<int> get targetRegisters => targetX64
    ? const <int>[3, 12, 13, 14, 15]
    : const <int>[19, 20, 21, 22, 23, 24, 25, 26, 27];
