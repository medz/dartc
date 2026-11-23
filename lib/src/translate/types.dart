import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

/// Finds the function of an element, or null if the SDK declares it.
typedef FunctionLookup = HirFunction? Function(TopLevelFunctionElement element);

/// The representation of values of [type], or null if not supported yet.
HirType? valueType(DartType type) {
  if (type.nullabilitySuffix != .none) return null;
  if (type.isDartCoreInt) return .integer;
  if (type.isDartCoreDouble) return .float;
  if (type.isDartCoreBool) return .boolean;
  return null;
}

/// Whether a function returning [type] gives its caller nothing to use.
bool hasNoResult(DartType type) =>
    type is VoidType || type is DynamicType || type is NeverType;
