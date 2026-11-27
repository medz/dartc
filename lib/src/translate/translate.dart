import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'program.dart';
import 'reasons.dart';

/// Translates everything the program's `main` can reach, for [target]. It
/// checks assertions outside the SDK if [checksAssertions], and records why
/// each function is part of the program in [reasons] if it is given.
///
/// Throws [CompileFailure] at the first construct not supported yet.
HirModule translateProgram(
  SourceProgram program, {
  Target target = .macosArm64,
  bool checksAssertions = false,
  Reasons? reasons,
}) => ProgramTranslator(
  program,
  target,
  checksAssertions: checksAssertions,
  reasons: reasons,
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
