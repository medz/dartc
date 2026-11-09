/// x86-64 instruction encoding with explicit scalar registers.
library;

export '../src/assembler/x64/assembler.dart' show Assembler;
export '../src/assembler/x64/registers.dart'
    show CpuRegister, Register, FloatRegister, Condition;
