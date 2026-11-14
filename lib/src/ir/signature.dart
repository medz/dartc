import 'type.dart';

/// A source position and its logical frame chain, innermost first.
///
/// Supplied coordinates must be absolute and one-based, or construction throws
/// [ArgumentError]. An omitted position does not erase the logical frame.
final class SourceLocation(
  /// The original source coordinates, absent when only frame identity is known.
  final ({Uri uri, int line, int column})? position, {

  /// The logical callable, or the containing physical callable when omitted.
  final FunctionTarget? function,

  /// The call site in the next outer logical frame.
  final SourceLocation? caller,
}) {
  this {
    if (position case (:final uri, :final line, :final column)
        when !uri.isAbsolute || line < 1 || column < 1) {
      throw ArgumentError('Expected absolute, one-based source coordinates.');
    }
  }

  /// Binds unnamed frames to [owner] and appends the outer [callSite].
  /// Existing logical identities and positions are preserved.
  SourceLocation inlinedAt(FunctionTarget owner, SourceLocation callSite) =>
      SourceLocation(
        position,
        function: function ?? owner,
        caller: caller?.inlinedAt(owner, callSite) ?? callSite,
      );

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      position == other.position &&
      function == other.function &&
      caller == other.caller;

  @override
  int get hashCode => Object.hash(position, function, caller);
}

/// A deferred import's source prefix and the library it loads.
///
/// Loading one prefix does not load another prefix for the same library.
final class DeferredImport(
  /// The source unit declaring the import, including imports inside parts.
  final Uri unit,

  /// The prefix whose loading state is checked.
  final String prefix,

  /// The resolved library URI, after conditional import selection.
  final Uri library,
) {
  this {
    if (!unit.isAbsolute || !library.isAbsolute || prefix.isEmpty) {
      throw ArgumentError(
        'Expected resolved library URIs and an import prefix.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DeferredImport &&
      unit == other.unit &&
      prefix == other.prefix &&
      library == other.library;

  @override
  int get hashCode => Object.hash(unit, prefix, library);
}

/// How a body runs, independently of its callable's dispatch convention.
enum FunctionBodyKind() {
  /// Executes once when called and returns its result directly.
  synchronous,

  /// Returns an iterable; each iterator runs a fresh, suspendable activation.
  syncGenerator,

  /// Starts immediately and completes a Future, suspending at explicit awaits.
  asynchronous,

  /// Returns a single-subscription stream whose body starts on listen.
  asyncGenerator,
}

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

  /// A lazy instance-field expression evaluated on its declaring storage.
  fieldInitializer,

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
  bool get hasReceiver =>
      isVirtual || this == initializer || this == fieldInitializer;
}

/// A dispatch name scoped by a source library or a generated declaring class.
typedef MemberSelector = ({
  FunctionKind kind,
  String name,
  Object? privateScope,
});

/// Validates the operation and library identity of an instance selector.
void checkMemberSelector(MemberSelector selector) {
  if (!selector.kind.isVirtual ||
      selector.name.isEmpty ||
      selector.name.startsWith('_') != (selector.privateScope != null) ||
      switch (selector.privateScope) {
        null => false,
        Uri uri => !uri.isAbsolute,
        ClassType type => type.library != null || type != type.declaration,
        _ => true,
      }) {
    throw ArgumentError('Invalid member selector.');
  }
}

/// The identity and signature of a statically resolved Dart callable.
///
/// Use the same target object for a function's definition and all its calls.
final class FunctionTarget(
  /// The declaring source library, or null for a generated definition.
  final Uri? library,

  /// The source name, or a diagnostic label for a generated definition.
  final String name,

  /// The static type of the result.
  final ValueType returnType,
  Iterable<ValueType> parameters, {

  /// The declaring class of a member.
  final ClassType? owner,

  /// The entry and return protocol of the body.
  final FunctionKind kind = .function,

  /// The originating private scope, when inherited from a different owner.
  final Object? privateSelectorScope,

  /// The number of trailing positional parameters that may be omitted.
  int optionalPositional = 0,
  Map<String, bool> namedParameters = const {},
  Iterable<int> covariantParameters = const [],
  Iterable<TypeParameterType> typeParameters = const [],

  /// Whether the instance member is declared without an implementation.
  final bool isAbstract = false,

  /// The immediately enclosing function of a local declaration or literal.
  final FunctionTarget? enclosing,

  /// The source offset of a local function. Synthesized functions can share an offset.
  final int? sourceOffset,

  /// The original declaration or literal start, when a source position is known.
  final SourceLocation? declarationLocation,
  Iterable<ValueType> captures = const [],

  /// The capture slot linking this lexical function to its asynchronous awaiter.
  final int? awaiterCapture,

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
    _ when kind.hasReceiver => .unmodifiable([
      owner == ValueType.nullClass ? ValueType.nullType : owner!,
      ...signature.parameters,
    ]),
    _ => signature.parameters,
  };

  /// The entry slot of the first explicit Dart parameter.
  int get argumentOffset => parameterTypes.length - signature.parameters.length;

  late final Set<int> _covariantParameters;

  /// Explicit method parameters checked covariantly at entry.
  Set<int> get covariantParameters => _covariantParameters;

  /// Whether a member result needs checking against the caller's receiver view.
  bool get requiresResultCheck =>
      kind.isVirtual &&
      owner!.typeParameters.isNotEmpty &&
      returnType.requiresCovariantCheck(
        owner!.typeParameters.toSet(),
        forResult: true,
      );

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
          optionalPositional: signature.optionalPositional,
          namedParameters: signature.namedParameters,
        );

  /// The function type exposed by extraction, before function instantiation.
  FunctionType tearOffSignature({ClassType? ownerType, bool reified = false}) {
    final base = reified ? reifiedSignature : signature;
    if (ownerType != null) {
      return base.substitute(environmentFor(ownerType)) as FunctionType;
    }
    if ((kind == .initializer || kind == .factory) &&
        owner!.typeParameters.isNotEmpty) {
      return FunctionType(
        base.result,
        base.parameters,
        typeParameters: owner!.typeParameters,
        optionalPositional: base.optionalPositional,
        namedParameters: base.namedParameters,
      );
    }
    return base;
  }

  /// Instantiates this declaration's signature through the receiver's owner view.
  FunctionType signatureFor(ClassType receiver) =>
      signature.substitute(environmentFor(receiver)) as FunctionType;

  Map<TypeParameterType, ValueType> environmentFor(ClassType receiver) {
    final view = owner == null ? null : receiver.asInstanceOf(owner!);
    if (view == null) throw ArgumentError('Incompatible member owner.');
    return view.typeEnvironment;
  }

  /// The name used for instance lookup after the receiver has been evaluated.
  MemberSelector get selector => (
    kind: kind,
    name: kind == .method && name == '-' && signature.parameters.isEmpty
        ? 'unary-'
        : name,
    privateScope: name.startsWith('_')
        ? privateSelectorScope ?? library ?? owner
        : null,
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
      applied = (target.redirectOwnerType ?? destination.owner!).substitute(
        target.environmentFor(applied),
      ) as ClassType;
      target = destination;
    }
  }

  this {
    if (declarationLocation case final location?
        when location.position == null ||
            location.function != null ||
            location.caller != null) {
      throw ArgumentError('Invalid declaration location for $name.');
    }
    final ownerParameters =
        kind.isVirtual && owner != null && owner!.typeParameters.isNotEmpty
        ? owner!.typeParameters.toSet()
        : const <TypeParameterType>{};
    // The signature has already materialized the possibly lazy input once.
    _covariantParameters = Set<int>.unmodifiable({
      ...covariantParameters,
      if (ownerParameters.isNotEmpty)
        for (final (i, type) in signature.parameters.indexed)
          if (type.requiresCovariantCheck(ownerParameters)) i,
    });

    if (privateSelectorScope != null &&
        (!kind.isVirtual || !name.startsWith('_'))) {
      throw ArgumentError(
        'Private selector provenance requires a private virtual member.',
      );
    }
    if (kind.isVirtual) checkMemberSelector(selector);
    if (library != null && !library!.isAbsolute) {
      throw ArgumentError('Expected a resolved source library URI.');
    }
    if (owner != null &&
            (library != null && owner!.library != library ||
                !identical(owner, owner!.declaration)) ||
        owner == null && (kind.hasReceiver || kind == .factory) ||
        isAbstract && !kind.isVirtual) {
      throw ArgumentError('Invalid callable owner.');
    }
    if (kind == .closure) {
      if (enclosing == null ||
          enclosing!.library != library ||
          owner != null ||
          sourceOffset == null ||
          sourceOffset! < 0) {
        throw ArgumentError('Invalid lexical function.');
      }
    } else if (enclosing != null ||
        sourceOffset != null ||
        this.captures.isNotEmpty) {
      throw ArgumentError(
        'Only lexical functions have an enclosing function and captures.',
      );
    }
    if (awaiterCapture != null &&
        (kind != .closure ||
            awaiterCapture! < 0 ||
            awaiterCapture! >= this.captures.length)) {
      throw ArgumentError('Invalid awaiter capture slot.');
    }
    if (this.covariantParameters.any(
      (slot) =>
          !kind.isVirtual || slot < 0 || slot >= signature.parameters.length,
    )) {
      throw ArgumentError('Invalid covariant parameter slot.');
    }
    final validSignature = switch (kind) {
      .function || .closure || .method => true,
      _ when signature.typeParameters.isNotEmpty => false,
      .initializer => returnType == .voidType,
      .fieldInitializer ||
      .getter ||
      .staticGetter => signature.parameters.isEmpty,
      .factory =>
        returnType ==
            (owner == ValueType.nullClass ? ValueType.nullType : owner),
      .setter || .staticSetter =>
        signature.requiredPositional == 1 &&
            signature.parameters.length == 1 &&
            returnType == .voidType,
    };
    if (!validSignature) {
      throw ArgumentError('Invalid signature for ${kind.name} $name.');
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

  /// Whether binding is restricted to initialization or one late assignment.
  final bool isFinal = false,

  /// Whether unbound reads lazily initialize the slot or raise a late error.
  final bool isLate = false,

  /// The receiver-only body evaluated on an unbound late read.
  final FunctionTarget? initializer,
}) {
  /// Whether source assignment can write the storage outside a constructor.
  bool get isWritable => !isFinal || isLate && initializer == null;

  /// Whether reading through a wider receiver view can fail a type check.
  bool get requiresReadCheck =>
      owner.typeParameters.isNotEmpty &&
      type.requiresCovariantCheck(
        owner.typeParameters.toSet(),
        forResult: true,
      );

  /// Substitutes type arguments along the superclass chain that supplies this slot.
  ValueType typeFor(ClassType receiver) {
    for (ClassType? view = receiver; view != null; view = view.superclass) {
      if (identical(view.declaration, owner)) {
        return type.substitute(view.typeEnvironment);
      }
    }
    throw ArgumentError('Receiver does not inherit this field.');
  }

  this {
    if (!identical(owner, owner.declaration) ||
        !isDartType(type) ||
        type.freeTypeParameters.any((p) => !owner.typeParameters.contains(p))) {
      throw ArgumentError('Invalid instance field type or declaring class.');
    }
    if (initializer case final target?) {
      if (!isLate ||
          target.owner != owner ||
          target.kind != .fieldInitializer ||
          target.signature.parameters.isNotEmpty ||
          target.typeParameters.isNotEmpty ||
          target.returnType != type) {
        throw ArgumentError(
          'Invalid instance field initializer signature or owner.',
        );
      }
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
    if (!isDartType(type) || type.freeTypeParameters.isNotEmpty) {
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
