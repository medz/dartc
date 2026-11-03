import 'type.dart';

/// How a callable is entered.
enum FunctionKind() {
  /// A top-level function or static method.
  function,

  /// A generative constructor initializing its first operand in place.
  initializer,

  /// A factory returning an instance without an implicit receiver.
  factory,

  /// A method dispatched on the runtime receiver.
  method,

  /// A dispatched property read.
  getter,

  /// A dispatched property write.
  setter;

  /// Whether Dart looks up the implementation on the runtime class.
  bool get isVirtual => this == method || this == getter || this == setter;

  /// Whether the receiver occupies the first SSA entry parameter.
  bool get hasReceiver => isVirtual || this == initializer;
}

/// A dispatch name including its operation and, for a private name, its library.
typedef MemberSelector = ({
  FunctionKind kind,
  String name,
  Uri? privateLibrary,
});

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

  /// The number of trailing positional parameters that may be omitted.
  int optionalPositional = 0,
  Map<String, bool> namedParameters = const {},
  Iterable<int> covariantParameters = const [],

  /// Whether the instance member is declared without an implementation.
  final bool isAbstract = false,

  /// The constructor named by a redirecting factory declaration.
  final FunctionTarget? redirect,
}) {
  /// The Dart call signature, excluding the receiver and returning the instance for constructors.
  final FunctionType signature = .new(
    kind == .initializer && owner != null ? owner : returnType,
    parameters,
    optionalPositional: optionalPositional,
    namedParameters: namedParameters,
  );

  /// The SSA entry parameter types, including the receiver when present.
  late final List<ValueType> parameterTypes = kind.hasReceiver
      ? .unmodifiable([owner!, ...signature.parameters])
      : signature.parameters;

  /// Explicit method parameters checked covariantly at entry.
  final Set<int> covariantParameters = .unmodifiable(covariantParameters);

  /// The runtime type of a tear-off. Covariant parameters reify as `Object?`.
  late final FunctionType reifiedSignature = covariantParameters.isEmpty
      ? signature
      : .new(
          signature.result,
          [
            for (final (i, type) in signature.parameters.indexed)
              covariantParameters.contains(i)
                  ? ValueType.object.nullable
                  : type,
          ],
          optionalPositional:
              signature.positionalCount - signature.requiredPositional,
          namedParameters: {
            for (final e in signature.named.entries) e.key: e.value.required,
          },
        );

  /// The name used for instance lookup after the receiver has been evaluated.
  MemberSelector get selector => (
    kind: kind,
    name: name,
    privateLibrary: name.startsWith('_') ? library : null,
  );

  /// The constructor whose body or initializer runs after factory redirection.
  FunctionTarget get implementation {
    var target = this;
    while (target.redirect != null) {
      target = target.redirect!;
    }
    return target;
  }

  this {
    if ((owner != null && owner!.library != library) ||
        (kind != .function && owner == null) ||
        this.covariantParameters.any(
          (i) => !kind.isVirtual || i < 0 || i >= signature.parameters.length,
        ) ||
        (kind == .initializer && returnType != .voidType) ||
        (kind == .factory && returnType != owner) ||
        isAbstract && !kind.isVirtual ||
        kind == .getter && signature.parameters.isNotEmpty ||
        kind == .setter &&
            (signature.positionalCount != 1 ||
                optionalPositional != 0 ||
                namedParameters.isNotEmpty ||
                returnType != .voidType)) {
      throw ArgumentError(
        'Inconsistent callable owner or constructor signature.',
      );
    }
    if (redirect case final target?) {
      if (kind != .factory ||
          !(target.kind == .factory ||
              target.kind == .initializer && !target.owner!.isAbstract) ||
          !returnType.accepts(target.owner!)) {
        throw ArgumentError('Invalid redirecting factory target.');
      }
      if (!signature.accepts(target.signature)) {
        throw ArgumentError('Incompatible redirecting factory signature.');
      }
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
