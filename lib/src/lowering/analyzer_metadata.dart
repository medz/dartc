import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

// The public analyzer API omits function-constant arguments/alias identity and
// pattern context schemas, generic defaults, forwarding metadata and superclass
// storage. Keep these analyzer 14.7 reads isolated instead of reconstructing
// inference or identity from lossy public types.
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/ast.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_algebra.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_schema_elimination.dart'
    as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/constant/value.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/element.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/member.dart' as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/inheritance_manager3.dart'
    as internal;
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/non_covariant_type_parameter_position.dart'
    as internal;

// ignore: implementation_imports
import 'package:analyzer/src/dart/resolver/applicable_extensions.dart'
    as internal;

/// Recovers source arguments of an already-selected extension or extension type.
/// Applicability inference is not generic-function default generation.
List<DartType> extensionTypeArguments(
  ExecutableElement selected,
  LibraryElement library, {
  DartType? receiverType,
  ast.ExtensionOverride? override,
  ExtensionElement? lexicalExtension,
  bool nullAware = false,
}) {
  final owner =
      selected.baseElement.enclosingElement as TypeParameterizedElement;
  final parameters = owner.typeParameters;
  if (override != null) {
    if (override.element != owner ||
        override.typeArgumentTypes?.length != parameters.length) {
      throw UnsupportedError(
        'Analyzer extension override metadata unavailable.',
      );
    }
    return override.typeArgumentTypes!;
  }
  if (parameters.isEmpty) return const [];
  if (lexicalExtension == owner) {
    return [
      for (final p in parameters) p.instantiate(nullabilitySuffix: .none),
    ];
  }
  if (selected is internal.SubstitutedExecutableElementImpl &&
      parameters.every(selected.substitution.map.containsKey)) {
    return [for (final p in parameters) selected.substitution.map[p]!];
  }
  receiverType ??= lexicalExtension?.extendedType;
  if (receiverType == null) {
    throw UnsupportedError('Analyzer extension receiver metadata unavailable.');
  }
  if (owner is ExtensionTypeElement) {
    final seen = <DartType>{};
    while (receiverType is TypeParameterType && seen.add(receiverType)) {
      receiverType = receiverType.bound;
    }
    if (receiverType is InterfaceType) {
      final view = receiverType.asInstanceOf(owner);
      if (view != null) return view.typeArguments;
    }
    throw UnsupportedError(
      'Analyzer extension type receiver metadata unavailable.',
    );
  }
  final candidates = internal.ExtensionsExtensions([owner as ExtensionElement])
      .applicableTo(
        targetLibrary: library,
        targetType: nullAware
            ? library.typeSystem.promoteToNonNull(receiverType)
            : receiverType,
      );
  if (candidates.length != 1) {
    throw UnsupportedError('Analyzer selected extension is not applicable.');
  }
  final substitution = candidates.single.substitution;
  return [for (final p in parameters) substitution.map[p]!];
}

/// Selected effective signatures that may require typed forwarding bodies.
///
/// Analyzer's marker includes inherited forwarders and some concrete overrides;
/// actual implementation planning must distinguish these from new bodies.
/// Private obligations also exist without a nontrivial noSuchMethod override.
/// An incompatible inherited private implementation needs a replacing body,
/// not a fallback-only guard.
List<
  ({
    ExecutableElement member,
    Uri? privateLibrary,
    bool overridesConcrete,
    Set<int> additionalCovariance,
    Iterable<ExecutableElement> covarianceContributors,
  })
>
noSuchMethodForwarderCandidates(
  InterfaceElement element, {
  void Function(ExecutableElement, Uri?, Iterable<ExecutableElement>)?
  checkCovariance,
}) {
  if (element is! internal.InterfaceElementImpl) {
    throw UnsupportedError('Analyzer noSuchMethod metadata unavailable.');
  }
  final isAbstract = element is internal.ClassElementImpl && element.isAbstract;
  if (isAbstract && checkCovariance == null) return const [];
  final interface = element.inheritanceManager.getInterface(element);
  late final inherited = element.inheritedConcreteMembers;
  final result =
      <
        ({
          ExecutableElement member,
          Uri? privateLibrary,
          bool overridesConcrete,
          Set<int> additionalCovariance,
          Iterable<ExecutableElement> covarianceContributors,
        })
      >[];
  for (final entry in interface.map.entries) {
    final name = entry.key;
    final declared = interface.declared[name];
    late final contributors = <ExecutableElement>[
      declared ?? entry.value,
      ?interface.implemented[name],
      ...?interface.overridden[name],
    ];
    if (checkCovariance != null && (declared == null || declared.isAbstract)) {
      checkCovariance(declared ?? entry.value, name.libraryUri, contributors);
    }
    if (isAbstract) continue;
    final foreignPrivate =
        name.libraryUri != null && name.libraryUri != element.library.uri;
    if (!foreignPrivate && !interface.noSuchMethodForwarders.contains(name)) {
      continue;
    }
    final implementation = inherited[name];
    // A legal covariant override can still have a narrower entry signature.
    // Replacement needs function subtyping, not override legality (which erases
    // covariant parameter types to Object?).
    final overridesConcrete =
        foreignPrivate &&
        implementation != null &&
        !implementation.isAbstract &&
        !element.library.typeSystem.isSubtypeOf(
          implementation.type,
          entry.value.type,
        );
    // An incompatible real implementation still carries its old types/defaults.
    // The combined interface is the exact replacement signature instead.
    final selected = overridesConcrete
        ? entry.value
        : interface.implemented[name] ?? entry.value;
    // Selected declaration covariance is read by target construction. Only a
    // real replacement needs additional flags from the old implementation.
    var additionalCovariance = const <int>{};
    if (overridesConcrete) {
      if (interface.implemented[name] case final implemented?) {
        additionalCovariance = combinedCovariance(selected, [implemented])
          ..removeAll({
            for (final (i, p) in selected.formalParameters.indexed)
              if (p.isCovariant) i,
          });
      }
    }
    result.add((
      member: selected,
      privateLibrary: name.libraryUri,
      overridesConcrete: overridesConcrete,
      additionalCovariance: additionalCovariance,
      covarianceContributors: contributors,
    ));
  }
  return result;
}

/// Exact own/overridden contributors for a declared virtual implementation.
/// Read at target construction so an early cached target already has its checks.
Iterable<ExecutableElement> executableCovarianceContributors(
  ExecutableElement member,
) {
  member = member.baseElement;
  final owner = member.enclosingElement;
  if (member is! internal.ElementImpl ||
      owner is! internal.InterfaceElementImpl) {
    throw UnsupportedError('Analyzer covariance contributors unavailable.');
  }
  return [
    member,
    ...?owner.inheritanceManager.getOverridden(
      owner,
      internal.Name(member.library.uri, member.lookupName!),
    ),
  ];
}

/// Combines parameter flags by positional index or named identity.
/// The default flags are declaration covariance; callers may supply class flags.
/// The result is mutable, including when the selected member has no parameters.
Set<int> combinedCovariance(
  ExecutableElement selected,
  Iterable<ExecutableElement> contributors, {
  Set<int> Function(ExecutableElement)? flags,
}) {
  final parameters = selected.formalParameters;
  if (parameters.isEmpty) return <int>{};
  final positionalCount = parameters.where((p) => p.isPositional).length;
  final namedSlots = {
    for (final (i, p) in parameters.indexed)
      if (p.isNamed) p.name!: i,
  };
  final result = <int>{};
  for (final member in contributors) {
    final slots = flags?.call(member);
    if (slots != null && slots.isEmpty) continue;
    for (final (i, p) in member.formalParameters.indexed) {
      if (!(slots?.contains(i) ?? p.isCovariant)) continue;
      final slot = p.isNamed
          ? namedSlots[p.name]
          : (i < positionalCount ? i : null);
      if (slot != null) result.add(slot);
    }
  }
  return result;
}

typedef ClassCovariance = ({Set<int> parameters, Set<int> bounds});

/// Compiler polarity checks in the original owner view, before specialization.
/// A fresh visitor is required for every query: early success can leave its
/// internal variance changed. No IR types, binders, or defaults are constructed.
ClassCovariance executableClassCovariance(ExecutableElement member) {
  member = member.baseElement;
  final owner = member.enclosingElement;
  if (owner is! InterfaceElement || owner.typeParameters.isEmpty) {
    return (parameters: const {}, bounds: const {});
  }
  bool needsCheck(DartType? type) =>
      type?.accept(
        internal.NonCovariantTypeParameterPositionVisitor(
          owner.typeParameters,
          initialVariance: .contravariant,
        ),
      ) ??
      false;
  return (
    parameters: {
      for (final (i, p) in member.formalParameters.indexed)
        if (needsCheck(p.type)) i,
    },
    bounds: {
      for (final (i, p) in member.typeParameters.indexed)
        if (needsCheck(p.bound)) i,
    },
  );
}

/// Runtime defaults of the flattened extension/method binder group.
/// CFE computes these together before creating the tear-off closure. Analyzer
/// keeps separate groups, so transport its method defaults through the already
/// computed extension defaults, using its variance-aware substitution visitor.
List<DartType> extensionTearOffDefaults(ExecutableElement member) {
  member = member.baseElement;
  if (member.typeParameters.isEmpty) return const [];
  final owner = member.enclosingElement as TypeParameterizedElement;
  DartType requiredDefault(TypeParameterElement parameter) =>
      typeParameterDefault(parameter) ??
      (throw UnsupportedError(
        'Analyzer extension default metadata unavailable.',
      ));
  final substitution = _ExtensionDefaults({
    for (final parameter in owner.typeParameters)
      parameter: requiredDefault(parameter),
  });
  return [
    for (final parameter in member.typeParameters)
      substitution.substituteType(requiredDefault(parameter)),
  ];
}

final class _ExtensionDefaults(final Map<TypeParameterElement, DartType> upper)
    extends internal.Substitution {
  @override
  DartType? getSubstitute(TypeParameterElement parameter, bool upperBound) =>
      !upper.containsKey(parameter)
      ? null
      : upperBound
      ? upper[parameter]
      : internal.NeverTypeImpl.instance;
}

/// Exact transported defaults for the selected executable's own binder group.
List<DartType?> executableTypeParameterDefaults(
  ExecutableElement executable,
) => [
  for (final (i, parameter) in executable.typeParameters.indexed)
    typeParameterDefault(parameter) ??
        (executable is internal.SubstitutedExecutableElementImpl &&
                typeParameterDefault(
                      executable.baseElement.typeParameters[i],
                    ) !=
                    null
            ? executable.substitution.substituteType(
                typeParameterDefault(executable.baseElement.typeParameters[i])!,
              )
            : null),
];

/// Reads the compiler-computed default, absent on some fresh structural binders.
DartType? typeParameterDefault(TypeParameterElement parameter) {
  if (parameter is! internal.TypeParameterElementImpl) {
    throw UnsupportedError(
      'Analyzer type parameter default metadata unavailable.',
    );
  }
  return parameter.defaultType;
}

/// Reads the exact arguments retained by constant function instantiation.
List<DartType>? constantFunctionArguments(DartObject value) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState) {
    throw UnsupportedError('Analyzer function constant metadata unavailable.');
  }
  return (value.state as internal.FunctionState).typeArguments;
}

/// Tests the alias identity without inspecting or reconstructing private state.
bool constantFunctionUsesAlias(DartObject value, TypeAliasElement alias) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState ||
      alias is! internal.TypeAliasElementImpl) {
    throw UnsupportedError('Analyzer constructor alias metadata unavailable.');
  }
  final state = value.state as internal.FunctionState;
  return state
          .isIdentical(
            state.element.library.typeSystem,
            internal.FunctionState(
              state.element,
              typeArguments: state.typeArguments,
              viaTypeAlias: alias,
            ),
          )
          .value ==
      true;
}

/// Whether a function constant retains a distinct constructor alias identity.
bool constantFunctionHasAlias(DartObject value) {
  if (value is! internal.DartObjectImpl ||
      value.state is! internal.FunctionState) {
    throw UnsupportedError('Analyzer constructor alias metadata unavailable.');
  }
  final state = value.state as internal.FunctionState;
  return state
          .isIdentical(
            state.element.library.typeSystem,
            internal.FunctionState(
              state.element,
              typeArguments: state.typeArguments,
            ),
          )
          .value ==
      false;
}

/// The contextual type applied to a declaration/assignment's RHS expression.
/// For-in patterns do not apply a context schema to each iterated value.
DartType? patternContextType(ast.DartPattern pattern) {
  final schema = switch (pattern.parent) {
    internal.PatternAssignmentImpl(:final patternTypeSchema) ||
    internal.PatternVariableDeclarationImpl(
      :final patternTypeSchema,
    ) => patternTypeSchema,
    _ => null,
  };
  return schema == null
      ? null
      : internal.TypeSchemaEliminationVisitor.run(
          topType: internal.DynamicTypeImpl.instance,
          bottomType: internal.NeverTypeImpl.instance,
          isLeastClosure: false,
          schema: schema,
        );
}

/// Reads the analyzer's separate storage layer for inherited instance fields.
DartObject? constantSuperclass(DartObject value) =>
    value.getField(internal.GenericState.SUPERCLASS_FIELD);

/// Unfolded constructor syntax, including assertions and super/redirect calls.
/// A missing adapter result must not be treated as an empty initializer list.
List<ast.ConstructorInitializer>? constantConstructorInitializers(
  ConstructorElement constructor,
) => constructor.baseElement is internal.ConstructorElementImpl
    ? (constructor.baseElement as internal.ConstructorElementImpl)
          .constantInitializers
    : null;
