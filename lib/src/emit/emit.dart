import 'package:dartc/lir.dart';

import 'arm64/assembler.dart';
import 'arm64/function.dart';
import 'code.dart';
import 'support.dart';

/// Translates a module to ARM64, throwing [EmitUnsupported] where it cannot.
EmittedCode emitArm64(LirModule module) {
  verifyModule(module);
  checkSupported(module);
  final assembler = Arm64Assembler();
  final functions = <String, int>{};
  for (final function in module.functions) {
    functions[function.name] = assembler.offset;
    Arm64Function(function, assembler).emit();
  }
  return EmittedCode(assembler.finish(), functions, assembler.relocations);
}
