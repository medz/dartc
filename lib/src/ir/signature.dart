import 'type.dart';

/// How a callable is entered.
enum FunctionKind() {
  /// A top-level function or static method.
  function,

  /// A generative constructor initializing its first operand in place.
  initializer,

  /// A factory returning an instance without an implicit receiver.
  factory,
}

/// The identity and signature of a statically resolved Dart callable.
///
/// Use the same target object for a function's definition and all its calls.
final class FunctionTarget(
  /// The URI of the library that declares the function.
  final Uri library,

  /// The declared name within [library].
  final String name,

  /// The static type of the result.
  final ValueType returnType,
  Iterable<ValueType> parameters, {

  /// The declaring class of a member.
  final ClassType? owner,

  /// The entry and return protocol of the body.
  final FunctionKind kind = .function,
}) {
  /// The entry parameters, including the receiver of an initializer in slot zero.
  final List<ValueType> parameterTypes = .unmodifiable([
    if (kind == .initializer && owner != null) owner,
    ...parameters,
  ]);

  this {
    if ((owner != null && owner!.library != library) ||
        (kind != .function && owner == null) ||
        (kind == .initializer && returnType != .voidType) ||
        (kind == .factory && returnType != owner)) {
      throw ArgumentError(
        'Inconsistent callable owner or constructor signature.',
      );
    }
  }
}

/// Storage declared by one class, distinct from its overridable getter and setter.
final class InstanceField(
  /// The class declaring the storage.
  final ClassType owner,

  /// The field name within [owner].
  final String name,

  /// The Dart type accepted by the storage.
  final ValueType type, {

  /// Whether writes are restricted to initialization.
  final bool isFinal = false,
});
