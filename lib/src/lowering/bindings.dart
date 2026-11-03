import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class Bindings() {
  final _targets = <ExecutableElement, FunctionTarget>{};
  final _classes = <InterfaceElement, ClassType>{};
  final _fields = <FieldElement, InstanceField>{};
  final _defaults = <FunctionTarget, Map<int, Constant>>{};

  /// Returns the shared signature and constructor binding for [element].
  FunctionTarget target(
    ExecutableElement element,
    ResolvedUnitResult unit,
    ast.AstNode site, {
    Set<ConstructorElement>? redirects,
  }) {
    element = element.baseElement;
    final previous = _targets[element];
    if (previous != null) return previous;
    final parameters = element.formalParameters;
    final enclosing = element.enclosingElement;
    final owner = enclosing is InterfaceElement
        ? classType(enclosing, unit, site)
        : null;
    final kind = switch (element) {
      ConstructorElement(:final isFactory) =>
        isFactory ? FunctionKind.factory : FunctionKind.initializer,
      GetterElement(isStatic: false) => FunctionKind.getter,
      SetterElement(isStatic: false) => FunctionKind.setter,
      MethodElement(isStatic: false) => FunctionKind.method,
      _ => FunctionKind.function,
    };
    if (element.typeParameters.isNotEmpty) {
      unsupported(unit, site, 'generic functions');
    }
    FunctionTarget? destination;
    if (element case final ConstructorElement ctor
        when ctor.isFactory && ctor.redirectedConstructor != null) {
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
      element.name!,
      kind == .initializer
          ? .voidType
          : valueType(element.returnType, unit, site),
      parameters.map((p) => valueType(p.type, unit, site)),
      owner: owner,
      kind: kind,
      redirect: destination,
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
    _targets[element] = function;
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
        return FunctionConstant(target(executable, unit, site));
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
      dart.InterfaceType(:final element) when type.typeArguments.isEmpty =>
        classType(element, unit, site),
      _ => unsupported(unit, site, type.getDisplayString()),
    };
    return type.nullabilitySuffix == .question ? base.nullable : base;
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
        'StackTrace' => ValueType.stackTrace,
        'num' => ValueType.number,
        'int' => ValueType.integer,
        'double' => ValueType.floating,
        'String' => ValueType.string,
        'bool' => ValueType.boolean,
        'Record' => ValueType.record,
        'Function' => ValueType.function,
        _ => null,
      };
      if (builtin != null) return builtin;
    }
    return _classes.putIfAbsent(element, () {
      if (element is! ClassElement ||
          element.typeParameters.isNotEmpty ||
          element.mixins.isNotEmpty) {
        unsupported(
          unit,
          site,
          'class ${element.name} with type parameters or mixins',
        );
      }
      return ClassType(
        element.library.uri,
        element.name!,
        superclass: classType(element.supertype!.element, unit, site),
        interfaces: element.interfaces.map(
          (it) => classType(it.element, unit, site),
        ),
        isAbstract: element.isAbstract || element.isSealed,
      );
    });
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
