import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';

/// The representation of values of [type], or null if not supported yet.
HirType? valueType(DartType type) {
  if (type.nullabilitySuffix == .none) {
    if (type.isDartCoreInt) return .integer;
    if (type.isDartCoreDouble) return .float;
    if (type.isDartCoreBool) return .boolean;
  }
  return isTop(type) ||
          type is FunctionType && type.typeParameters.isEmpty ||
          type.isDartCoreNull ||
          type is NeverType && !isNever(type) ||
          classOf(type) != null
      ? .reference
      : null;
}

/// Whether every value is of [type].
bool isTop(DartType type) =>
    type is DynamicType ||
    type is VoidType ||
    type.isDartCoreObject && type.nullabilitySuffix == .question;

/// Whether a value of [type] can be a number.
bool canBeNumber(DartType type) =>
    isTop(type) ||
    type.isDartCoreObject ||
    type.isDartCoreNum ||
    type.isDartCoreInt ||
    type.isDartCoreDouble;

/// Whether [type] is that of numbers, without null.
bool isNumber(DartType? type) =>
    type != null &&
    type.nullabilitySuffix == .none &&
    (type.isDartCoreNum || type.isDartCoreInt || type.isDartCoreDouble);

/// The class whose objects, or null, are the values of [type].
///
/// Of the SDK's classes only `Object`, numbers, `bool`, errors, exceptions and
/// stack traces are supported yet.
ClassElement? classOf(DartType? type) {
  if (type is! InterfaceType || type.typeArguments.isNotEmpty) return null;
  final element = type.element;
  if (element is! ClassElement) return null;
  return element.library.isInSdk && !_isKnown(element) ? null : element;
}

bool _isKnown(ClassElement class_) =>
    class_.library.isDartCore &&
    (class_.isDartCoreObject ||
        const {
          'num',
          'int',
          'double',
          'bool',
          'Function',
        }.contains(class_.name) ||
        class_.name == 'StackTrace' ||
        _isFailure(class_) ||
        class_.allSupertypes.any((type) => _isFailure(type.element)));

bool _isFailure(InterfaceElement class_) =>
    class_.library.isDartCore &&
    (class_.name == 'Error' || class_.name == 'Exception');

/// [type] as the official runtime calls it.
String describeType(DartType type) {
  if (type is! FunctionType) return type.getDisplayString();
  String list(Iterable<FormalParameterElement> parameters) =>
      parameters.map((p) => describeType(p.type)).join(', ');
  final all = type.formalParameters;
  final optional = all.where((p) => p.isOptionalPositional);
  final named = all
      .where((p) => p.isNamed)
      .map(
        (p) =>
            '${p.isRequiredNamed ? 'required ' : ''}'
            '${describeType(p.type)} ${p.name}',
      );
  final parameters = [
    if (all.any((p) => p.isRequiredPositional))
      list(all.where((p) => p.isRequiredPositional)),
    if (optional.isNotEmpty) '[${list(optional)}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ];
  final text = '(${parameters.join(', ')}) => ${describeType(type.returnType)}';
  return type.nullabilitySuffix == .question ? '($text)?' : text;
}

/// Whether a function returning [type] gives its caller nothing to use.
bool hasNoResult(DartType type) => type is VoidType || isNever(type);

/// Whether expressions of [type] never give a value.
bool isNever(DartType? type) =>
    type is NeverType && type.nullabilitySuffix == .none;

/// Whether objects of [sub] are objects of [superclass] too.
bool isSubclass(ClassElement sub, ClassElement superclass) =>
    _isSameClass(sub, superclass) ||
    sub.allSupertypes.any((type) => _isSameClass(type.element, superclass));

/// The program and the runtime have each their own elements for the SDK.
bool _isSameClass(InterfaceElement a, InterfaceElement b) =>
    a == b ||
    a.library.isInSdk &&
        b.library.isInSdk &&
        a.name == b.name &&
        a.library.uri == b.library.uri;
