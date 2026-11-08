import 'package:dartc/artifact.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';

/// Generates relocatable native code from verified Dart IR.
abstract interface class CodeGenerator() {
  /// The explicit output platform, independent of the host.
  Target get target;

  /// Generates functions using their exact linker names.
  ///
  /// Unsupported operations fail before an artifact is returned.
  ObjectFile generate(IrProgram program, Map<FunctionTarget, String> exports);
}
