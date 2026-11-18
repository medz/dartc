import 'signature.dart';
import 'execution_shape.dart';
import 'type.dart';
import 'type_metadata.dart';

/// One explicit calling shape shared by compatible function-value entries.
///
/// Language function types and identities remain on the original values. The
/// closed language signature and physical components are independent contracts.
final class CallEntryShape(
  final int slot,
  final ValueType result,
  Iterable<ValueType> positional, {
  Map<String, ValueType> named = const {},
  final int typeArgumentCount = 0,
  final bool checked = false,
  final FunctionTarget? failure,
  Iterable<String> failureNamed = const [],
  ExecutionSignature? execution,
}) {
  final List<ValueType> positional = .unmodifiable(positional);
  final Map<String, ValueType> named = .unmodifiable({
    for (final name in named.keys.toList()..sort()) name: named[name]!,
  });

  /// Original named argument order expected by the ordinary failure body.
  final List<String> failureNamed = .unmodifiable(failureNamed);

  /// The original function environment precedes values and reified arguments.
  late final FunctionType signature = FunctionType(result, [
    ValueType.object.nullable,
    ...positional,
    ...named.values,
    for (var i = 0; i < typeArgumentCount; i++) TypeMetadata.type,
  ]);

  /// The actual entry components, independent of the language signature.
  final ExecutionSignature? _execution = execution;
  late final ExecutionSignature execution =
      _execution ??
      ExecutionSignature(
        signature.parameters.map(ExecutionShapes.forType),
        ExecutionShapes.forType(result),
      );

  this {
    if (checked != (failure != null) ||
        this.failureNamed.toSet().length != this.failureNamed.length ||
        checked &&
            (this.failureNamed.length != this.named.length ||
                !this.failureNamed.every(this.named.containsKey)) ||
        !checked && this.failureNamed.isNotEmpty) {
      throw ArgumentError(
        'Checked calls require their actual failure binding.',
      );
    }
    if (slot < 0 || typeArgumentCount < 0) {
      throw ArgumentError('Call entry indices cannot be negative.');
    }
    if (this.execution.parameters.length != signature.parameters.length) {
      throw ArgumentError(
        'Call entry execution arity must match its signature.',
      );
    }
    if ([
      result,
      ...this.positional,
      ...this.named.values,
    ].any((type) => type.freeTypeParameters.isNotEmpty || type is CellType)) {
      throw ArgumentError('Call entries require closed language signatures.');
    }
  }
}

/// Real execution entries selected by a function value's source implementation.
///
/// This mapping changes execution, never language identity. Only an actual
/// invocation enters an adapter; retaining the mapping creates no entry roots.
final class CallEntryBinding(
  final CallEntryShape shape,
  Map<FunctionTarget, FunctionTarget> entries, {
  ExecutionShapes? executionShapes,
}) {
  final Map<FunctionTarget, FunctionTarget> entries = .unmodifiable(entries);

  this {
    for (final target in this.entries.values) {
      if (target.kind != .function ||
          target.isAbstract ||
          target.implementation != target ||
          target.typeParameters.isNotEmpty ||
          target.signature.optionalPositional != 0 ||
          target.signature.named.isNotEmpty ||
          target.parameterTypes.length != shape.signature.parameters.length ||
          !shape.result.accepts(target.returnType)) {
        throw ArgumentError('A call entry must implement its complete shape.');
      }
    }
    checkExecution(executionShapes ?? ExecutionShapes.defaults);
  }

  /// Revalidates a persistent binding against its current program authority.
  void checkExecution(ExecutionShapes shapes) {
    if (entries.values.any(
      (target) => shapes.entryOf(target) != shape.execution,
    )) {
      throw ArgumentError(
        'A call entry must implement its execution signature.',
      );
    }
  }
}
