import 'package:dartc/lir.dart';

import 'arm64/assembler.dart';
import 'arm64/function.dart';
import 'code.dart';
import 'support.dart';

/// Translates a module to ARM64, throwing [EmitUnsupported] where it cannot.
///
/// External functions are C functions taking and returning 64-bit words; their
/// convention agrees with the one used between functions here.
EmittedCode emitArm64(LirModule module) {
  verifyModule(module);
  checkSupported(module);
  final assembler = Arm64Assembler();
  final functions = <String, int>{};
  for (final function in module.functions) {
    functions[function.name] = assembler.offset;
    Arm64Function(function, assembler).emit();
  }
  return EmittedCode(
    assembler.finish(),
    functions,
    assembler.relocations,
    externals: module.externals.map((external) => external.name),
  );
}
