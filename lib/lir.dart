/// The machine-level program representation, with its checker and interpreter.
library;

export 'src/lir/block.dart';
export 'src/lir/instruction.dart';
export 'src/lir/interpret.dart'
    show LirExternalBody, LirInterpreter, LirException;
export 'src/lir/memory.dart' show LirFault, LirMemory, LirNumber, LirObject;
export 'src/lir/module.dart';
export 'src/lir/print.dart' show printModule, printFunction;
export 'src/lir/value.dart';
export 'src/lir/verify.dart' show LirError, verifyModule;
