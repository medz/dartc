import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/arm64.dart' as arm64;
import 'package:dartc/artifact.dart' as artifact;
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:dartc/x64.dart' as x64;

import 'integer_function.dart';

/// Generates register-only integer leaf exports for an explicit target.
///
/// Unsupported IR, stack arguments and register pressure are diagnosed before
/// an artifact is returned. This backend does not yet provide a Dart runtime.
final class CodeGenerator(final Target target) {
  /// Generates [exports], mapping each function to its exact linker symbol.
  artifact.ObjectFile generate(
    IrProgram program,
    Map<FunctionTarget, String> exports,
  ) {
    if (exports.isEmpty) throw ArgumentError('No native exports.');
    final code = BytesBuilder(copy: false);
    final symbols = <artifact.Symbol>[];
    for (final MapEntry(key: declaration, value: name) in exports.entries) {
      final function = program.implementationOf(declaration);
      if (function is! IrFunction) {
        throw ArgumentError('Export has no body: $name');
      }
      final bytes = switch (target.architecture) {
        .arm64 => IntegerFunction(
          Arm64Abi(arm64.Assembler()),
        ).generate(function),
        .x64 => IntegerFunction(X64Abi(x64.Assembler())).generate(function),
      };
      while (code.length % 16 != 0) {
        code.addByte(0);
      }
      symbols.add(artifact.Symbol(name, code.length, bytes.length));
      code.add(bytes);
    }
    return artifact.ObjectFile(target, code.takeBytes(), symbols);
  }
}
