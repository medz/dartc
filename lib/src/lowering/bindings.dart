import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class Bindings({final bool enableAssertions = false}) {
  final _targets = <ExecutableElement, FunctionTarget>{};
  final _classes = <InterfaceElement, ClassType>{};
  final _parameters = <TypeParameterElement, TypeParameterType>{};
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
    if (element.typeParameters.isNotEmpty) {
      unsupported(unit, site, 'generic functions');
    }
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
    return constantValue(value, unit, site);
  }

  /// Converts an analyzer constant into an independent IR operand.
  Constant constantValue(
    DartObject? value,
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
        final ClassType? ownerType;
        final functionType = value.type;
        if (executable is ConstructorElement &&
            callable.owner!.typeParameters.isNotEmpty &&
            functionType is dart.FunctionType) {
          ownerType =
              valueType(functionType.returnType, unit, site) as ClassType;
        } else {
          ownerType = null;
        }
        return FunctionConstant(callable, ownerType: ownerType);
      }
      if (value.toRecordValue() case final record?) {
        final type = valueType(value.type!, unit, site);
        if (type is RecordType) {
          return RecordConstant(type, [
            for (final field in record.positional)
              constantValue(field, unit, site),
            for (final name in type.slots.keys.skip(type.positionalCount))
              constantValue(record.named[name]!, unit, site),
          ]);
        }
      }
    }
    unsupported(unit, site, 'constant ${value?.type}');
  }

  /// Maps the resolved Dart [type] to its IR type.
  ValueType valueType(
    dart.DartType type,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    final ValueType base = switch (type) {
      dart.VoidType() => .voidType,
      dart.NeverType() => .never,
      final dart.TypeParameterType parameter => _parameterType(
        parameter,
        unit,
        site,
      ),
      dart.FunctionType(
        :final formalParameters,
        :final returnType,
        typeParameters: [],
      ) =>
        FunctionType(
          valueType(returnType, unit, site),
          formalParameters.map((p) => valueType(p.type, unit, site)),
          optionalPositional: formalParameters
              .where((p) => p.isOptionalPositional)
              .length,
          namedParameters: {
            for (final p in formalParameters)
              if (p.isNamed) p.name!: p.isRequiredNamed,
          },
        ),
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
    final parameters = [
      for (final parameter in element.typeParameters)
        _parameters.putIfAbsent(
          parameter.baseElement,
          () => TypeParameterType(parameter.name!),
        ),
    ];
    final type = ClassType.declare(
      element.library.uri,
      element.name!,
      typeParameters: parameters,
      isAbstract: element.isAbstract || element.isSealed,
    );
    _classes[element] = type;
    for (final (i, parameter) in element.typeParameters.indexed) {
      parameters[i].initializeBound(
        parameter.bound == null
            ? ValueType.object.nullable
            : valueType(parameter.bound!, unit, site),
      );
    }
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
    final value = evaluate(argument.argumentExpression);
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
