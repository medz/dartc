enum Target { macosArm64, linuxArm64, linuxX64, macosX64 }

Target compilationTarget = Target.macosArm64;

int get targetOS =>
    compilationTarget == Target.macosArm64 ||
        compilationTarget == Target.macosX64
    ? 0
    : 1;
bool get targetX64 =>
    compilationTarget == Target.linuxX64 ||
    compilationTarget == Target.macosX64;

// General registers are callee-saved. Managed references remain in described
// stack slots at calls and safe points.
List<int> get targetRegisters => targetX64
    ? const <int>[3, 12, 13, 14, 15]
    : const <int>[19, 20, 21, 22, 23, 24, 25, 26, 27];

// Physical locations 32..63 identify the floating register bank. ARM64 d16-d23
// are caller-saved; d0/d1 remain scratch. x64 still uses instruction-local SSE.
const int floatRegisterBase = 32;
List<int> get targetFloatRegisters =>
    targetX64 ? const <int>[] : const <int>[48, 49, 50, 51, 52, 53, 54, 55];
