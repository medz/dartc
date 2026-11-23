import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

/// The representation of values of [type], or null if not supported yet.
HirType? valueType(DartType type) {
  if (type.isDartCoreNull || classOf(type) != null) return .reference;
  if (type.nullabilitySuffix != .none) return null;
  if (type.isDartCoreInt) return .integer;
  if (type.isDartCoreDouble) return .float;
  if (type.isDartCoreBool) return .boolean;
  return null;
}

/// The class whose objects, or null, are the values of [type].
///
/// Of the SDK's classes only `Object` is supported yet.
ClassElement? classOf(DartType? type) {
  if (type is! InterfaceType || type.typeArguments.isNotEmpty) return null;
  final element = type.element;
  if (element is! ClassElement) return null;
  return element.library.isInSdk && !element.isDartCoreObject ? null : element;
}

/// Whether a function returning [type] gives its caller nothing to use.
bool hasNoResult(DartType type) =>
    type is VoidType || type is DynamicType || type is NeverType;

/// Whether objects of [sub] are objects of [superclass] too.
bool isSubclass(ClassElement sub, ClassElement superclass) =>
    sub == superclass ||
    sub.allSupertypes.any((type) => type.element == superclass);
