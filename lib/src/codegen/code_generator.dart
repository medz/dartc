import 'package:dartc/object.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

/// Generates relocatable native code from verified Dart IR.
abstract interface class CodeGenerator() {
  /// The explicit output platform, independent of the host.
  Target get target;

  /// Generates the selected definitions and exposes the declared native exports.
  ///
  /// Definitions must belong to [program] and include every directly called
  /// body or external declaration. [imports] binds external declarations to
  /// native signatures; [exports] exposes a subset of the supplied Dart bodies.
  /// The caller resolves native symbols and supplies their implementations when
  /// linking. Unsupported operations fail before an artifact is returned.
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
    Map<FunctionTarget, NativeImport> imports = const {},
  });
}
