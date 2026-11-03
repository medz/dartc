import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class TargetBindings() {
  final _targets = <TopLevelFunctionElement, FunctionTarget>{};
  final _parameters =
      <FormalParameterElement, ({int slot, Constant? fallback})>{};

  /// Returns the shared target for [element] and records its parameter slots.
  FunctionTarget target(
    TopLevelFunctionElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    return _targets.putIfAbsent(element, () {
      final parameters = element.formalParameters;
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
        valueType(element.returnType, unit, site),
        parameters.map((p) => valueType(p.type, unit, site)),
      );
    });
  }

  /// Evaluates explicit [arguments] in source order, then fills omitted slots.
  List<Value>? arguments(
    TopLevelFunctionElement callee,
    ast.ArgumentList arguments,
    ResolvedUnitResult unit,
    Value? Function(ast.Expression) evaluate,
  ) {
    final parameters = callee.formalParameters;
    final values = List<Value?>.filled(parameters.length, null);
    for (final argument in arguments.arguments) {
      final binding = _parameters[argument.correspondingParameter];
      if (binding == null) unsupported(unit, argument, 'argument binding');
      final value = evaluate(argument.argumentExpression);
      if (value == null) return null;
      values[binding.slot] = value;
    }
    if (arguments.arguments.length < values.length) {
      for (final (i, parameter) in parameters.indexed) {
        values[i] ??=
            _parameters[parameter]?.fallback ??
            unsupported(unit, arguments, 'missing argument');
      }
    }
    return values.cast<Value>();
  }
}

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

/// Reports an unimplemented [feature] at the start of [node] in [unit].
Never unsupported(ResolvedUnitResult unit, ast.AstNode node, String feature) {
  final location = unit.lineInfo.getLocation(node.offset);
  throw UnsupportedError(
    '${unit.uri}:${location.lineNumber}:${location.columnNumber}: IR lowering for $feature',
  );
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
    dart.RecordType(:final positionalFields, :final namedFields) => RecordType(
      positionalFields.map((field) => valueType(field.type, unit, site)),
      {
        for (final field in namedFields)
          field.name: valueType(field.type, unit, site),
      },
    ),
    _ when type.isDartCoreNull => .nullType,
    _ when type.isDartCoreInt => .integer,
    _ when type.isDartCoreBool => .boolean,
    _ when type.isDartCoreDouble => .floating,
    _ when type.isDartCoreString => .string,
    _ when type.isDartCoreNum => .number,
    _ when type.isDartCoreObject => .object,
    _ when type.isDartCoreRecord => .record,
    dart.InterfaceType(
      element: ClassElement(
        library: LibraryElement(isDartCore: true),
        :final name,
      ),
    ) =>
      switch (name) {
        'Error' => .error,
        'TypeError' => .typeError,
        'StackTrace' => .stackTrace,
        _ => unsupported(unit, site, type.getDisplayString()),
      },
    _ => unsupported(unit, site, type.getDisplayString()),
  };
  return type.nullabilitySuffix == .question ? base.nullable : base;
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
