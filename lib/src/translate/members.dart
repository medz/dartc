import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'levels.dart';
import 'native_types.dart';
import 'types.dart';

/// Whether [element] is a member of objects, rather than of a class or library.
bool isInstanceMember(Element? element) =>
    element is ExecutableElement &&
    element is! ConstructorElement &&
    element.enclosingElement is InstanceElement &&
    !element.isStatic;

/// Whether [element] is a member of values, declared by an extension or by an
/// extension type.
bool isExtensionMember(Element? element) =>
    isInstanceMember(element) && extendedType(element!) != null;

/// What the members of an extension or extension type, of which [element] is
/// one, are used on.
DartType? extendedType(Element element) => switch (element.enclosingElement) {
  ExtensionElement(:final extendedType) => extendedType,
  ExtensionTypeElement(:final typeErasure) => typeErasure,
  _ => null,
};

/// Whether [element] is a constructor that works on an object created before.
bool isInitializerElement(ExecutableElement element) =>
    element is ConstructorElement &&
    !element.isFactory &&
    element.enclosingElement is! ExtensionTypeElement;

/// Whether the function of [element] takes an object first.
bool hasReceiver(ExecutableElement element) =>
    isInstanceMember(element) && !isExtensionMember(element) ||
    isInitializerElement(element);

/// What the type arguments are for that the function of [element] takes, if
/// it takes any, besides those of an extension.
Element? takesTypes(ExecutableElement element) {
  if (element.typeParameters.isNotEmpty) return element;
  final owner = element.enclosingElement;
  return element is ConstructorElement &&
          owner is InterfaceElement &&
          owner.typeParameters.isNotEmpty
      ? owner
      : null;
}

/// The extension or extension type whose type arguments the function of
/// [element] takes before its own.
InstanceElement? takesExtensionTypes(ExecutableElement element) {
  final owner = element.enclosingElement;
  return isExtensionMember(element) &&
          owner is InstanceElement &&
          owner.typeParameters.isNotEmpty
      ? owner
      : null;
}

/// A member and the level that it is part of.
typedef Implementation = ({ExecutableElement element, Level level});

/// The implementation of a member like [member] that objects have whose class
/// is at [level], or null if it is abstract.
Implementation? implementationIn(Level level, ExecutableElement member) {
  for (final found in level.chain) {
    for (final own in _membersLike(member, found.element)) {
      if (_sameName(own, member) && !own.isStatic && !_isAbstract(own)) {
        return (element: own, level: found);
      }
    }
  }
  return null;
}

List<ExecutableElement> _membersLike(
  ExecutableElement member,
  InterfaceElement class_,
) => switch (member) {
  GetterElement() => class_.getters,
  SetterElement() => class_.setters,
  _ => class_.methods,
};

bool _sameName(ExecutableElement a, ExecutableElement b) =>
    a.lookupName == b.lookupName && (a.isPublic || a.library == b.library);

bool _isAbstract(ExecutableElement member) =>
    member.isAbstract || (fieldOfAccessor(member)?.isAbstract ?? false);

/// The field that an implicit getter or setter reads or writes.
FieldElement? fieldOfAccessor(ExecutableElement member) =>
    switch (variableOfAccessor(member)) {
      final FieldElement field when !isExternalVariable(field) => field,
      _ => null,
    };

/// The variable that declares [member], a getter or setter.
PropertyInducingElement? variableOfAccessor(ExecutableElement member) =>
    switch (member) {
      PropertyAccessorElement(isOriginVariable: true, :final variable) =>
        variable,
      _ => null,
    };

/// Whether [variable] is only a getter and maybe a setter, which are external.
///
/// External fields of structs and unions are fields, in memory that C knows.
bool isExternalVariable(PropertyInducingElement variable) => switch (variable) {
  TopLevelVariableElement(:final isExternal) => isExternal,
  FieldElement(isExternal: true, :final isStatic, :final enclosingElement) =>
    isStatic || !NativeTypes.isCompound(enclosingElement),
  _ => false,
};

/// Whether [member] is declared without saying what it does.
bool isExternalMember(ExecutableElement member) {
  final variable = variableOfAccessor(member);
  return variable == null ? member.isExternal : isExternalVariable(variable);
}

/// Every member of the superclasses and interfaces of [class_] that a member
/// like [member] overrides.
Iterable<ExecutableElement> overriddenBy(
  InterfaceElement class_,
  ExecutableElement member,
) sync* {
  for (final type in class_.allSupertypes) {
    for (final other in _membersLike(member, type.element)) {
      if (other != member && _sameName(other, member) && !other.isStatic) {
        yield other;
      }
    }
  }
}

/// The instance member called [name] of objects whose class is at [level], or
/// null if it has none. It is private to [library] if that is given.
Implementation? memberNamed(
  Level level,
  String name,
  LibraryElement? library, {
  bool isGetter = false,
  bool isSetter = false,
}) {
  for (final found in level.chain) {
    final InterfaceElement(:setters, :getters, :methods) = found.element;
    final members = isSetter
        ? setters
        : isGetter
        ? getters
        : methods;
    for (final member in members) {
      if (member.lookupName == name &&
          !member.isStatic &&
          !_isAbstract(member) &&
          (library == null || member.library == library)) {
        return (element: member, level: found);
      }
    }
  }
  return null;
}

/// What [class_] or its supertypes declare that is called like [member].
ExecutableElement declaredFor(
  InterfaceElement class_,
  ExecutableElement member,
) {
  final owner = member.enclosingElement;
  if (owner is InterfaceElement && isSubclass(class_, owner)) return member;
  for (final type in [class_.thisType, ...class_.allSupertypes]) {
    final found = switch (member) {
      GetterElement() => type.element.getGetter(member.name!),
      SetterElement() => type.element.getSetter(member.name!),
      _ => type.element.getMethod(member.name!),
    };
    if (found != null && !found.isStatic) return found;
  }
  return member;
}

/// Whether calls may give the parameter [declared] of a method values that are not of its
/// type.
bool isUnchecked(FormalParameterElement declared) {
  final parameter = declared.baseElement;
  final method = parameter.enclosingElement;
  final owner = method?.enclosingElement;
  if (parameter.isCovariant || mentions(parameter.type, owner)) return true;
  if (method is! MethodElement || owner is! InterfaceElement) return false;
  final place = method.formalParameters.indexOf(parameter);
  return overriddenBy(owner, method).any((other) {
    final declared = parameter.isNamed
        ? other.formalParameters.where((p) => p.name == parameter.name)
        : other.formalParameters.skip(place).take(1);
    return declared.any((p) => mentions(p.type, other.enclosingElement));
  });
}

/// The constructor that [element] redirects to, if it is a factory that does.
ConstructorElement? redirectionOf(ConstructorElement element) =>
    element.isFactory ? element.redirectedConstructor : null;

/// The parameter that a value given to [parameter] is passed on to, if it is
/// one of a redirecting factory.
FormalParameterElement? redirectedParameter(FormalParameterElement parameter) {
  final factory = parameter.enclosingElement;
  if (factory is! ConstructorElement) return null;
  final target = redirectionOf(factory)?.baseElement;
  if (target == null) return null;
  final parameters = target.formalParameters;
  return parameter.isNamed
      ? parameters.firstWhere((p) => p.isNamed && p.name == parameter.name)
      : parameters[factory.formalParameters.indexOf(parameter)];
}
