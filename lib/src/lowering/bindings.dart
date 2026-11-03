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
  final _parameters =
      <FormalParameterElement, ({int slot, Constant? fallback})>{};

  /// Returns the shared target for [element] and records its parameter slots.
  FunctionTarget target(
    ExecutableElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    element = element.baseElement;
    return _targets.putIfAbsent(element, () {
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
      for (final (i, parameter) in parameters.indexed) {
        _parameters[parameter] = (
          slot: i,
          fallback: parameter.isOptional
              ? constantOf(parameter, unit, site)
              : null,
        );
      }
      return .new(
        element.library.uri,
        element.name!,
        kind == .initializer
            ? .voidType
            : valueType(element.returnType, unit, site),
        parameters.map((p) => valueType(p.type, unit, site)),
        owner: owner,
        kind: kind,
        isAbstract: kind.isVirtual && element.isAbstract,
        optionalPositional: parameters
            .where((p) => p.isOptionalPositional)
            .length,
        namedParameters: {
          for (final p in parameters)
            if (p.isNamed) p.name!: p.isRequiredNamed,
        },
      );
    });
  }

  /// The declaration defaults used by calls that dispatch to [element].
  Map<int, Constant> defaults(ExecutableElement element) => {
    for (final p in element.formalParameters)
      if (_parameters[p.baseElement] case (
        slot: final i,
        fallback: final value?,
      ))
        i: value,
  };

  /// Evaluates explicit [arguments] in source order, then fills omitted slots.
  List<Value>? arguments(
    ExecutableElement callee,
    ast.ArgumentList? arguments,
    ResolvedUnitResult unit,
    Value? Function(ast.Expression) evaluate, {
    Map<FormalParameterElement, Value> forwarded = const {},
  }) {
    final parameters = callee.formalParameters;
    final values = List<Value?>.filled(parameters.length, null);
    for (final MapEntry(:key, :value) in forwarded.entries) {
      values[_parameters[key.baseElement]!.slot] = value;
    }
    for (final argument in arguments?.arguments ?? const <ast.Argument>[]) {
      final binding = _parameters[argument.correspondingParameter?.baseElement];
      if (binding == null) unsupported(unit, argument, 'argument binding');
      final value = evaluate(argument.argumentExpression);
      if (value == null) return null;
      values[binding.slot] = value;
    }
    if ((arguments?.arguments.length ?? 0) + forwarded.length < values.length) {
      for (final (i, parameter) in parameters.indexed) {
        values[i] ??=
            _parameters[parameter]?.fallback ??
            unsupported(unit, arguments ?? unit.unit, 'missing argument');
      }
    }
    return values.cast<Value>();
  }

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
