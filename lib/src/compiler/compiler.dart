import 'dart:io';

import 'package:dartc/analyzer.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/lowering.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

import 'compiled_library.dart';

/// Compiles annotated native exports for an explicit output target.
final class Compiler(final Target target, {final DartSdk? sdk}) {
  /// Checks the non-SDK dependency closure and builds all annotated exports.
  ///
  /// No output files are changed until the returned library is written.
  Future<CompiledLibrary> compile(List<String> paths) =>
      AnalysisSession(paths, sdk: sdk, includeDependencies: true).use((input) {
        final (:program, :exports) = Lowering().lower(input);
        final CodeGenerator generator = switch (target.architecture) {
          .arm64 => Arm64CodeGenerator(target),
          .x64 => X64CodeGenerator(target),
        };
        final definitions = <FunctionTarget>{};
        void include(FunctionTarget target) {
          if (!definitions.add(target)) return;
          final function = program.implementationOf(target);
          if (function is! IrFunction) {
            throw UnsupportedError('Native body unavailable: ${target.name}');
          }
          function.callees.forEach(include);
        }

        exports.keys.forEach(include);
        final object = generator.generate(
          program,
          definitions: definitions,
          exports: exports,
        );
        return CompiledLibrary(object, NativeExports(exports.values), [
          for (final library in input.libraries)
            for (final unit in library.units) File(unit.path).absolute.uri,
        ]);
      });
}
