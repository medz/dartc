import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'builder.dart';
import 'levels.dart';
import 'scope.dart';
import 'types.dart';

/// What errors call what is missing, and what kind of member it would be.
typedef _Missing = ({String name, int level, int kind, String? found});

// Levels and kinds of the official runtime.
const _static = 2, _constructor = 3, _topLevel = 4;
const _method = 0, _getter = 1, _setter = 2;

/// Throws the error for a call of [element], which nothing implements, as the
/// body of its function.
void throwExternal(
  ProgramScope scope,
  FunctionBuilder builder,
  ExecutableElement element,
) {
  final (:name, :level, :kind, :found) = _missing(element);
  final class_ = level == _topLevel ? null : element.enclosingElement;
  HirValue text(String? text) =>
      builder.add(text == null ? HirNull() : scope.text(text));
  // Members of mixins are those of where they are mixed in.
  final mixedIn = builder.level;
  final HirValue receiver;
  if (mixedIn != null && mixedIn.isMixin && class_ == mixedIn.element) {
    final application = mixedIn.class_;
    receiver = application is ClassElement && application.isMixinApplication
        ? _typeOf(scope, builder, application)
        : text(_applicationName(mixedIn));
  } else {
    receiver = class_ is InterfaceElement
        ? _typeOf(scope, builder, class_)
        : text(null);
  }
  builder
    ..call(
      HirCall(scope.runtime('throwExternal'), [
        receiver,
        text(name),
        builder.add(HirConst(level << 3 | kind)),
        text(found),
      ]),
    )
    ..end(HirUnreachable());
}

/// What the official runtime calls the class that [level] of a mixin makes,
/// which the program does not name: the class, its superclass and the mixins
/// up to this one.
String _applicationName(Level level) {
  final class_ = level.class_;
  final mixins = [for (final mixin in class_.mixins) mixin.element.displayName];
  final count = mixins.indexOf(level.element.displayName) + 1;
  final superclass = class_.supertype?.element.displayName ?? 'Object';
  return [
    '_${class_.displayName}',
    superclass,
    ...mixins.take(count),
  ].join('&');
}

/// The object that the type [class_] is, with the bounds of its parameters.
HirValue _typeOf(
  ProgramScope scope,
  FunctionBuilder builder,
  InterfaceElement class_,
) {
  final type = builder.library.typeSystem.instantiateInterfaceToBounds(
    element: class_,
    nullabilitySuffix: .none,
  );
  return builder.add(HirStatic(scope.typeObject(type)!));
}

_Missing _missing(ExecutableElement element) {
  final owner = element.enclosingElement;
  final kind = switch (element) {
    GetterElement() => _getter,
    SetterElement() => _setter,
    _ => _method,
  };
  final name = element.lookupName!;
  final type = describeType(element.type);
  switch (owner) {
    case ExtensionElement() || ExtensionTypeElement():
      // Their members belong to the library.
      final own = switch (element) {
        GetterElement(isStatic: false) => 'get#${element.name}',
        SetterElement(isStatic: false) => 'set#${element.name}',
        ConstructorElement() => 'constructor#${element.name}',
        _ => name,
      };
      return (
        name: '${owner!.displayName}|$own',
        level: _topLevel,
        kind: element.isStatic ? kind : _method,
        found: null,
      );
    case InterfaceElement() when element is ConstructorElement:
      final own = element.name == 'new' ? '' : element.name;
      final called = '${owner.displayName}.$own';
      return (name: called, level: _constructor, kind: kind, found: type);
    case InterfaceElement():
      final found = element is MethodElement && element.isStatic ? type : null;
      return (name: name, level: _static, kind: kind, found: found);
    default:
      return (name: name, level: _topLevel, kind: kind, found: null);
  }
}
