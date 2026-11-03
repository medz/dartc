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
  final int optionalPositional = 0,
  Map<String, bool> namedParameters = const {},

  /// Whether the instance member is declared without an implementation.
  final bool isAbstract = false,
}) {
  /// The entry parameter types, including the receiver when present.
  final List<ValueType> parameterTypes = .unmodifiable([
    if (kind.hasReceiver && owner != null) owner,
    ...parameters,
  ]);

  /// Named parameters in declaration order, with `true` for required names.
  final Map<String, bool> namedParameters = .unmodifiable(namedParameters);

  /// The number of explicit positional parameters.
  int get positionalCount =>
      parameterTypes.length -
      (kind.hasReceiver ? 1 : 0) -
      namedParameters.length;

  /// The name used for instance lookup after the receiver has been evaluated.
  MemberSelector get selector => (
    kind: kind,
    name: name,
    privateLibrary: name.startsWith('_') ? library : null,
  );

  /// The explicit parameter slots that require a default on omission.
  Iterable<int> get optionalSlots sync* {
    final count = positionalCount;
    for (var i = count - optionalPositional; i < count; i++) {
      yield i;
    }
    for (final (i, required) in namedParameters.values.indexed) {
      if (!required) yield count + i;
    }
  }

  /// Places supplied arguments in this declaration's order and fills omitted slots.
  List<T> bind<T>(
    List<T> positional,
    Map<String, T> named,
    T Function(int) omitted,
  ) {
    final count = positionalCount;
    if (positional.length < count - optionalPositional ||
        positional.length > count ||
        named.keys.any((name) => !namedParameters.containsKey(name))) {
      throw ArgumentError('Arguments do not match $name.');
    }
    final result = <T>[...positional];
    while (result.length < count) {
      result.add(omitted(result.length));
    }
    for (final MapEntry(:key, value: required) in namedParameters.entries) {
      if (named.containsKey(key)) {
        result.add(named[key] as T);
      } else if (required) {
        throw ArgumentError('Missing required argument $key.');
      } else {
        result.add(omitted(result.length));
      }
    }
    return result;
  }

  this {
    if ((owner != null && owner!.library != library) ||
        (kind != .function && owner == null) ||
        (kind == .initializer && returnType != .voidType) ||
        (kind == .factory && returnType != owner) ||
        optionalPositional < 0 ||
        optionalPositional > positionalCount ||
        optionalPositional > 0 && namedParameters.isNotEmpty ||
        isAbstract && !kind.isVirtual ||
        kind == .getter &&
            (positionalCount != 0 || namedParameters.isNotEmpty) ||
        kind == .setter &&
            (positionalCount != 1 ||
                optionalPositional != 0 ||
                namedParameters.isNotEmpty ||
                returnType != .voidType)) {
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
