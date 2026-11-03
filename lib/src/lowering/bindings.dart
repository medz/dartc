import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
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
              ? scalarConstant(parameter, unit, site)
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
  List<Value> arguments(
    TopLevelFunctionElement callee,
    ast.ArgumentList arguments,
    ResolvedUnitResult unit,
    Value Function(ast.Expression) evaluate,
  ) {
    final parameters = callee.formalParameters;
    final values = List<Value?>.filled(parameters.length, null);
    for (final argument in arguments.arguments) {
      final binding = _parameters[argument.correspondingParameter];
      if (binding == null) unsupported(unit, argument, 'argument binding');
      values[binding.slot] = evaluate(argument.argumentExpression);
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

/// Reads a resolved scalar constant or optional parameter's default value.
Constant scalarConstant(
  VariableElement variable,
  ResolvedUnitResult unit,
  ast.AstNode site,
) {
  final value = variable.computeConstantValue();
  if (value == null) {
    if (variable is FormalParameterElement &&
        variable.isOptional &&
        !variable.hasDefaultValue) {
      return const .nullValue();
    }
  } else {
    if (value.isNull) return const .nullValue();
    if (value.toIntValue() case final i?) return .integer(i);
    if (value.toBoolValue() case final b?) return .boolean(b);
    if (value.toDoubleValue() case final d?) return .floating(d);
    if (value.toStringValue() case final s?) return .string(s);
  }
  unsupported(unit, site, 'constant value of ${variable.name}');
}

/// Reports an unimplemented [feature] at the start of [node] in [unit].
Never unsupported(ResolvedUnitResult unit, ast.AstNode node, String feature) {
  final location = unit.lineInfo.getLocation(node.offset);
  throw UnsupportedError(
    '${unit.uri}:${location.lineNumber}:${location.columnNumber}: IR lowering for $feature',
  );
}

/// Maps the resolved Dart [type] to its IR type.
ValueType valueType(DartType type, ResolvedUnitResult unit, ast.AstNode site) {
  if (type is VoidType) return .voidType;
  if (type.isDartCoreNull) return .nullType;
  if (type.nullabilitySuffix == .none) {
    if (type.isDartCoreInt) return .integer;
    if (type.isDartCoreBool) return .boolean;
    if (type.isDartCoreDouble) return .floating;
    if (type.isDartCoreString) return .string;
  }
  unsupported(unit, site, type.getDisplayString());
}
