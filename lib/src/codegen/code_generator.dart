import 'package:dartc/artifact.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

/// Generates relocatable native code from verified Dart IR.
abstract interface class CodeGenerator() {
  /// The explicit output platform, independent of the host.
  Target get target;

  /// Generates the selected definitions and exposes the declared native exports.
  ///
  /// Unsupported operations fail before an artifact is returned.
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
  });
}
