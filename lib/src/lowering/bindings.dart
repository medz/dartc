import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'analyzer_metadata.dart';
import 'constant_safety.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class Bindings({final bool enableAssertions = false}) {
  final _constantSafety = ConstantSafety();
  final _targets = <ExecutableElement, FunctionTarget>{};
  final _classes = <InterfaceElement, ClassType>{};
  final _classElements = <ClassType, InterfaceElement>{};
  final _parameters = <TypeParameterElement, TypeParameterType>{};
  final _boundParameters = <TypeParameterElement>{};
  final _fields = <FieldElement, InstanceField>{};
  final _globals = <VariableElement, GlobalVariable>{};
  final _defaults = <FunctionTarget, Map<int, Constant>>{};
  final _constantAliases = <LibraryElement, List<TypeAliasElement>>{};

  final _modeledClasses =
      <InterfaceElement, (ResolvedUnitResult, ast.AstNode)>{};
  final _implementationPlans =
      <InterfaceElement, Map<MemberSelector, FunctionTarget>>{};
  final _syntheticTargets = <FunctionTarget>{};
  final _forwarderClassCovariance = <FunctionTarget, Set<int>>{};
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
    for (final member in <ExecutableElement>[
      ...element.methods,
      ...element.getters,
      ...element.setters,
    ]) {
      if (!member.isStatic && !member.isAbstract) {
        final implementation = target(member, unit, site);
        effective[implementation.selector] = implementation;
      }
    }
    final emitted = <FunctionTarget>[];
    final unsupportedSelectors = <MemberSelector>{};
    for (final candidate in noSuchMethodForwarderCandidates(element)) {
      final member = candidate.member;
      final selector = _memberSelector(member, candidate.privateLibrary);
      final inherited = effective[selector];
      // Analyzer propagates forwarder markers across real concrete overrides.
      if (inherited != null && !_syntheticTargets.contains(inherited)) {
        if (candidate.overridesConcrete) {
          unsupported(
            unit,
            site,
            'inherited private noSuchMethod forwarder ${member.name}',
          );
        }
        continue;
      }
      final foreignPrivate =
          candidate.privateLibrary != null &&
          candidate.privateLibrary != element.library.uri;
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
        // Only an actual inherited synthetic target requires comparison first.
        if (foreignPrivate || unmodeledParent) {
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
      final replacement = _forwarderTarget(
        element,
        member,
        templates,
        unit,
        site,
        inheritedClassCovariance: inherited == null
            ? const {}
            : _transportCovariance(
                inherited,
                member,
                _forwarderClassCovariance[inherited] ?? const {},
              ),
      );
      if (inherited != null) {
        if (inherited.signatureFor(owner) == replacement.signature) {
          final inheritedCovariance = _transportCovariance(
            inherited,
            member,
            inherited.covariantParameters,
          );
          if (inheritedCovariance.length !=
                  replacement.covariantParameters.length ||
              !inheritedCovariance.containsAll(
                replacement.covariantParameters,
              )) {
            unsupported(
              unit,
              site,
              'inherited noSuchMethod covariance transition ${member.name}',
            );
          }
          continue;
        }
      }
      if (foreignPrivate) {
        if (inherited != null || candidate.overridesConcrete) {
          unsupported(
            unit,
            site,
            'inherited private noSuchMethod forwarder ${member.name}',
          );
        }
        unsupportedSelectors.add(selector);
        continue;
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

  // FunctionType equality ignores named declaration order, unlike entry slots.
  // Transfer inherited checks by named identity and only positional index.
  Set<int> _transportCovariance(
    FunctionTarget inherited,
    ExecutableElement selected,
    Set<int> slots,
  ) {
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
    final result = FunctionTarget(
      destination.library.uri,
      selected.name!,
      valueType(selected.returnType, unit, site),
      parameters.map((p) => valueType(p.type, unit, site)),
      owner: owner,
      kind: _memberSelector(selected).kind,
      typeParameters: binders,
      optionalPositional: parameters
          .where((p) => p.isOptionalPositional)
          .length,
      namedParameters: {
        for (final p in parameters)
          if (p.isNamed) p.name!: p.isRequiredNamed,
      },
      covariantParameters: [
        ...inheritedClassCovariance,
        for (final (i, p) in parameters.indexed)
          if (p.isCovariant) i,
      ],
    );
    // These checks survive specialization even when the destination's own
    // parameter types no longer contain class variables. Keep their provenance
    // through further signature replacements as well as unchanged inheritance.
    _forwarderClassCovariance[result] = {
      ...inheritedClassCovariance,
      for (final (i, type) in result.signature.parameters.indexed)
        if (containsCovariantTypeParameter(type, owner.typeParameters.toSet()))
          i,
    };
    _defaults[result] = {
      for (final (i, p) in parameters.indexed)
        if (p.isOptional) i: constantOf(p.baseElement, unit, site),
    };
    return result;
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
      final element = _classElements[owner.declaration];
      final parent = element?.supertype?.element;
      if (parent != null) {
        final actual = _planImplementations(parent)[_memberSelector(member)];
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
    element = element.baseElement;
    final previous = enclosing == null ? _targets[element] : null;
    if (previous != null) return previous;
    final parameters = element.formalParameters;
    final container = element.enclosingElement;
    if (element.isStatic &&
        element.library.isDartCore &&
        container is ClassElement &&
        container.name == 'Enum') {
      unsupported(unit, site, 'core Enum member ${element.name}');
    }
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
    final function = FunctionTarget(
      element.library.uri,
      element.name ?? '<anonymous>',
      kind == .initializer
          ? .voidType
          : valueType(element.returnType, unit, site),
      parameters.map((p) => valueType(p.type, unit, site)),
      owner: owner,
      typeParameters: typeParameters,
      kind: kind,
      redirect: destination,
      redirectOwnerType: redirectOwnerType,
      enclosing: enclosing,
      sourceOffset: sourceOffset,
      captures: captures,
      covariantParameters: [
        if (kind.isVirtual)
          for (final (i, p) in parameters.indexed)
            if (p.isCovariant) i,
      ],
      isAbstract: kind.isVirtual && element.isAbstract,
      optionalPositional: parameters
          .where((p) => p.isOptionalPositional)
          .length,
      namedParameters: {
        for (final p in parameters)
          if (p.isNamed) p.name!: p.isRequiredNamed,
      },
    );
    if (enclosing == null) _targets[element] = function;
    if (destination == null && parameters.any((p) => p.isOptional)) {
      _defaults[function] = {
        for (final (i, p) in parameters.indexed)
          if (p.isOptional) i: constantOf(p, unit, site),
      };
    }
    return function;
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

  /// Binds a top-level or static declaration using its actual source initializer.
  GlobalVariable global(
    PropertyInducingElement element,
    ResolvedUnitResult unit,
    ast.VariableDeclaration declaration,
  ) => _globals.putIfAbsent(element.baseElement as VariableElement, () {
    final container = element.enclosingElement;
    final owner = container is InterfaceElement
        ? classType(container, unit, declaration)
        : null;
    final type = valueType(element.type, unit, declaration);
    return GlobalVariable(
      element.library.uri,
      element.name!,
      type,
      owner: owner,
      isFinal: element.isFinal,
      isLate: element.isLate,
      initializer: declaration.initializer == null
          ? null
          : FunctionTarget(
              element.library.uri,
              '<initialize:${element.name}>',
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
    ast.AstNode site,
  ) {
    element = element.baseElement;
    return _fields.putIfAbsent(element, () {
      final owner = classType(
        element.enclosingElement as InterfaceElement,
        unit,
        site,
      );
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
      final type = valueType(element.type, unit, site);
      return InstanceField(
        owner,
        element.name!,
        type,
        isFinal: element.isFinal,
        isLate: element.isLate,
        initializer: element.isLate && element.hasInitializer
            ? FunctionTarget(
                element.library.uri,
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
  ) {
    _constantSafety.check(unit, site, variable: variable);
    final value = variable.computeConstantValue();
    if (value == null &&
        variable is FormalParameterElement &&
        variable.isOptional &&
        !variable.hasDefaultValue) {
      return const .nullValue();
    }
    return _constantValue(value, variable.constantInitializer, unit, site);
  }

  /// Converts an analyzer constant into an independent IR operand.
  Constant constantValue(
    DartObject? value,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final expression = site is ast.Expression ? site : null;
    _constantSafety.check(unit, site, expression: expression);
    return _constantValue(value, expression, unit, site);
  }

  Constant _constantValue(
    DartObject? value,
    ast.Expression? syntax,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
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
          final alias = _constantConstructorAlias(
            value,
            syntax,
            unit.libraryElement,
          );
          if (alias != null) {
            final signature = constructorAliasSignature(
              alias,
              callable,
              unit,
              site,
            );
            return FunctionConstant(
              callable,
              constructorSignature: signature,
              constructorAlias: (alias.library.uri, alias.name!),
              typeArguments: functionType.typeParameters.isEmpty
                  ? arguments!.map((t) => valueType(t, unit, site))
                  : null,
            );
          }
          if (constantFunctionHasAlias(value)) {
            unsupported(unit, site, 'constant constructor alias provenance');
          }
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
          elements.map(
            (element) => _constantValue(element, syntax, unit, site),
          ),
        );
      }
      if (value.toMapValue() case final entries?) {
        return MapConstant(
          valueType(value.type!, unit, site) as ClassType,
          entries.entries.map(
            (entry) => (
              _constantValue(entry.key, syntax, unit, site),
              _constantValue(entry.value, syntax, unit, site),
            ),
          ),
        );
      }
      if (value.toRecordValue() case final record?) {
        final type = valueType(value.type!, unit, site);
        if (type is RecordType) {
          final expressions = <int, ast.Expression>{};
          if (syntax is ast.RecordLiteral) {
            var positional = 0;
            for (final field in syntax.fields) {
              final slot = field is ast.RecordLiteralNamedField
                  ? type.slots[field.name.lexeme]!
                  : positional++;
              expressions[slot] = field.fieldExpression;
            }
          }
          return RecordConstant(type, [
            for (final (i, field) in record.positional.indexed)
              _constantValue(field, expressions[i] ?? syntax, unit, site),
            for (final name in type.slots.keys.skip(type.positionalCount))
              _constantValue(
                record.named[name]!,
                expressions[type.slots[name]] ?? syntax,
                unit,
                site,
              ),
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
          if (!isClassOrEnum(element) ||
              element.mixins.isNotEmpty ||
              element.library.isInSdk &&
                  !layerType.isDartCoreObject &&
                  !(element.library.isDartCore && element.name == 'MapEntry') ||
              !layer.hasKnownValue) {
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
            fields[field(declaration, unit, site)] = _constantValue(
              layer.getField(declaration.name!),
              declaration.constantInitializer ?? syntax,
              unit,
              site,
            );
          }
          if (element is EnumElement) {
            // Analyzer stores Enum's inherited slots directly in the enum value,
            // unlike the separate superclass layer used by ordinary instances.
            fields[CoreTypes.enumIndex] = _constantValue(
              layer.getField('index'),
              syntax,
              unit,
              site,
            );
            fields[CoreTypes.enumName] = _constantValue(
              layer.getField('_name'),
              syntax,
              unit,
              site,
            );
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

  /// Builds the independently bound callable view of an alias constructor.
  FunctionType constructorAliasSignature(
    TypeAliasElement alias,
    FunctionTarget target,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final parameters = bindTypeParameters(alias.typeParameters, unit, site);
    final owner = valueType(alias.aliasedType, unit, site) as ClassType;
    final signature = target.signatureFor(owner);
    return FunctionType(
      signature.result,
      signature.parameters,
      typeParameters: parameters,
      optionalPositional:
          signature.positionalCount - signature.requiredPositional,
      namedParameters: {
        for (final entry in signature.named.entries)
          entry.key: entry.value.required,
      },
    );
  }

  TypeAliasElement? _constantConstructorAlias(
    DartObject value,
    ast.Expression? syntax,
    LibraryElement library,
  ) {
    final aliases = <TypeAliasElement>{};
    final visited = <VariableElement>{};
    void scan(ast.AstNode? node) {
      if (node == null) return;
      if (node is ast.NamedType && node.element is TypeAliasElement) {
        aliases.add(node.element as TypeAliasElement);
      }
      final variable = switch (node) {
        ast.Identifier(element: final VariableElement variable) => variable,
        ast.Identifier(element: GetterElement(:final variable)) => variable,
        _ => null,
      };
      if (variable != null && variable.isConst && visited.add(variable)) {
        scan(variable.constantInitializer);
      }
      for (final child in node.childEntities) {
        if (child is ast.AstNode) scan(child);
      }
    }

    scan(syntax);
    scan(value.variable?.constantInitializer);
    for (final alias in aliases) {
      if (constantFunctionUsesAlias(value, alias)) return alias;
    }
    // A nested value can originate in a constructor default or initializer,
    // with no alias syntax at this use. Match the analyzer's retained identity
    // against reachable declarations rather than guessing from the function type.
    if (constantFunctionHasAlias(value)) {
      final candidates = _constantAliases.putIfAbsent(library, () {
        final libraries = <LibraryElement>{};
        final result = <TypeAliasElement>[];
        void collect(LibraryElement current) {
          if (!libraries.add(current)) return;
          result.addAll(current.typeAliases);
          for (final dependency in [
            ...current.exportedLibraries,
            for (final fragment in current.fragments)
              ...fragment.importedLibraries,
          ]) {
            if (!dependency.isInSdk) collect(dependency);
          }
        }

        collect(library);
        return result;
      });
      for (final alias in candidates) {
        if (constantFunctionUsesAlias(value, alias)) return alias;
      }
    }
    return null;
  }

  /// Maps the resolved Dart [type] to its IR type.
  ValueType valueType(
    dart.DartType type,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
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
    ast.AstNode site,
  ) {
    final parameters = bindTypeParameters(type.typeParameters, unit, site);
    return FunctionType(
      valueType(type.returnType, unit, site),
      type.formalParameters.map((p) => valueType(p.type, unit, site)),
      typeParameters: parameters,
      optionalPositional: type.formalParameters
          .where((p) => p.isOptionalPositional)
          .length,
      namedParameters: {
        for (final p in type.formalParameters)
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
    unsupported(
      unit,
      site,
      'type parameter intersection ${type.getDisplayString()}',
    );
  }

  /// Resolves one nominal declaration for its type, constructors and field owners.
  ClassType classType(
    InterfaceElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (element.library.isDartCore) {
      final builtin = switch (element.name) {
        'Object' => ValueType.object,
        'Type' => ValueType.typeType,
        'Error' => ValueType.error,
        'TypeError' => ValueType.typeError,
        'NoSuchMethodError' => ValueType.noSuchMethodError,
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
    if (element.library.uri.toString() == 'dart:_internal' &&
        element.name == 'Symbol') {
      return CoreTypes.symbolStorage;
    }
    final previous = _classes[element];
    if (previous != null) return previous;
    if (!isClassOrEnum(element) || element.mixins.isNotEmpty) {
      unsupported(unit, site, 'class ${element.name} with mixins');
    }
    final parameters = registerTypeParameters(element.typeParameters);
    final type = ClassType.declare(
      element.library.uri,
      element.name!,
      typeParameters: parameters,
      isAbstract:
          element is ClassElement && (element.isAbstract || element.isSealed),
    );
    _classes[element] = type;
    _classElements[type] = element;
    bindTypeParameters(element.typeParameters, unit, site);
    type.initializeHierarchy(
      superclass: valueType(element.supertype!, unit, site) as ClassType,
      interfaces: element.interfaces.map(
        (interface) => valueType(interface, unit, site) as ClassType,
      ),
    );
    return type;
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
  Value? Function(ast.Expression) evaluate, {
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
    final input = evaluate(argument.argumentExpression);
    if (input == null) return null;
    final parameter = argument.correspondingParameter;
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

/// Whether this declaration uses the shared class member lowering.
bool isClassOrEnum(Element? element) =>
    element is ClassElement || element is EnumElement;

/// Resolves only the public SDK enum protocols, not user members of the same name.
InstanceField? coreEnumField(ExecutableElement? member) {
  if (member is! GetterElement || !member.library.isDartCore) return null;
  return switch ((member.enclosingElement, member.name)) {
    (ClassElement(name: 'Enum'), 'index') => CoreTypes.enumIndex,
    (ExtensionElement(name: 'EnumName'), 'name') => CoreTypes.enumName,
    _ => null,
  };
}

/// Whether this SDK member has a supported runtime-backed virtual protocol.
///
/// Keep these public protocols virtual: user implementations need not carry
/// the SDK implementation's storage, and subclasses may inherit or override
/// their concrete getters.
bool coreRuntimeMember(ExecutableElement member, ValueType receiver) {
  if (!member.library.isDartCore || member.isStatic) return false;
  return switch ((member, member.enclosingElement?.name, member.name)) {
    (GetterElement(), 'Symbol', 'hashCode') => true,
    (
      GetterElement(),
      'Invocation',
      'memberName' ||
          'typeArguments' ||
          'positionalArguments' ||
          'namedArguments' ||
          'isMethod' ||
          'isGetter' ||
          'isSetter' ||
          'isAccessor',
    ) =>
      true,
    (MethodElement(), 'Object', 'toString') =>
      CoreTypes.view(receiver, CoreTypes.symbol) != null,
    _ => false,
  };
}
