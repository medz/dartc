import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import '../analyzer_metadata.dart';
import '../constant_evaluation.dart';
import 'ffi.dart';
import 'intrinsic.dart';

/// An extension's static IR entry, distinct from its source callable signature.
final class ExtensionExecutable(
  final ExecutableElement declaration,
  final Element extension,
  final FunctionTarget target,
  final List<TypeParameterType> extensionParameters,
  final FunctionType sourceSignature,
  final ValueType? receiverType,
) {
  int get sourceParameterOffset => receiverType == null ? 0 : 1;
}

/// Call-site instantiation, never cached by declaration alone.
final class ExtensionApplication(
  final ExtensionExecutable executable,
  final List<ValueType> typeArguments,
  final ValueType receiverType,
);

/// Maps analyzer declarations and formal parameters to their IR identities.
final class Bindings({
  final bool enableAssertions = false,
  ConstantEvaluation? constants,
}) {
  final ConstantEvaluation constants = constants ?? ConstantEvaluation();
  final _targets = <ExecutableElement, FunctionTarget>{};

  /// SDK functions with Dart bodies, discovered while binding direct references.
  final sdkFunctions = <ExecutableElement>[];

  /// Resolved external declarations whose behavior is supplied by the compiler.
  final intrinsics = <IrFunction>[];

  /// Constructed SDK classes, with superclasses preceding their children.
  final sdkClasses = <InterfaceElement>[];

  /// Includes a constructed SDK class and the bodies it inherits.
  void requireSdkClass(InterfaceElement element) {
    if (element.library.typeProvider.objectElement == element ||
        sdkClasses.contains(element)) {
      return;
    }
    if (element.supertype case final parent?) requireSdkClass(parent.element);
    sdkClasses.add(element);
  }

  /// Includes the actual SDK error used by failed late binding operations.
  void requireLateError(
    LibraryElement library,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final core = library.typeProvider.objectElement.library;
    final error = core.fragments
        .expand((fragment) => fragment.importedLibraries)
        .where((library) => library.uri == Uri.parse('dart:_internal'))
        .firstOrNull
        ?.getClass('LateError');
    if (error == null || error.unnamedConstructor == null) {
      unsupported(unit, site, 'SDK late initialization error unavailable');
    }
    requireSdkClass(error);
  }

  final _typeEnvironments =
      <FunctionTarget, Map<TypeParameterType, ValueType>>{};
  final _extensions = <ExecutableElement, ExtensionExecutable>{};
  final _deferredImports =
      <PrefixElement, ({DeferredImport reference, IrFunction loader})>{};

  /// The implicit `loadLibrary` functions referenced by this batch.
  Iterable<IrFunction> get libraryLoaders =>
      _deferredImports.values.map((entry) => entry.loader);

  /// Resolves a deferred namespace from a static receiver or named type.
  ({DeferredImport reference, IrFunction loader})? deferredImport(
    ast.AstNode? source,
  ) {
    final prefix = switch (source) {
      ast.SimpleIdentifier(:final element) => element,
      ast.PrefixedIdentifier(prefix: ast.SimpleIdentifier(:final element)) =>
        element,
      ast.NamedType(:final importPrefix) => importPrefix?.element,
      _ => null,
    };
    if (prefix is! PrefixElement || !prefix.firstFragment.isDeferred) {
      return null;
    }
    return _deferredImports.putIfAbsent(prefix, () {
      final reference = DeferredImport(
        prefix.firstFragment.enclosingFragment!.source.uri,
        prefix.name!,
        prefix.imports.single.importedLibrary!.uri,
      );
      final operation = LoadLibrary(reference);
      final target = FunctionTarget(
        prefix.library.uri,
        '${reference.unit}:loadLibrary:${reference.prefix}',
        operation.type,
        [],
      );
      final entry = Block([]);
      entry.finish(Return(entry.emit(operation)));
      return (reference: reference, loader: IrFunction(target, [entry]));
    });
  }

  /// Substitutions from source binders into this instantiated lexical body.
  Map<TypeParameterType, ValueType> typeEnvironment(FunctionTarget target) {
    if (_typeEnvironments[target] case final environment?) return environment;
    if (target.enclosing case final enclosing?) {
      return typeEnvironment(enclosing);
    }
    final owner = target.owner;
    return _applicationOwners.containsKey(owner)
        ? owner!.interfaces.single.typeEnvironment
        : const {};
  }

  final _classes = <InterfaceElement, ClassType>{};
  final _mixinApplications = <InterfaceElement, List<IrClass>>{};
  final _mixinInitializers = <IrFunction>[];
  final _applicationOwners =
      <ClassType, ({InterfaceElement owner, InterfaceElement source})>{};
  final _superImplementations =
      <ClassType, Map<MemberSelector, FunctionTarget>>{};
  final _classElements = <ClassType, InterfaceElement>{};
  final _parameters = <TypeParameterElement, TypeParameterType>{};
  final _boundParameters = <TypeParameterElement>{};
  final _fields = <(FieldElement, ClassType), InstanceField>{};
  final _globals = <VariableElement, GlobalVariable>{};
  final _defaults = <FunctionTarget, Map<int, Constant>>{};
  final _constants = <VariableElement, Constant>{};

  final _modeledClasses =
      <InterfaceElement, (ResolvedUnitResult, ast.AstNode)>{};
  final _implementationPlans =
      <InterfaceElement, Map<MemberSelector, FunctionTarget>>{};
  // Eligibility for later nSM replacement, including direct wrappers over nSM.
  final _syntheticTargets = <FunctionTarget>{};
  final _superWrappers =
      <FunctionTarget, ({FunctionTarget target, FunctionType declaration})>{};
  // Keep declaration covariance separate from implicit class-variable checks.
  // CFE compares these independently when deciding to emit a super wrapper.
  final _declarationCovariance = <FunctionTarget, Set<int>>{};
  final _classCovariance = <FunctionTarget, Set<int>>{};
  final _boundCovariance = <FunctionTarget, Set<int>>{};
  final _memberClassCovariance = <ExecutableElement, ClassCovariance>{};
  final _newForwarders = <InterfaceElement, List<FunctionTarget>>{};
  final _unsupportedForwarders = <InterfaceElement, Set<MemberSelector>>{};
  final _planningClasses = <InterfaceElement>{};

  /// Records source ownership before any body (including super calls) is lowered.
  void registerClass(
    InterfaceElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    _modeledClasses[element] = (unit, site);
  }

  MemberSelector _memberSelector(
    ExecutableElement member, [
    Uri? privateLibrary,
  ]) => (
    kind: switch (member) {
      GetterElement() => FunctionKind.getter,
      SetterElement() => FunctionKind.setter,
      _ => FunctionKind.method,
    },
    name:
        member is MethodElement &&
            member.name == '-' &&
            member.formalParameters.isEmpty
        ? 'unary-'
        : member.name!,
    privateLibrary: member.name!.startsWith('_')
        ? privateLibrary ?? member.library.uri
        : null,
  );

  FunctionTarget? superWrapperTarget(FunctionTarget target) =>
      _superWrappers[target]?.target;

  /// Stable targets emitted only by the destination class's lowering pass.
  List<FunctionTarget> forwarders(InterfaceElement element) {
    _planImplementations(element);
    return _newForwarders[element] ?? const [];
  }

  Set<MemberSelector> unsupportedForwarders(InterfaceElement element) {
    _planImplementations(element);
    return _unsupportedForwarders[element] ?? const {};
  }

  Map<MemberSelector, FunctionTarget> _planImplementations(
    InterfaceElement element,
  ) {
    if (_implementationPlans[element] case final previous?) return previous;
    final source = _modeledClasses[element];
    if (source == null) return const {};
    final (unit, site) = source;
    if (!_planningClasses.add(element)) {
      unsupported(unit, site, 'cyclic forwarder implementation plan');
    }
    final owner = classType(element, unit, site);
    final parent = element.supertype?.element;
    final effective = <MemberSelector, FunctionTarget>{
      if (parent != null) ..._planImplementations(parent),
    };
    for (final application in _mixinApplications[element] ?? <IrClass>[]) {
      _superImplementations[application.type] = Map.of(effective);
      final mixin = _applicationOwners[application.type]!.source;
      for (final member in <ExecutableElement>[
        ...mixin.methods,
        ...mixin.getters,
        ...mixin.setters,
      ]) {
        if (member.isStatic || member.isAbstract) continue;
        final selected = application.members[_memberSelector(member)]!;
        effective[selected.selector] = selected;
      }
    }
    _superImplementations[owner] = Map.of(effective);
    // With no own abstract declaration, interface, or mixin, this class adds
    // no new covariance provenance; its superclass has already been checked.
    var checkCovariance =
        element.interfaces.isNotEmpty || element.mixins.isNotEmpty;
    for (final member in <ExecutableElement>[
      ...element.methods,
      ...element.getters,
      ...element.setters,
    ]) {
      if (!member.isStatic && member.isAbstract) checkCovariance = true;
      if (!member.isStatic && !member.isAbstract) {
        final implementation = target(member, unit, site);
        effective[implementation.selector] = implementation;
      }
    }
    final emitted = <FunctionTarget>[];
    final unsupportedSelectors = <MemberSelector>{};
    final candidates = noSuchMethodForwarderCandidates(
      element,
      checkCovariance: !checkCovariance
          ? null
          : (member, library, contributors) {
              _planCovarianceWrapper(
                element,
                member,
                library,
                contributors,
                effective,
                emitted,
                unit,
                site,
              );
            },
    );
    for (final candidate in candidates) {
      final member = candidate.member;
      final selector = _memberSelector(member, candidate.privateLibrary);
      final inherited = effective[selector];
      // Analyzer propagates forwarder markers across real concrete overrides.
      if (inherited != null &&
          !_syntheticTargets.contains(inherited) &&
          !candidate.overridesConcrete) {
        continue;
      }
      final unmodeledParent =
          parent != null &&
          !_modeledClasses.containsKey(parent) &&
          !element.supertype!.isDartCoreObject;
      if (inherited == null) {
        if (candidate.overridesConcrete) {
          unsupported(
            unit,
            site,
            'inherited private noSuchMethod forwarder ${member.name}',
          );
        }
        // A guard does not consume the unsupported signature or its constants.
        // A known inherited target requires replacement comparison first.
        if (unmodeledParent) {
          unsupportedSelectors.add(selector);
          continue;
        }
      }
      final templates = executableTypeParameterDefaults(member);
      if (templates.any((type) => type == null)) {
        if (inherited != null) {
          unsupported(
            unit,
            site,
            'inherited synthetic generic-default metadata ${member.name}',
          );
        }
        unsupportedSelectors.add(selector);
        continue;
      }
      final sourceClassFlags = combinedCovariance(
        member,
        candidate.covarianceContributors,
        flags: (contributor) => _classCovarianceFor(contributor).parameters,
      );
      final replacement = _forwarderTarget(
        element,
        member,
        templates,
        unit,
        site,
        privateLibrary: candidate.privateLibrary,
        effectiveCovariance: {
          ...candidate.additionalCovariance,
          if (candidate.overridesConcrete && inherited != null)
            ..._transportCovariance(
              inherited,
              member,
              inherited.covariantParameters,
            ),
        },
        inheritedClassCovariance: {
          ...sourceClassFlags,
          if (inherited != null)
            ..._transportCovariance(
              inherited,
              member,
              _classCovariance[inherited] ?? const {},
            ),
        },
      );
      final declarationFlags = {
        ...candidate.additionalCovariance,
        for (final (i, p) in member.formalParameters.indexed)
          if (p.isCovariant) i,
        if (candidate.overridesConcrete && inherited != null)
          ..._transportCovariance(
            inherited,
            member,
            _declarationCovariance[inherited] ?? const {},
          ),
      };
      if (declarationFlags.isNotEmpty) {
        _declarationCovariance[replacement] = declarationFlags;
      }
      final boundFlags = {
        ...?_boundCovariance[inherited],
        for (final contributor in candidate.covarianceContributors)
          ..._classCovarianceFor(contributor).bounds,
      };
      if (boundFlags.isNotEmpty) _boundCovariance[replacement] = boundFlags;
      if (inherited != null) {
        final inheritedSignature =
            _superWrappers[inherited]?.declaration.substitute(
              inherited.environmentFor(owner),
            ) ??
            inherited.signatureFor(owner);
        if (inheritedSignature == replacement.signature) {
          continue;
        }
      }
      if (unmodeledParent) {
        unsupportedSelectors.add(selector);
        continue;
      }
      _syntheticTargets.add(replacement);
      emitted.add(replacement);
      effective[selector] = replacement;
    }
    _newForwarders[element] = emitted;
    _unsupportedForwarders[element] = unsupportedSelectors;
    _planningClasses.remove(element);
    return _implementationPlans[element] = effective;
  }

  void _planCovarianceWrapper(
    InterfaceElement element,
    ExecutableElement member,
    Uri? privateLibrary,
    Iterable<ExecutableElement> contributors,
    Map<MemberSelector, FunctionTarget> effective,
    List<FunctionTarget> emitted,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (member.formalParameters.isEmpty && member.typeParameters.isEmpty) {
      return;
    }
    final inherited = effective[_memberSelector(member, privateLibrary)];
    if (inherited == null) return;
    final isAbstract = element is ClassElement && element.isAbstract;
    // Concrete nSM/private candidates use the existing replacement branch.
    // Even a real foreign-private body uses CFE's nSM-target equality branch:
    // a compatible body is reused despite additional interface covariance.
    if (!isAbstract &&
        (_syntheticTargets.contains(inherited) ||
            privateLibrary != null && privateLibrary != element.library.uri)) {
      return;
    }
    // An insufficient super parameter count cannot support a concrete wrapper.
    final parameters = member.formalParameters;
    if (inherited.signature.positionalCount <
            parameters.where((p) => p.isPositional).length ||
        inherited.signature.named.length <
            parameters.where((p) => p.isNamed).length) {
      return;
    }
    final inheritedCovariance = _transportCovariance(
      inherited,
      member,
      _declarationCovariance[inherited] ?? const {},
    );
    final inheritedClassCovariance = _transportCovariance(
      inherited,
      member,
      _classCovariance[inherited] ?? const {},
    );
    final combinedClassCovariance = combinedCovariance(
      member,
      contributors,
      flags: (contributor) => _classCovarianceFor(contributor).parameters,
    );
    final combinedBounds = {
      for (final contributor in contributors)
        ..._classCovarianceFor(contributor).bounds,
    };
    final declarationFlags = combinedCovariance(member, contributors);
    if (!inheritedCovariance.containsAll(declarationFlags) ||
        !inheritedClassCovariance.containsAll(combinedClassCovariance) ||
        !(_boundCovariance[inherited] ?? const <int>{}).containsAll(
          combinedBounds,
        )) {
      final owner = classType(element, unit, site);
      final templates = executableTypeParameterDefaults(member);
      if (templates.every((type) => type != null)) {
        final wrapper = _forwarderTarget(
          element,
          member,
          templates,
          unit,
          site,
          privateLibrary: privateLibrary,
          inheritedEntry: inherited,
          effectiveCovariance: {...inheritedCovariance, ...declarationFlags},
          inheritedClassCovariance: {
            ...inheritedClassCovariance,
            ...combinedClassCovariance,
          },
        );
        _boundCovariance[wrapper] = {
          ...?_boundCovariance[inherited],
          ...combinedBounds,
        };
        _superWrappers[wrapper] = (
          target: inherited.signatureFor(owner) == wrapper.signature
              ? _superWrappers[inherited]?.target ?? inherited
              : inherited,
          declaration: valueType(member.type, unit, site) as FunctionType,
        );
        if (_syntheticTargets.contains(inherited)) {
          _syntheticTargets.add(wrapper);
        }
        effective[wrapper.selector] = wrapper;
        emitted.add(wrapper);
        return;
      }
      unsupported(
        unit,
        site,
        _syntheticTargets.contains(inherited)
            ? 'inherited noSuchMethod covariance transition ${member.name}'
            : 'inherited concrete covariance transition ${member.name}',
      );
    }
  }

  ClassCovariance _classCovarianceFor(ExecutableElement member) {
    member = member.baseElement;
    if (_memberClassCovariance[member] case final previous?) return previous;
    final owner = member.enclosingElement;
    if (owner is! InterfaceElement) {
      return (parameters: const {}, bounds: const {});
    }
    final hasInherited =
        owner.interfaces.isNotEmpty ||
        owner.mixins.isNotEmpty ||
        (owner.supertype != null && !owner.supertype!.isDartCoreObject);
    if (owner.typeParameters.isEmpty && !hasInherited) {
      return (parameters: const {}, bounds: const {});
    }
    return _memberClassCovariance.putIfAbsent(member, () {
      final own = executableClassCovariance(member);
      if (!hasInherited) return own;
      // A checked inheritance graph is acyclic. Do not recurse into the own
      // declaration included by the adapter; effective flags survive real
      // overrides whose syntactic types no longer contain owner variables.
      final overridden = executableCovarianceContributors(member)
          .where((e) => e.baseElement != member)
          .toList();
      if (overridden.isEmpty) return own;
      return (
        parameters: {
          ...own.parameters,
          ...combinedCovariance(
            member,
            overridden,
            flags: (e) => _classCovarianceFor(e).parameters,
          ),
        },
        bounds: {
          ...own.bounds,
          for (final e in overridden) ..._classCovarianceFor(e).bounds,
        },
      );
    });
  }

  // FunctionType equality ignores named declaration order, unlike entry slots.
  // Transfer inherited checks by named identity and only positional index.
  Set<int> _transportCovariance(
    FunctionTarget inherited,
    ExecutableElement selected,
    Set<int> slots,
  ) {
    if (slots.isEmpty) return const {};
    final oldNames = {
      for (final entry in inherited.signature.named.entries)
        entry.value.slot: entry.key,
    };
    final newNames = {
      for (final (i, parameter) in selected.formalParameters.indexed)
        if (parameter.isNamed) parameter.name!: i,
    };
    final positionalCount = selected.formalParameters
        .where((p) => p.isPositional)
        .length;
    final result = <int>{};
    for (final slot in slots) {
      final name = oldNames[slot];
      if (name != null) {
        final destination = newNames[name];
        if (destination != null) result.add(destination);
      } else if (slot < positionalCount) {
        result.add(slot);
      }
    }
    return result;
  }

  FunctionTarget _forwarderTarget(
    InterfaceElement destination,
    ExecutableElement selected,
    List<dart.DartType?> templates,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    Uri? privateLibrary,
    FunctionTarget? inheritedEntry,
    Set<int> effectiveCovariance = const {},
    Set<int> inheritedClassCovariance = const {},
  }) {
    final owner = classType(destination, unit, site);
    final parameters = selected.formalParameters;
    final binders = bindTypeParameters(
      selected.typeParameters,
      unit,
      site,
      defaultTemplates: templates,
    );
    final signature =
        inheritedEntry?.signatureFor(owner).rebind({}) ??
        FunctionType(
          valueType(selected.returnType, unit, site),
          parameters.map((p) => valueType(p.type, unit, site)),
          typeParameters: binders,
          optionalPositional: parameters
              .where((p) => p.isOptionalPositional)
              .length,
          namedParameters: {
            for (final p in parameters)
              if (p.isNamed) p.name!: p.isRequiredNamed,
          },
        );
    int slot(int i) =>
        parameters[i].isNamed ? signature.named[parameters[i].name]!.slot : i;
    final declarationFlags = {
      ...effectiveCovariance.map(slot),
      for (final (i, p) in parameters.indexed)
        if (p.isCovariant) slot(i),
    };
    final classFlags = inheritedClassCovariance.map(slot).toSet();
    final result = FunctionTarget(
      destination.library.uri,
      selected.name!,
      signature.result,
      signature.parameters,
      owner: owner,
      kind: _memberSelector(selected).kind,
      privateSelectorLibrary: privateLibrary,
      typeParameters: signature.typeParameters,
      optionalPositional: signature.optionalPositional,
      namedParameters: signature.namedParameters,
      covariantParameters: {...classFlags, ...declarationFlags},
    );
    // These checks survive specialization even when the destination's own
    // parameter types no longer contain class variables. Keep their provenance
    // through further signature replacements as well as unchanged inheritance.
    final ownerParameters = owner.typeParameters.isEmpty
        ? const <TypeParameterType>{}
        : owner.typeParameters.toSet();
    _classCovariance[result] = {
      ...classFlags,
      if (ownerParameters.isNotEmpty)
        for (final (i, type) in result.signature.parameters.indexed)
          if (type.requiresCovariantCheck(ownerParameters)) i,
    };
    _declarationCovariance[result] = declarationFlags;
    _defaults[result] = {
      if (inheritedEntry != null) ...defaults(inheritedEntry),
      for (final (i, p) in parameters.indexed)
        if (p.isOptional) slot(i): constantOf(p.baseElement, unit, site),
    };
    return result;
  }

  /// Binds the genuine SDK operation used by an ordinary forwarding body.
  FunctionTarget noSuchMethodBodyTarget(
    InterfaceElement destination,
    FunctionTarget forwarder,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final object = destination.library.typeProvider.objectElement;
    final foreignPrivate =
        forwarder.selector.privateLibrary != null &&
        forwarder.selector.privateLibrary != forwarder.library;
    return target(
      foreignPrivate
          ? object.library
                .getClass('NoSuchMethodError')!
                .getNamedConstructor('withInvocation')!
          : object.getMethod('noSuchMethod')!,
      unit,
      site,
    );
  }

  /// Resolves super against the lexical superclass, not an abstract interface
  /// declaration returned by analyzer or the runtime receiver's class.
  FunctionTarget superTarget(
    ValueType lexicalReceiver,
    ExecutableElement member,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final owner = lexicalReceiver.nonNullable;
    if (owner is ClassType) {
      final element =
          _applicationOwners[owner.declaration]?.owner ??
          _classElements[owner.declaration];
      if (element != null) {
        _planImplementations(element);
        final actual =
            _superImplementations[owner.declaration]?[_memberSelector(member)];
        if (actual != null) return actual;
      }
    }
    return target(member, unit, site);
  }

  /// Returns the shared signature and constructor binding for [element].
  FunctionTarget target(
    ExecutableElement element,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    Set<ConstructorElement>? redirects,
    FunctionTarget? enclosing,
    int? sourceOffset,
    Iterable<ValueType> captures = const [],
  }) {
    if (isExtensionOwner(element.enclosingElement)) {
      return extensionExecutable(element, unit, site)!.target;
    }
    element = element.baseElement;
    final previous = enclosing == null ? _targets[element] : null;
    if (previous != null) return previous;
    final parameters = element.formalParameters;
    final container = element.enclosingElement;
    final owner = container is InterfaceElement
        ? classType(container, unit, site)
        : null;
    final kind = switch (element) {
      ConstructorElement(:final isFactory) =>
        isFactory ? FunctionKind.factory : FunctionKind.initializer,
      LocalFunctionElement() => FunctionKind.closure,
      GetterElement(isStatic: false) => FunctionKind.getter,
      GetterElement() => FunctionKind.staticGetter,
      SetterElement(isStatic: false) => FunctionKind.setter,
      SetterElement() => FunctionKind.staticSetter,
      MethodElement(isStatic: false) => FunctionKind.method,
      _ => FunctionKind.function,
    };
    final typeParameters = bindTypeParameters(
      element.typeParameters,
      unit,
      site,
    );
    final environment = enclosing == null
        ? const <TypeParameterType, ValueType>{}
        : typeEnvironment(enclosing);
    final rebound = environment.isEmpty
        ? null
        : (valueType(element.type, unit, site) as FunctionType).rebind(
            environment,
          );
    FunctionTarget? destination;
    ClassType? redirectOwnerType;
    if (element case final ConstructorElement ctor
        when ctor.isFactory && ctor.redirectedConstructor != null) {
      redirectOwnerType = valueType(
        ctor.redirectedConstructor!.returnType,
        unit,
        site,
      ) as ClassType;
      final path = redirects ?? <ConstructorElement>{};
      if (!path.add(ctor)) unsupported(unit, site, 'cyclic factory redirect');
      destination = target(
        ctor.redirectedConstructor!,
        unit,
        site,
        redirects: path,
      );
    }
    final needsCovariance =
        kind.isVirtual &&
        (parameters.isNotEmpty || element.typeParameters.isNotEmpty);
    final contributors = needsCovariance
        ? executableCovarianceContributors(element)
        : const <ExecutableElement>[];
    final declarationFlags = needsCovariance
        ? combinedCovariance(element, contributors)
        : const <int>{};
    final classCovariance = needsCovariance
        ? _classCovarianceFor(element)
        : (parameters: const <int>{}, bounds: const <int>{});
    final classFlags = classCovariance.parameters;
    final function = FunctionTarget(
      enclosing?.library ?? element.library.uri,
      element.name ?? '<anonymous>',
      kind == .initializer
          ? .voidType
          : rebound?.result ?? valueType(element.returnType, unit, site),
      rebound?.parameters ??
          parameters.map((p) => valueType(p.type, unit, site)),
      owner: owner,
      typeParameters: rebound?.typeParameters ?? typeParameters,
      kind: kind,
      redirect: destination,
      redirectOwnerType: redirectOwnerType,
      enclosing: enclosing,
      sourceOffset: sourceOffset,
      captures: captures,
      covariantParameters: {...declarationFlags, ...classFlags},
      isAbstract:
          kind.isVirtual && (element.isAbstract || container is MixinElement),
      optionalPositional: parameters
          .where((p) => p.isOptionalPositional)
          .length,
      namedParameters: {
        for (final p in parameters)
          if (p.isNamed) p.name!: p.isRequiredNamed,
      },
    );
    if (rebound != null) {
      _typeEnvironments[function] = {
        ...environment,
        for (final (i, parameter) in typeParameters.indexed)
          parameter: rebound.typeParameters[i],
      };
    }
    if (declarationFlags.isNotEmpty) {
      _declarationCovariance[function] = declarationFlags;
    }
    if (classFlags.isNotEmpty) _classCovariance[function] = classFlags;
    if (classCovariance.bounds.isNotEmpty) {
      _boundCovariance[function] = classCovariance.bounds;
    }
    if (enclosing == null) {
      _targets[element] = function;
      if (element.isExternal) {
        if (intrinsicBody(element, function) case final body?) {
          intrinsics.add(body);
        }
      }
      if (element is ConstructorElement &&
          !element.isFactory &&
          redirects == null &&
          element.library.isInSdk &&
          !element.isExternal) {
        requireSdkClass(element.enclosingElement);
      }
      if (element.library.isInSdk &&
          element.isStatic &&
          !element.isExternal &&
          !element.isAbstract &&
          (element is TopLevelFunctionElement || element is MethodElement)) {
        sdkFunctions.add(element);
      }
    }
    if (destination == null && parameters.any((p) => p.isOptional)) {
      _defaults[function] = {
        for (final (i, p) in parameters.indexed)
          if (p.isOptional) i: constantOf(p, unit, site),
      };
    }
    return function;
  }

  /// Returns an extension member's declaration ABI, or null for other owners.
  ExtensionExecutable? extensionExecutable(
    ExecutableElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    element = element.baseElement;
    final owner = element.enclosingElement;
    if (!isExtensionOwner(owner)) return null;
    final constructor = element is ConstructorElement;
    if (_extensions[element] case final previous?) return previous;
    final extensionElements = element.isStatic && !constructor
        ? const <TypeParameterElement>[]
        : owner is ExtensionElement
        ? owner.typeParameters
        : (owner as ExtensionTypeElement).typeParameters;
    // Both groups must exist before converting dependent bounds/defaults.
    registerTypeParameters(extensionElements);
    registerTypeParameters(element.typeParameters);
    final extensionParameters = bindTypeParameters(
      extensionElements,
      unit,
      site,
    );
    bindTypeParameters(
      element.typeParameters,
      unit,
      site,
      defaultTemplates: executableTypeParameterDefaults(element),
    );
    final source = _functionType(
      element.type,
      unit,
      site,
      parameters: element.formalParameters,
    );
    final receiver = element.isStatic || constructor
        ? null
        : valueType(
            owner is ExtensionElement
                ? owner.extendedType
                : (owner as ExtensionTypeElement).thisType,
            unit,
            site,
          );
    final function = FunctionTarget(
      element.library.uri,
      _extensionName(owner!, element.name!, switch (element) {
        ConstructorElement() => 'constructor',
        GetterElement() => 'get',
        SetterElement() => 'set',
        MethodElement(name: '-', formalParameters: []) => 'unary',
        _ => 'method',
      }),
      source.result,
      [?receiver, ...source.parameters],
      kind: !element.isStatic
          ? .function
          : switch (element) {
              GetterElement() => .staticGetter,
              SetterElement() => .staticSetter,
              _ => .function,
            },
      typeParameters: [...extensionParameters, ...source.typeParameters],
      optionalPositional: source.optionalPositional,
      namedParameters: source.namedParameters,
    );
    // Default constants may refer to this executable (or a mutually recursive
    // constructor), so publish its identity before evaluating defaults.
    _targets[element] = function;
    final executable = _extensions[element] = ExtensionExecutable(
      element,
      owner,
      function,
      extensionParameters,
      source,
      receiver,
    );
    if (element case ConstructorElement(redirectedConstructor: final redirect?)
        when element.isFactory) {
      final destination = target(redirect, unit, site);
      _defaults[function] = {
        for (final (i, parameter) in element.formalParameters.indexed)
          if (parameter.isOptional)
            i:
                defaults(destination)[parameter.isNamed
                    ? destination.signature.named[parameter.name]!.slot
                    : i]!,
      };
    } else {
      _defaults[function] = {
        for (final (i, parameter) in element.formalParameters.indexed)
          if (parameter.isOptional)
            i + (receiver == null ? 0 : 1): constantOf(parameter, unit, site),
      };
    }
    return executable;
  }

  String _extensionName(Element owner, String name, String operation) {
    final identity =
        owner.name ??
        '${(owner as ExtensionElement).firstFragment.libraryFragment.source.uri}@${owner.firstFragment.offset}';
    final kind = owner is ExtensionTypeElement ? 'extension-type' : 'extension';
    return '<$kind:$identity:$operation:$name>';
  }

  /// Defaults supplied by an executable declaration.
  Map<int, Constant> defaults(FunctionTarget target) =>
      _defaults[target] ?? const {};

  /// Binds evaluated arguments to their destination, including its declared defaults.
  List<Value> bind(FunctionTarget target, EvaluatedArguments args) => target
      .signature
      .bind(args.positional, args.named, (i) => _defaults[target]![i]!);

  /// The stored declarations lowered from this batch's source units.
  Iterable<GlobalVariable> get globals => _globals.values;

  /// Anonymous application layers with ordinary member targets.
  Iterable<IrClass> get mixinApplications =>
      _mixinApplications.values.expand((layers) => layers);

  Iterable<IrFunction> get mixinInitializers => _mixinInitializers;

  /// The same checked source is lowered against each actual application owner.
  Iterable<(IrClass, ResolvedUnitResult, ast.AstNode)>
  get mixinDeclarations sync* {
    for (final application in mixinApplications) {
      final (unit, source) =
          _modeledClasses[_applicationOwners[application.type]!.source]!;
      yield (application, unit, source);
    }
  }

  void replaceMixinApplication(IrClass application) {
    final layers =
        _mixinApplications[_applicationOwners[application.type]!.owner]!;
    final index = layers.indexWhere((layer) => layer.type == application.type);
    layers[index] = application;
  }

  /// Inserts ordinary delegating initializers for anonymous application layers.
  /// The source constructor supplies the selected name, signature and defaults.
  ({FunctionTarget target, ClassType ownerType}) initializerCall(
    ConstructorElement from,
    ConstructorElement to,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    var destination = target(to, unit, site);
    var ownerType = valueType(to.returnType, unit, site) as ClassType;
    final layers = from.enclosingElement == to.enclosingElement
        ? null
        : _mixinApplications[from.enclosingElement];
    for (var i = 0; i < (layers?.length ?? 0); i++) {
      final layer = layers![i];
      var initializer = layer.constructors[destination.name];
      if (initializer == null) {
        final signature = destination.signatureFor(ownerType);
        initializer = FunctionTarget(
          layer.type.library,
          destination.name,
          .voidType,
          signature.parameters,
          owner: layer.type,
          kind: .initializer,
          optionalPositional: signature.optionalPositional,
          namedParameters: signature.namedParameters,
        );
        _defaults[initializer] = defaults(destination);
        final entry = Block(initializer.parameterTypes);
        if (layer.constructors['<mixin-fields>'] case final fields?) {
          entry.emit(DirectCall(fields, [entry.parameters.first]));
        }
        if (destination.owner != ValueType.object) {
          entry.emit(
            DirectCall(destination, entry.parameters, ownerType: ownerType),
          );
        }
        entry.finish(const Return());
        _mixinInitializers.add(
          IrFunction(initializer, [entry], defaults: defaults(initializer)),
        );
        layers[i] = IrClass(
          layer.type,
          layer.fields,
          members: layer.members.values,
          constructors: [...layer.constructors.values, initializer],
        );
      }
      destination = initializer;
      ownerType = layer.type;
    }
    return (target: destination, ownerType: ownerType);
  }

  /// Binds a top-level or static declaration using its actual source initializer.
  GlobalVariable global(
    PropertyInducingElement element,
    ResolvedUnitResult unit,
    ast.VariableDeclaration declaration,
  ) => _globals.putIfAbsent(element.baseElement as VariableElement, () {
    final container = element.enclosingElement;
    final owner =
        container is InterfaceElement && container is! ExtensionTypeElement
        ? classType(container, unit, declaration)
        : null;
    final type = valueType(element.type, unit, declaration);
    final name = isExtensionOwner(container)
        ? _extensionName(container!, element.name!, 'field')
        : element.name!;
    return GlobalVariable(
      element.library.uri,
      name,
      type,
      owner: owner,
      isFinal: element.isFinal,
      isLate: element.isLate,
      initializer: declaration.initializer == null
          ? null
          : FunctionTarget(
              element.library.uri,
              '<initialize:$name>',
              type,
              const [],
              owner: owner,
            ),
    );
  });

  /// Returns the same slot for every use of this field declaration.
  InstanceField field(
    FieldElement element,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    ClassType? owner,
  }) {
    element = element.baseElement;
    owner ??= classType(
      element.enclosingElement as InterfaceElement,
      unit,
      site,
    );
    final fieldOwner = owner;
    return _fields.putIfAbsent((element, fieldOwner), () {
      final owner = fieldOwner;
      if (owner == CoreTypes.enumeration) {
        return switch (element.name) {
          'index' => CoreTypes.enumIndex,
          '_name' => CoreTypes.enumName,
          _ => unsupported(unit, site, 'Enum field ${element.name}'),
        };
      }
      if (owner == CoreTypes.mapEntry) {
        return element.name == 'key'
            ? CoreTypes.mapEntryKey
            : CoreTypes.mapEntryValue;
      }
      final type = valueType(element.type, unit, site).substitute(
        _applicationOwners.containsKey(owner)
            ? owner.interfaces.single.typeEnvironment
            : const {},
      );
      return InstanceField(
        owner,
        element.name!,
        type,
        isFinal: element.isFinal,
        isLate: element.isLate,
        initializer: element.isLate && element.hasInitializer
            ? FunctionTarget(
                owner.library,
                '<initialize:${element.name}>',
                type,
                const [],
                owner: owner,
                kind: .fieldInitializer,
              )
            : null,
      );
    });
  }

  /// Reads a resolved constant or optional parameter's default value.
  Constant constantOf(
    VariableElement variable,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) => _constants.putIfAbsent(variable, () {
    final value = constants.variable(variable, unit, site);
    if (value == null &&
        variable is FormalParameterElement &&
        variable.isOptional &&
        !variable.hasDefaultValue) {
      return const .nullValue();
    }
    return _constantValue(
      value,
      variable.library ?? unit.libraryElement,
      unit,
      site,
    );
  });

  /// Returns the IR operand required by a constant expression.
  Constant constantExpression(
    ResolvedUnitResult unit,
    ast.Expression expression,
  ) =>
      tryConstantExpression(unit, expression) ??
      unsupported(unit, expression, 'constant expression');

  /// Returns a checked constant when [expression] can be evaluated.
  Constant? tryConstantExpression(
    ResolvedUnitResult unit,
    ast.Expression expression,
  ) {
    final value = constants.expression(unit, expression);
    if (value == null) return null;
    return _constantValue(value, unit.libraryElement, unit, expression);
  }

  Constant _constantValue(
    DartObject? value,
    LibraryElement origin,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    Constant convert(DartObject? child) =>
        _constantValue(child, origin, unit, site);
    if (value != null) {
      if (value.toTypeValue() case final type?) {
        return TypeConstant(valueType(type, unit, site));
      }
      if (value.isNull) return const .nullValue();
      if (value.toIntValue() case final i?) return .integer(i);
      if (value.toBoolValue() case final b?) return .boolean(b);
      if (value.toDoubleValue() case final d?) return .floating(d);
      if (value.toStringValue() case final s?) return .string(s);
      if (value.toSymbolValue() case final name?) {
        // ConstantSafety has already rejected dependencies on private literals.
        // Analyzer does not retain their defining library in toSymbolValue().
        return ObjectConstant(CoreTypes.symbolStorage, {
          CoreTypes.symbolName: .string(name),
          CoreTypes.symbolPrivateLibrary: const .nullValue(),
        });
      }
      if (value.toFunctionValue() case final executable?) {
        final callable = target(executable, unit, site);
        final functionType = value.type! as dart.FunctionType;
        final arguments = constantFunctionArguments(value);
        if (executable is ConstructorElement) {
          final alias = _constantConstructorAlias(value, origin, unit, site);
          if (alias != null) {
            return constructorAliasConstant(
              alias,
              callable,
              unit,
              site,
              typeArguments: functionType.typeParameters.isEmpty
                  ? arguments!.map((t) => valueType(t, unit, site))
                  : null,
            );
          }
        }
        if (executable is ConstructorElement &&
            executable.enclosingElement is ExtensionTypeElement) {
          if (functionType.typeParameters.isEmpty &&
              arguments == null &&
              callable.typeParameters.isNotEmpty) {
            unsupported(unit, site, 'extension type constructor arguments');
          }
          return FunctionConstant(
            callable,
            typeArguments: functionType.typeParameters.isEmpty
                ? arguments?.map((type) => valueType(type, unit, site))
                : null,
          );
        }
        if (executable is ConstructorElement) {
          return FunctionConstant(
            callable,
            ownerType: functionType.typeParameters.isEmpty
                ? valueType(functionType.returnType, unit, site) as ClassType
                : null,
            constructorSignature: functionType.typeParameters.isNotEmpty
                ? valueType(functionType, unit, site) as FunctionType
                : null,
          );
        }
        return FunctionConstant(
          callable,
          typeArguments: arguments?.map((t) => valueType(t, unit, site)),
        );
      }
      if (value.toListValue() ?? value.toSetValue()?.toList()
          case final elements?) {
        return SequenceConstant(
          valueType(value.type!, unit, site) as ClassType,
          elements.map(convert),
        );
      }
      if (value.toMapValue() case final entries?) {
        return MapConstant(
          valueType(value.type!, unit, site) as ClassType,
          entries.entries.map(
            (entry) => (convert(entry.key), convert(entry.value)),
          ),
        );
      }
      if (value.toRecordValue() case final record?) {
        final type = valueType(value.type!, unit, site);
        if (type is RecordType) {
          return RecordConstant(type, [
            ...record.positional.map(convert),
            for (final name in type.slots.keys.skip(type.positionalCount))
              convert(record.named[name]),
          ]);
        }
      }
      if (value.type case final dart.InterfaceType objectType) {
        final fields = <InstanceField, Constant>{};
        DartObject? layer = value;
        while (layer != null) {
          final layerType = layer.type;
          if (layerType is! dart.InterfaceType) {
            unsupported(unit, site, 'constant instance storage');
          }
          final element = layerType.element;
          if (!isClassLike(element) || !layer.hasKnownValue) {
            unsupported(unit, site, 'constant ${layer.type}');
          }
          for (final declaration in element.fields) {
            if (declaration.isStatic ||
                declaration.isAbstract ||
                declaration.isOriginGetterSetter) {
              continue;
            }
            if (!declaration.isFinal ||
                declaration.isLate ||
                declaration.isExternal) {
              unsupported(
                unit,
                site,
                'constant field ${declaration.displayName}',
              );
            }
            fields[field(declaration, unit, site)] = convert(
              layer.getField(declaration.name!),
            );
          }
          if (element is EnumElement) {
            // Analyzer stores Enum's inherited slots directly in the enum value,
            // unlike the separate superclass layer used by ordinary instances.
            fields[CoreTypes.enumIndex] = convert(layer.getField('index'));
            fields[CoreTypes.enumName] = convert(layer.getField('_name'));
            break;
          }
          if (layerType.isDartCoreObject) break;
          final parent = constantSuperclass(layer);
          if (parent == null && element.supertype?.isDartCoreObject != true) {
            unsupported(unit, site, 'constant superclass storage');
          }
          layer = parent;
        }
        return ObjectConstant(
          valueType(objectType, unit, site) as ClassType,
          fields,
        );
      }
    }
    unsupported(unit, site, 'constant ${value?.type}');
  }

  /// Builds a constructor alias with its declared binders and target mapping.
  FunctionConstant constructorAliasConstant(
    TypeAliasElement alias,
    FunctionTarget target,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    Iterable<ValueType>? typeArguments,
  }) {
    final parameters = bindTypeParameters(alias.typeParameters, unit, site);
    final aliasedType = alias.aliasedType as dart.InterfaceType;
    final arguments = aliasedType.element is ExtensionTypeElement
        ? [for (final t in aliasedType.typeArguments) valueType(t, unit, site)]
        : null;
    final signature = arguments == null
        ? target.signatureFor(valueType(aliasedType, unit, site) as ClassType)
        : target.signature.instantiate(arguments);
    final view = FunctionType(
      signature.result,
      signature.parameters,
      typeParameters: parameters,
      optionalPositional: signature.optionalPositional,
      namedParameters: signature.namedParameters,
    );
    if (arguments != null &&
        arguments.length == parameters.length &&
        arguments.indexed.every((e) => e.$2 == parameters[e.$1]) &&
        view.accepts(target.signature) &&
        target.signature.accepts(view)) {
      return FunctionConstant(target, typeArguments: typeArguments);
    }
    return FunctionConstant(
      target,
      constructorSignature: view,
      constructorAlias: (alias.library.uri, alias.name!),
      constructorTypeArguments: arguments,
      typeArguments: typeArguments,
    );
  }

  TypeAliasElement? _constantConstructorAlias(
    DartObject value,
    LibraryElement library,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (constantFunctionUsesAlias(value, null)) return null;
    final pending = [library], visited = <LibraryElement>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      for (final alias in current.typeAliases) {
        if (constantFunctionUsesAlias(value, alias)) return alias;
      }
      pending.addAll(current.exportedLibraries);
      for (final fragment in current.fragments) {
        pending.addAll(fragment.importedLibraries);
      }
    }
    unsupported(unit, site, 'constant constructor alias provenance');
  }

  /// Maps the resolved Dart [type] to its IR type.
  ValueType valueType(
    dart.DartType type,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (type case dart.InterfaceType(element: ExtensionTypeElement())) {
      return valueType(type.extensionTypeErasure, unit, site);
    }
    final ValueType base = switch (type) {
      dart.DynamicType() => .dynamicType,
      dart.VoidType() => .voidType,
      dart.NeverType() => .never,
      final dart.TypeParameterType parameter => _parameterType(
        parameter,
        unit,
        site,
      ),
      final dart.FunctionType function => _functionType(function, unit, site),
      dart.RecordType(:final positionalFields, :final namedFields) =>
        RecordType(
          positionalFields.map((field) => valueType(field.type, unit, site)),
          {
            for (final field in namedFields)
              field.name: valueType(field.type, unit, site),
          },
        ),
      _ when type.isDartCoreNull => .nullType,
      dart.InterfaceType(:final typeArguments) when type.isDartAsyncFutureOr =>
        ValueType.futureOr(valueType(typeArguments.single, unit, site)),
      dart.InterfaceType(:final element, :final typeArguments) =>
        classType(element, unit, site).instantiate(
          typeArguments.map((argument) => valueType(argument, unit, site)),
        ),
      _ => unsupported(unit, site, type.getDisplayString()),
    };
    return type.nullabilitySuffix == .question ? base.nullable : base;
  }

  /// Registers a binder group before its bounds or defaults are converted.
  List<TypeParameterType> registerTypeParameters(
    List<TypeParameterElement> elements,
  ) => [
    for (final element in elements)
      _parameters.putIfAbsent(
        element.baseElement,
        () => TypeParameterType(element.name!),
      ),
  ];

  /// Converts a binder group and its simultaneously scoped bounds and defaults.
  List<TypeParameterType> bindTypeParameters(
    List<TypeParameterElement> elements,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    List<dart.DartType?>? defaultTemplates,
  }) {
    if (defaultTemplates != null &&
        defaultTemplates.length != elements.length) {
      throw ArgumentError('Mismatched type parameter defaults.');
    }
    final parameters = registerTypeParameters(elements);
    for (final (i, element) in elements.indexed) {
      final initialize = _boundParameters.add(element.baseElement);
      // Ordinary metadata is immutable. Only exact recovered templates can
      // augment a binder that has already been initialized.
      if (!initialize && defaultTemplates == null) continue;
      if (initialize) {
        parameters[i].initializeBound(
          element.bound == null
              ? ValueType.object.nullable
              : valueType(element.bound!, unit, site),
        );
      }
      final template = defaultTemplates?[i] ?? typeParameterDefault(element);
      if (template != null) {
        final converted = valueType(template, unit, site);
        if (parameters[i].defaultType == null) {
          parameters[i].initializeDefaultType(converted);
        } else if (parameters[i].defaultType != converted) {
          unsupported(
            unit,
            site,
            'inconsistent type parameter default metadata',
          );
        }
      }
    }
    return parameters;
  }

  FunctionType _functionType(
    dart.FunctionType type,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    List<FormalParameterElement>? parameters,
  }) {
    final formals = parameters ?? type.formalParameters;
    final binders = bindTypeParameters(type.typeParameters, unit, site);
    return FunctionType(
      valueType(type.returnType, unit, site),
      formals.map((p) => valueType(p.type, unit, site)),
      typeParameters: binders,
      optionalPositional: formals.where((p) => p.isOptionalPositional).length,
      namedParameters: {
        for (final p in formals)
          if (p.isNamed) p.name!: p.isRequiredNamed,
      },
    );
  }

  ValueType _parameterType(
    dart.TypeParameterType type,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final element = type.element.baseElement;
    final parameter = _parameters[element];
    if (parameter == null) {
      unsupported(unit, site, 'unbound type parameter ${element.name}');
    }
    final bound = element.bound;
    final promoted = bound == null
        ? type.bound is! dart.DynamicType
        : type.bound != bound;
    if (!promoted) return parameter;
    if (type.bound.isDartCoreObject &&
        type.bound.nullabilitySuffix != .question) {
      return parameter.nonNullable;
    }
    return PromotedTypeParameterType(
      parameter,
      valueType(type.bound, unit, site),
    );
  }

  /// Resolves one nominal declaration for its type, constructors and field owners.
  ClassType classType(
    InterfaceElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final ffi = ffiClass(element);
    if (element.library.isDartCore || ffi != null) {
      final builtin =
          ffi ??
          switch (element.name) {
            'Object' => ValueType.object,
            'Type' => ValueType.typeType,
            'Error' => ValueType.error,
            'Exception' => CoreTypes.exception,
            'IntegerDivisionByZeroException' =>
              CoreTypes.integerDivisionByZeroException,
            'TypeError' => ValueType.typeError,
            'NoSuchMethodError' => ValueType.noSuchMethodError,
            'ArgumentError' => ValueType.argumentError,
            'StateError' => ValueType.stateError,
            'UnsupportedError' => ValueType.unsupportedError,
            'AssertionError' => ValueType.assertionError,
            'StackTrace' => ValueType.stackTrace,
            'num' => ValueType.number,
            'int' => ValueType.integer,
            'double' => ValueType.floating,
            'String' => ValueType.string,
            'bool' => ValueType.boolean,
            'Record' => ValueType.record,
            'Function' => ValueType.function,
            'Iterable' => CoreTypes.iterable,
            'Iterator' => CoreTypes.iterator,
            'List' => CoreTypes.list,
            'Set' => CoreTypes.set,
            'Map' => CoreTypes.map,
            'MapEntry' => CoreTypes.mapEntry,
            'Enum' => CoreTypes.enumeration,
            'Symbol' => CoreTypes.symbol,
            'Invocation' => CoreTypes.invocation,
            '_Invocation' => CoreTypes.invocationStorage,
            _ => null,
          };
      if (builtin != null) {
        for (final (i, parameter) in element.typeParameters.indexed) {
          _parameters[parameter.baseElement] = builtin.typeParameters[i];
          _boundParameters.add(parameter.baseElement);
        }
        return builtin;
      }
    }
    if (element.library.isDartAsync &&
        (element.name == 'Future' || element.name == 'Stream')) {
      final type = element.name == 'Future'
          ? CoreTypes.future
          : CoreTypes.stream;
      final parameter = element.typeParameters.single.baseElement;
      _parameters[parameter] = type.typeParameters.single;
      _boundParameters.add(parameter);
      return type;
    }
    if (element.library.uri.toString() == 'dart:_internal' &&
        element.name == 'Symbol') {
      return CoreTypes.symbolStorage;
    }
    final previous = _classes[element];
    if (previous != null) return previous;
    if (!isClassLike(element)) {
      unsupported(unit, site, 'class ${element.name}');
    }
    if (element is MixinElement) _checkMixin(element, unit, site);
    if (element.mixins.isNotEmpty) {
      for (
        var parent = element.supertype;
        parent != null && !parent.isDartCoreObject;
        parent = parent.element.supertype
      ) {
        if (!_modeledClasses.containsKey(parent.element) &&
            !(parent.element.library.isDartCore &&
                parent.element.name == 'Enum')) {
          unsupported(
            unit,
            site,
            'mixin application with unmodeled superclass',
          );
        }
      }
    }
    final parameters = registerTypeParameters(element.typeParameters);
    final type = ClassType.declare(
      element.library.uri,
      element.name!,
      typeParameters: parameters,
      isAbstract:
          element is MixinElement ||
          element is ClassElement && (element.isAbstract || element.isSealed),
    );
    _classes[element] = type;
    _classElements[type] = element;
    bindTypeParameters(element.typeParameters, unit, site);
    var parent = element.supertype == null
        ? ValueType.object
        : valueType(element.supertype!, unit, site) as ClassType;
    final applications = <IrClass>[];
    final effective = <MemberSelector, FunctionTarget>{
      if (element.mixins.isNotEmpty && element.supertype != null)
        ..._planImplementations(element.supertype!.element),
    };
    Iterable<dart.InterfaceType> expand(dart.InterfaceType mixin) sync* {
      for (final nested in mixin.mixins) {
        yield* expand(nested);
      }
      yield mixin;
    }

    for (final mixin in element.mixins.expand(expand)) {
      _checkMixin(mixin.element, unit, site);
      final view = valueType(mixin, unit, site) as ClassType;
      final application = ClassType(
        type.library,
        '<${element.name}:mixin:${applications.length}>',
        superclass: parent,
        interfaces: [view],
        typeParameters: parameters,
        isAbstract: true,
      );
      final members = <FunctionTarget>[];
      for (final member in <ExecutableElement>[
        ...mixin.element.methods,
        ...mixin.element.getters,
        ...mixin.element.setters,
      ]) {
        if (member.isStatic) continue;
        final source = target(member, unit, site);
        final signature = source.signature.rebind(view.typeEnvironment);
        final inherited = effective[source.selector];
        Set<int> covariance(Map<FunctionTarget, Set<int>> flags) => {
          ...?flags[source],
          if (inherited != null)
            ..._transportCovariance(inherited, member, flags[inherited] ?? {}),
        };
        final declarationFlags = covariance(_declarationCovariance);
        final classFlags = covariance(_classCovariance);
        final bound = FunctionTarget(
          type.library,
          source.name,
          signature.result,
          signature.parameters,
          owner: application,
          kind: source.kind,
          typeParameters: signature.typeParameters,
          privateSelectorLibrary: source.selector.privateLibrary,
          optionalPositional: signature.optionalPositional,
          namedParameters: signature.namedParameters,
          covariantParameters: {...declarationFlags, ...classFlags},
          isAbstract: member.isAbstract,
        );
        _typeEnvironments[bound] = {
          ...view.typeEnvironment,
          for (final (i, parameter) in source.typeParameters.indexed)
            parameter: signature.typeParameters[i],
        };
        _defaults[bound] = defaults(source);
        _declarationCovariance[bound] = declarationFlags;
        _classCovariance[bound] = classFlags;
        _boundCovariance[bound] = {
          ...?_boundCovariance[source],
          ...?_boundCovariance[inherited],
        };
        if (!bound.isAbstract) effective[bound.selector] = bound;
        members.add(bound);
      }
      _applicationOwners[application] = (owner: element, source: mixin.element);
      applications.add(
        IrClass(
          application,
          const [],
          members: members,
          constructors: [
            if (mixin.element.fields.any(
              (field) =>
                  !field.isStatic && !field.isLate && field.hasInitializer,
            ))
              FunctionTarget(
                type.library,
                '<mixin-fields>',
                .voidType,
                const [],
                owner: application,
                kind: .initializer,
              ),
          ],
        ),
      );
      parent = application;
    }
    if (applications.isNotEmpty) _mixinApplications[element] = applications;
    type.initializeHierarchy(
      superclass: parent,
      interfaces: [
        ...element.interfaces,
        if (element is MixinElement) ...element.superclassConstraints,
      ].map((interface) => valueType(interface, unit, site) as ClassType),
    );
    return type;
  }

  void _checkMixin(
    InterfaceElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (!_modeledClasses.containsKey(element)) {
      unsupported(unit, site, 'unmodeled mixin source');
    }
  }
}

/// Explicit arguments after their source-order evaluation.
typedef EvaluatedArguments = ({
  List<Value> positional,
  Map<String, Value> named,
});

/// Evaluates each argument once, retaining omissions and names for the dispatch target.
EvaluatedArguments? evaluateArguments(
  ast.ArgumentList? arguments,
  Value? Function(ast.Expression, FormalParameterElement?) evaluate, {
  Map<FormalParameterElement, Value> forwarded = const {},
  required Value? Function(Value, FormalParameterElement, ast.AstNode) convert,
}) {
  final positional = <Value>[], named = <String, Value>{};
  for (final MapEntry(key: parameter, :value) in forwarded.entries) {
    if (parameter.isNamed) {
      named[parameter.name!] = value;
    } else {
      positional.add(value);
    }
  }
  for (final argument in arguments?.arguments ?? const <ast.Argument>[]) {
    final parameter = argument.correspondingParameter;
    final input = evaluate(argument.argumentExpression, parameter);
    if (input == null) return null;
    final value = parameter == null
        ? input
        : convert(input, parameter, argument);
    if (value == null) return null;
    if (argument is ast.NamedArgument) {
      named[argument.name.lexeme] = value;
    } else {
      positional.add(value);
    }
  }
  return (positional: positional, named: named);
}

/// Reports an unimplemented [feature] at the start of [node] in [unit].
Never unsupported(ResolvedUnitResult unit, ast.AstNode node, String feature) {
  final location = unit.lineInfo.getLocation(node.offset);
  throw UnsupportedError(
    '${unit.uri}:${location.lineNumber}:${location.columnNumber}: IR lowering for $feature',
  );
}

/// Whether a switch without a default must cover every value of [type].
bool requiresExhaustiveSwitch(dart.DartType type) => switch (type) {
  dart.RecordType(:final namedFields, :final positionalFields) =>
    positionalFields.every((f) => requiresExhaustiveSwitch(f.type)) &&
        namedFields.every((f) => requiresExhaustiveSwitch(f.type)),
  dart.InterfaceType(element: EnumElement() || ClassElement(isSealed: true)) =>
    true,
  _ => type.isDartCoreBool || type.isDartCoreNull,
};

/// Whether source members use the explicit-receiver static ABI.
bool isExtensionOwner(Element? element) =>
    element is ExtensionElement || element is ExtensionTypeElement;

/// Whether this declaration uses the shared class member lowering.
bool isClassLike(Element? element) =>
    element is ClassElement ||
    element is EnumElement ||
    element is MixinElement;
