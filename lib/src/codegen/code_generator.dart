import 'package:dartc/object.dart';
import 'package:dartc/target.dart';

import 'program_preparation.dart';

/// Selects instructions, allocates locations and emits a prepared program.
abstract interface class CodeGenerator() {
  /// The explicit output platform, independent of the compiler host.
  Target get target;

  /// Emits a closed program prepared for [target].
  ///
  /// A mismatched target or invalidated analysis is rejected before emission.
  /// Calls and native dependencies must already belong to [program]; omitted
  /// dependencies are internal errors rather than requests to expand it.
  /// Each invocation owns its machine locations, constants and relocations.
  ObjectModule generate(PreparedProgram program);
}
