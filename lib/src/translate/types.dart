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
          type is TypeParameterType ||
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

/// Whether a value of a type can be a number.
bool canBeNumber(DartType declared) {
  final type = boundOf(declared);
  return isTop(type) ||
      type.isDartCoreObject ||
      type.isDartCoreNum ||
      type.isDartCoreInt ||
      type.isDartCoreDouble;
}

/// Whether the type given is that of numbers, without null.
bool isNumber(DartType? declared) {
  if (declared == null || declared.nullabilitySuffix != .none) return false;
  final type = boundOf(declared);
  return type.nullabilitySuffix == .none &&
      (type.isDartCoreNum || type.isDartCoreInt || type.isDartCoreDouble);
}

/// The type that a value of [type], a type parameter, has for sure.
DartType boundOf(DartType type) {
  var found = type;
  while (found is TypeParameterType) {
    found = found.bound;
  }
  return found;
}

/// Whether what has [type] can be of another type if type arguments of [owner]
/// are subtypes of those known.
///
/// They are used as they are, or as what functions take if [isTaken].
bool mentions(DartType type, Element? owner, {bool isTaken = false}) =>
    switch (type) {
      TypeParameterType(:final element) =>
        !isTaken && element.enclosingElement == owner,
      InterfaceType(:final typeArguments) => typeArguments.any(
        (argument) => mentions(argument, owner, isTaken: isTaken),
      ),
      FunctionType(:final returnType, :final formalParameters) =>
        mentions(returnType, owner, isTaken: isTaken) ||
            formalParameters.any(
              (p) => mentions(p.type, owner, isTaken: !isTaken),
            ),
      _ => false,
    };

/// Whether [type] is made of type parameters.
bool isOpen(DartType type) => switch (type) {
  TypeParameterType() => true,
  InterfaceType(:final typeArguments) => typeArguments.any(isOpen),
  FunctionType(:final returnType, :final formalParameters) =>
    isOpen(returnType) || formalParameters.any((p) => isOpen(p.type)),
  _ => false,
};

/// The class whose objects, or null, are the values of a type.
///
/// Of the SDK's classes only `Object`, numbers, `bool`, errors, exceptions and
/// stack traces are supported yet.
InterfaceElement? classOf(DartType? declared) {
  final type = declared == null ? null : boundOf(declared);
  if (type is! InterfaceType) return null;
  final element = type.element;
  if (element is! ClassElement && element is! MixinElement) return null;
  final isKnown =
      !element.library.isInSdk ||
      element is ClassElement &&
          _isKnown(element) &&
          type.typeArguments.isEmpty;
  return isKnown ? element : null;
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
  final suffix = type.nullabilitySuffix == .question ? '?' : '';
  if (type is InterfaceType && type.typeArguments.isNotEmpty) {
    final arguments = type.typeArguments.map(describeType).join(', ');
    return '${type.element.displayName}<$arguments>$suffix';
  }
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
  return suffix.isEmpty ? text : '($text)$suffix';
}

/// Whether a function returning [type] gives its caller nothing to use.
bool hasNoResult(DartType type) => type is VoidType || isNever(type);

/// Whether expressions of [type] never give a value.
bool isNever(DartType? type) =>
    type is NeverType && type.nullabilitySuffix == .none;

/// The type arguments that make the generic [element] a function of [type].
List<DartType> typeArgumentsOf(ExecutableElement element, FunctionType type) {
  final owner = element.enclosingElement;
  final parameters = element.typeParameters.isNotEmpty
      ? element.typeParameters
      : owner is ClassElement
      ? owner.typeParameters
      : const <TypeParameterElement>[];
  final found = <TypeParameterElement, DartType>{};
  void match(DartType declared, DartType actual) {
    switch ((declared, actual)) {
      case (TypeParameterType(:final element), _):
        found.putIfAbsent(element, () => actual);
      case (InterfaceType a, InterfaceType b):
        for (final (i, argument) in a.typeArguments.indexed) {
          if (i < b.typeArguments.length) match(argument, b.typeArguments[i]);
        }
      case (FunctionType a, FunctionType b):
        match(a.returnType, b.returnType);
        for (final (i, parameter) in a.formalParameters.indexed) {
          if (i < b.formalParameters.length) {
            match(parameter.type, b.formalParameters[i].type);
          }
        }
    }
  }

  match(element.type, type);
  return [
    for (final parameter in parameters)
      found[parameter] ?? element.library.typeProvider.dynamicType,
  ];
}

/// Whether objects of [sub] are objects of [superclass] too.
bool isSubclass(InterfaceElement sub, InterfaceElement superclass) =>
    _isSameClass(sub, superclass) ||
    sub.allSupertypes.any((type) => _isSameClass(type.element, superclass));

/// The program and the runtime have each their own elements for the SDK.
bool _isSameClass(InterfaceElement a, InterfaceElement b) =>
    a == b ||
    a.library.isInSdk &&
        b.library.isInSdk &&
        a.name == b.name &&
        a.library.uri == b.library.uri;
