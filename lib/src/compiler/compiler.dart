import 'dart:io';

import 'package:dartc/analyzer.dart';
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
  Future<CompiledLibrary> compile(List<String> paths) => CheckedLibraries.read(
    paths,
    (input) async {
      final program = Lowering.lower(input);
      final exports = await NativeExports.read(input, program);
      final object = CodeGenerator(target).generate(program, {
        for (final export in exports.functions)
          export.function: export.linkerName(target),
      });
      return CompiledLibrary(object, exports, [
        for (final library in input.libraries)
          for (final unit in library.units) File(unit.path).absolute.uri,
      ]);
    },
    sdk: sdk,
    includeDependencies: true,
  );
}
