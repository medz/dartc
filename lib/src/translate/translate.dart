import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'program.dart';

/// Translates everything the program's `main` can reach, for [target]. It
/// checks assertions outside the SDK if [checksAssertions].
///
/// Throws [CompileFailure] at the first construct not supported yet.
HirModule translateProgram(
  SourceProgram program, {
  Target target = .macosArm64,
  bool checksAssertions = false,
}) => ProgramTranslator(
  program,
  target,
  checksAssertions: checksAssertions,
).translate();

/// Translates everything that the functions which the program exports can
/// reach, and writes a header of C for those.
({HirModule module, String header}) translateLibrary(
  SourceProgram program, {
  Target target = .macosArm64,
  bool checksAssertions = false,
}) => ProgramTranslator(
  program,
  target,
  checksAssertions: checksAssertions,
).translateLibrary();
