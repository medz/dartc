import 'execution_shape.dart';
import 'signature.dart';
import 'type.dart';

/// Ordinary member entries sharing one caller's physical invocation contract.
///
/// Source members still determine dispatch and language identity. The entries
/// own argument/default/type/result adaptation and are reached only by calls.
final class MemberEntryBinding(
  final FunctionType signature,
  final ExecutionSignature execution,
  final int positionalCount,
  Iterable<String> names,
  final int typeArgumentCount,
  Map<FunctionTarget, FunctionTarget> entries, {
  required ExecutionShapes executionShapes,
}) {
  final List<String> names = .unmodifiable(names);
  final Map<FunctionTarget, FunctionTarget> entries = .unmodifiable(entries);

  this {
    if (positionalCount < 0 ||
        typeArgumentCount < 0 ||
        this.names.toSet().length != this.names.length ||
        signature.typeParameters.isNotEmpty ||
        signature.freeTypeParameters.isNotEmpty ||
        signature.optionalPositional != 0 ||
        signature.named.isNotEmpty ||
        signature.parameters.length !=
            1 + positionalCount + this.names.length + typeArgumentCount ||
        execution.parameters.length != signature.parameters.length) {
      throw ArgumentError(
        'Member entries require a closed complete signature.',
      );
    }
    for (final entry in this.entries.entries) {
      final target = entry.value;
      if (!entry.key.kind.isVirtual ||
          target.kind != .function ||
          target.isAbstract ||
          target.implementation != target ||
          target.signature != signature) {
        throw ArgumentError('A member entry must implement its invocation.');
      }
    }
    checkExecution(executionShapes);
  }

  /// Rechecks persisted entries against the current common shape authority.
  void checkExecution(ExecutionShapes shapes) {
    if (entries.values.any((target) => shapes.entryOf(target) != execution)) {
      throw ArgumentError('Member entry execution signatures disagree.');
    }
  }
}
