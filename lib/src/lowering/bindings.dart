import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/ir.dart';

/// Maps analyzer declarations and formal parameters to their IR identities.
final class TargetBindings() {
  final _targets = <TopLevelFunctionElement, FunctionTarget>{};
  final _slots = <FormalParameterElement, int>{};

  /// The declaration-order slot of [parameter], once its target has been bound.
  int? slotOf(FormalParameterElement? parameter) => _slots[parameter];

  /// Returns the shared target for [element] and records its parameter slots.
  FunctionTarget target(
    TopLevelFunctionElement element,
    ResolvedUnitResult unit,
    ast.AstNode site,
  ) {
    return _targets.putIfAbsent(element, () {
      final parameters = element.formalParameters;
      if (element.typeParameters.isNotEmpty ||
          parameters.any((p) => p.isOptional)) {
        unsupported(unit, site, 'generic functions or optional parameters');
      }
      for (var i = 0; i < parameters.length; i++) {
        _slots[parameters[i]] = i;
      }
      return .new(
        element.library.uri,
        element.name!,
        valueType(element.returnType, unit, site),
        parameters.map((p) => valueType(p.type, unit, site)),
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

/// Maps the resolved Dart [type] to its IR type.
ValueType valueType(DartType type, ResolvedUnitResult unit, ast.AstNode site) {
  if (type is VoidType) return .voidType;
  if (type.nullabilitySuffix == .none) {
    if (type.isDartCoreInt) return .integer;
    if (type.isDartCoreBool) return .boolean;
  }
  unsupported(unit, site, type.getDisplayString());
}
