import 'package:analyzer/dart/element/element.dart';

import 'types.dart';

/// Whether [element] is a member of objects, rather than of a class or library.
bool isInstanceMember(Element? element) =>
    element is ExecutableElement &&
    element is! ConstructorElement &&
    element.enclosingElement is InstanceElement &&
    !element.isStatic;

/// What the type arguments are for that the function of [element] takes, if
/// it takes any.
Element? takesTypes(ExecutableElement element) {
  if (element.typeParameters.isNotEmpty) return element;
  final owner = element.enclosingElement;
  return element is ConstructorElement &&
          owner is ClassElement &&
          owner.typeParameters.isNotEmpty
      ? owner
      : null;
}

/// The implementation that objects of [class_] have for a member like
/// [member], or null if it is abstract.
ExecutableElement? implementationIn(
  ClassElement class_,
  ExecutableElement member,
) {
  InterfaceElement? found = class_;
  while (found != null) {
    for (final own in _membersLike(member, found)) {
      if (_sameName(own, member) && !own.isStatic && !_isAbstract(own)) {
        return own;
      }
    }
    found = found.supertype?.element;
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
FieldElement? fieldOfAccessor(ExecutableElement member) => switch (member) {
  PropertyAccessorElement(
    isOriginVariable: true,
    :final FieldElement variable,
  ) =>
    variable,
  _ => null,
};

/// Every member of the superclasses and interfaces of [class_] that a member
/// like [member] overrides.
Iterable<ExecutableElement> overriddenBy(
  ClassElement class_,
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

/// Whether calls may give [parameter] of a method values that are not of its
/// type.
bool isUnchecked(FormalParameterElement parameter) {
  final method = parameter.enclosingElement;
  final owner = method?.enclosingElement;
  if (parameter.isCovariant || mentions(parameter.type, owner)) return true;
  if (method is! MethodElement || owner is! ClassElement) return false;
  final place = method.formalParameters.indexOf(parameter);
  return overriddenBy(owner, method).any((other) {
    final declared = parameter.isNamed
        ? other.formalParameters.where((p) => p.name == parameter.name)
        : other.formalParameters.skip(place).take(1);
    return declared.any((p) => mentions(p.type, other.enclosingElement));
  });
}
