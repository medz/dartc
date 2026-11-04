import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

import 'analyzer_metadata.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class Bindings({final bool enableAssertions = false}) {
  final _targets = <ExecutableElement, FunctionTarget>{};
  final _classes = <InterfaceElement, ClassType>{};
  final _parameters = <TypeParameterElement, TypeParameterType>{};
  final _boundParameters = <TypeParameterElement>{};
  final _fields = <FieldElement, InstanceField>{};
  final _defaults = <FunctionTarget, Map<int, Constant>>{};

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
    if (element is PropertyAccessorElement &&
        element.isStatic &&
        element.isOriginVariable) {
      unsupported(unit, site, 'stored static or top-level variable');
    }
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

  /// Returns the same slot for every use of this field declaration.
  InstanceField field(
    FieldElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) => _fields.putIfAbsent(
    element.baseElement,
    () => InstanceField(
      classType(element.enclosingElement as InterfaceElement, unit, site),
      element.name!,
      valueType(element.type, unit, site),
      isFinal: element.isFinal,
    ),
  );

  /// Reads a resolved constant or optional parameter's default value.
  Constant constantOf(
    VariableElement variable,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
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
  ) => _constantValue(value, site is ast.Expression ? site : null, unit, site);

  Constant _constantValue(
    DartObject? value,
    ast.Expression? syntax,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    if (value != null) {
      if (value.isNull) return const .nullValue();
      if (value.toIntValue() case final i?) return .integer(i);
      if (value.toBoolValue() case final b?) return .boolean(b);
      if (value.toDoubleValue() case final d?) return .floating(d);
      if (value.toStringValue() case final s?) return .string(s);
      if (value.toFunctionValue() case final executable?) {
        final callable = target(executable, unit, site);
        final functionType = value.type! as dart.FunctionType;
        final arguments = constantFunctionArguments(value);
        if (executable is ConstructorElement) {
          final alias = _constantConstructorAlias(value, syntax);
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

  /// Registers a binder group before any of its bounds are converted.
  List<TypeParameterType> registerTypeParameters(
    List<TypeParameterElement> elements,
  ) => [
    for (final element in elements)
      _parameters.putIfAbsent(
        element.baseElement,
        () => TypeParameterType(element.name!),
      ),
  ];

  /// Converts a binder group and its simultaneously scoped bounds.
  List<TypeParameterType> bindTypeParameters(
    List<TypeParameterElement> elements,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final parameters = registerTypeParameters(elements);
    for (final (i, element) in elements.indexed) {
      if (!_boundParameters.add(element.baseElement)) continue;
      parameters[i].initializeBound(
        element.bound == null
            ? ValueType.object.nullable
            : valueType(element.bound!, unit, site),
      );
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
        'Error' => ValueType.error,
        'TypeError' => ValueType.typeError,
        'StateError' => ValueType.stateError,
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
        _ => null,
      };
      if (builtin != null) {
        for (final (i, parameter) in element.typeParameters.indexed) {
          _parameters[parameter.baseElement] = builtin.typeParameters[i];
        }
        return builtin;
      }
    }
    final previous = _classes[element];
    if (previous != null) return previous;
    if (element is! ClassElement || element.mixins.isNotEmpty) {
      unsupported(unit, site, 'class ${element.name} with mixins');
    }
    final parameters = registerTypeParameters(element.typeParameters);
    final type = ClassType.declare(
      element.library.uri,
      element.name!,
      typeParameters: parameters,
      isAbstract: element.isAbstract || element.isSealed,
    );
    _classes[element] = type;
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
      named[argument.correspondingParameter!.name!] = value;
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
