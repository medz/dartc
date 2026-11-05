import 'type.dart';

/// How a callable is entered.
enum FunctionKind() {
  /// A top-level function or static method.
  function,

  /// A top-level or static property read, without a receiver.
  staticGetter,

  /// A top-level or static property write, without a receiver.
  staticSetter,

  /// A lexical function paired with its captured environment.
  closure,

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
  Iterable<TypeParameterType> typeParameters = const [],

  /// Whether the instance member is declared without an implementation.
  final bool isAbstract = false,

  /// The immediately enclosing function of a local declaration or literal.
  final FunctionTarget? enclosing,

  /// The lexical source offset of that local function.
  final int? sourceOffset,
  Iterable<ValueType> captures = const [],

  /// The constructor named by a redirecting factory declaration.
  final FunctionTarget? redirect,

  /// The destination owner expressed in this declaration's type parameters.
  final ClassType? redirectOwnerType,
}) {
  /// The Dart call signature, excluding the receiver and returning the instance for constructors.
  final FunctionType signature = .new(
    kind == .initializer && owner != null ? owner : returnType,
    parameters,
    optionalPositional: optionalPositional,
    namedParameters: namedParameters,
    typeParameters: typeParameters,
  );

  /// The lexical type parameters declared by this function.
  List<TypeParameterType> get typeParameters => signature.typeParameters;

  /// The capture slots, in the order supplied when the closure is created.
  final List<ValueType> captures = .unmodifiable(captures);

  /// The entry types. A local function receives itself and its captures before explicit arguments.
  late final List<ValueType> parameterTypes = switch (kind) {
    .closure => .unmodifiable([
      signature,
      ...captures,
      ...signature.parameters,
    ]),
    _ when kind.hasReceiver => .unmodifiable([owner!, ...signature.parameters]),
    _ => signature.parameters,
  };

  /// The entry slot of the first explicit Dart parameter.
  int get argumentOffset => parameterTypes.length - signature.parameters.length;

  /// Explicit method parameters checked covariantly at entry.
  final Set<int> covariantParameters = .unmodifiable({
    ...covariantParameters,
    if (kind.isVirtual && owner != null)
      for (final (i, type) in parameters.indexed)
        if (containsCovariantTypeParameter(type, owner.typeParameters.toSet()))
          i,
  });

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
          typeParameters: signature.typeParameters,
          optionalPositional:
              signature.positionalCount - signature.requiredPositional,
          namedParameters: {
            for (final e in signature.named.entries) e.key: e.value.required,
          },
        );

  /// The function type exposed by extraction, before function instantiation.
  FunctionType tearOffSignature({ClassType? ownerType, bool reified = false}) {
    final base = reified ? reifiedSignature : signature;
    if (ownerType != null) {
      return substituteType(base, environmentFor(ownerType)) as FunctionType;
    }
    if ((kind == .initializer || kind == .factory) &&
        owner!.typeParameters.isNotEmpty) {
      return FunctionType(
        base.result,
        base.parameters,
        typeParameters: owner!.typeParameters,
        optionalPositional: base.positionalCount - base.requiredPositional,
        namedParameters: {
          for (final e in base.named.entries) e.key: e.value.required,
        },
      );
    }
    return base;
  }

  /// Instantiates this declaration's signature through the receiver's owner view.
  FunctionType signatureFor(ClassType receiver) =>
      substituteType(signature, environmentFor(receiver)) as FunctionType;

  Map<TypeParameterType, ValueType> environmentFor(ClassType receiver) {
    final view = owner == null ? null : receiver.asInstanceOf(owner!);
    if (view == null) throw ArgumentError('Incompatible member owner.');
    return view.typeEnvironment;
  }

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

  /// Resolves a construction while substituting each factory redirect's owner.
  ({FunctionTarget target, ClassType ownerType}) resolveConstruction(
    ClassType ownerType,
  ) {
    var target = this;
    var applied = ownerType;
    final visited = <FunctionTarget>{};
    while (true) {
      if (!visited.add(target) ||
          applied.declaration != target.owner?.declaration) {
        throw ArgumentError('Invalid constructor redirect chain.');
      }
      applied.validateTypeArguments();
      final destination = target.redirect;
      if (destination == null) return (target: target, ownerType: applied);
      applied = substituteType(
        target.redirectOwnerType ?? destination.owner!,
        target.environmentFor(applied),
      ) as ClassType;
      target = destination;
    }
  }

  this {
    if ((typeParameters.isNotEmpty &&
            (kind == .initializer ||
                kind == .factory ||
                kind == .getter ||
                kind == .setter ||
                kind == .staticGetter ||
                kind == .staticSetter)) ||
        (owner != null && owner!.library != library) ||
        (kind != .function &&
            kind != .closure &&
            kind != .staticGetter &&
            kind != .staticSetter &&
            owner == null) ||
        (kind == .closure
            ? enclosing == null ||
                  enclosing!.library != library ||
                  owner != null ||
                  sourceOffset == null ||
                  sourceOffset! < 0
            : enclosing != null ||
                  sourceOffset != null ||
                  this.captures.isNotEmpty) ||
        this.covariantParameters.any(
          (i) => !kind.isVirtual || i < 0 || i >= signature.parameters.length,
        ) ||
        (kind == .initializer && returnType != .voidType) ||
        (kind == .factory && returnType != owner) ||
        isAbstract && !kind.isVirtual ||
        (kind == .getter || kind == .staticGetter) &&
            signature.parameters.isNotEmpty ||
        (kind == .setter || kind == .staticSetter) &&
            (signature.positionalCount != 1 ||
                optionalPositional != 0 ||
                namedParameters.isNotEmpty ||
                returnType != .voidType)) {
      throw ArgumentError(
        'Inconsistent callable owner or constructor signature.',
      );
    }
    if (redirect == null && redirectOwnerType != null) {
      throw ArgumentError('Redirect owner requires a destination.');
    }
    if (redirect case final target?) {
      if (kind != .factory ||
          !(target.kind == .factory ||
              target.kind == .initializer && !target.owner!.isAbstract) ||
          (redirectOwnerType ?? target.owner!).declaration !=
              target.owner!.declaration ||
          !returnType.accepts(redirectOwnerType ?? target.owner!)) {
        throw ArgumentError('Invalid redirecting factory target.');
      }
      if (!signature.accepts(
        target.signatureFor(redirectOwnerType ?? target.owner!),
      )) {
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
}) {
  ValueType typeFor(ClassType receiver) {
    final view = receiver.asInstanceOf(owner);
    if (view == null) throw ArgumentError('Incompatible field owner.');
    return substituteType(type, view.typeEnvironment);
  }

  this {
    if (type is CellType) {
      throw ArgumentError('An instance field must hold a Dart value.');
    }
  }
}

/// A top-level or static non-constant variable, identified by its declaration.
///
/// Initializers run lazily on a read of unbound storage. A write before the first
/// read binds the slot without running its initializer. Static storage belongs
/// to the class declaration and is never specialized by class type arguments.
final class GlobalVariable(
  /// The library containing the source declaration.
  final Uri library,

  /// The source variable name within its declaring library or class.
  final String name,

  /// The closed Dart type accepted by the storage.
  final ValueType type, {

  /// The declaring class for static storage, absent for a top-level variable.
  final ClassType? owner,

  /// Whether binding is restricted to one successful initialization.
  final bool isFinal = false,

  /// Whether an absent initializer leaves the slot unbound instead of null.
  final bool isLate = false,

  /// The zero-argument body evaluated on a read of an unbound slot.
  final FunctionTarget? initializer,
}) {
  /// Whether source assignment can write the storage.
  bool get isWritable => !isFinal || isLate && initializer == null;

  this {
    if (!isDartType(type) || typeParametersIn(type).isNotEmpty) {
      throw ArgumentError('Global storage requires a closed Dart value type.');
    }
    if (owner != null &&
        (owner!.library != library || !identical(owner, owner!.declaration))) {
      throw ArgumentError('Global storage requires its declaring class.');
    }
    if (!isLate && initializer == null && (isFinal || !type.mayBeNull)) {
      throw ArgumentError(
        'Uninitialized non-late storage must be nullable and mutable.',
      );
    }
    if (initializer case final target?) {
      if (target.library != library ||
          target.owner != owner ||
          target.kind != .function ||
          target.parameterTypes.isNotEmpty ||
          target.typeParameters.isNotEmpty ||
          target.returnType != type) {
        throw ArgumentError('Invalid global initializer signature or owner.');
      }
    }
  }
}
