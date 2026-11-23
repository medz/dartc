import 'package:dartc/lir.dart';

import 'arm64/assembler.dart';
import 'arm64/function.dart';
import 'code.dart';
import 'stack_maps.dart';
import 'support.dart';

/// Translates a module to ARM64, throwing [EmitUnsupported] where it cannot.
///
/// External functions are C functions taking and returning 64-bit words; their
/// convention agrees with the one used between functions here.
EmittedCode emitArm64(LirModule module) {
  verifyModule(module);
  checkSupported(module);
  final assembler = Arm64Assembler();
  final functions = <String, int>{textSymbol: 0};
  final maps = <StackMap>[];
  for (final function in module.functions) {
    functions[function.name] = assembler.offset;
    maps.addAll(Arm64Function(function, assembler).emit());
  }
  return EmittedCode(
    assembler.finish(),
    functions,
    assembler.relocations,
    externals: module.externals.map((external) => external.name),
    data: {
      for (final data in module.data) data.name: data.bytes,
      if (_usesStackMaps(module)) stackMapSymbol: encodeStackMaps(maps),
    },
    tables: {for (final table in module.tables) table.name: table.functions},
    objects: {
      for (final object in module.statics)
        object.name: EmittedObject(
          object.bytes,
          object.references,
          writable: object.writable,
        ),
    },
    stackMaps: maps,
  );
}

bool _usesStackMaps(LirModule module) => module.functions.any(
  (function) => function.blocks.any(
    (block) => block.instructions.any(
      (instruction) =>
          instruction is SymbolAddress && instruction.symbol == stackMapSymbol,
    ),
  ),
);
