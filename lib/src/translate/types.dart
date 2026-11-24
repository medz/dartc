import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
// Only this tells what type parameters are by default.
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/type_system.dart' show TypeSystemImpl;
import 'package:dartc/hir.dart';

/// The representation of values of [declared], or null if not supported yet.
HirType? valueType(DartType declared) {
  final type = declared.extensionTypeErasure;
  if (type.nullabilitySuffix == .none && type is InterfaceType) {
    if (plainType(type.element) case final plain?) return plain;
  }
  return isTop(type) ||
          type is FunctionType ||
          type is RecordType ||
          type is TypeParameterType ||
          type.isDartCoreNull ||
          type is NeverType && !isNever(type) ||
          type.isDartAsyncFutureOr ||
          classOf(type) != null
      ? .reference
      : null;
}

/// What the class of boxes for [type] is called.
String boxName(HirType type) => switch (type) {
  .integer => '_Mint',
  .float => '_Double',
  _ => 'bool',
};

/// How objects of [class_] are represented without boxes, if they are.
HirType? plainType(InterfaceElement class_) => class_.library.isDartCore
    ? switch (class_.name) {
        'int' || '_IntegerImplementation' || '_Smi' || '_Mint' => .integer,
        'double' || '_Double' => .float,
        'bool' => .boolean,
        _ => null,
      }
    : null;

/// Whether objects of [class_] are numbers.
bool _isNumeric(InterfaceElement class_) =>
    class_.library.isDartCore &&
    (class_.name == 'num' ||
        plainType(class_) == .integer ||
        plainType(class_) == .float);

/// Whether every value is of [declared].
bool isTop(DartType declared) {
  final type = declared.extensionTypeErasure;
  if (type is InterfaceType && type.isDartAsyncFutureOr) {
    return isTop(type.typeArguments.single);
  }
  return type is DynamicType ||
      type is VoidType ||
      type.isDartCoreObject && type.nullabilitySuffix == .question;
}

/// Whether a value of a type can be a number.
bool canBeNumber(DartType declared) {
  final type = boundOf(declared);
  return isTop(type) ||
      type.isDartCoreObject ||
      type is InterfaceType &&
          (type.isDartAsyncFutureOr ||
              _isNumeric(type.element) ||
              type.element.name == 'Comparable');
}

/// Whether the type given is that of numbers, without null.
bool isNumber(DartType? declared) {
  if (declared == null || declared.nullabilitySuffix != .none) return false;
  final type = boundOf(declared);
  return type.nullabilitySuffix == .none &&
      type is InterfaceType &&
      _isNumeric(type.element);
}

/// The type that a value of [type], which can be a type parameter or extension
/// type, has for sure.
DartType boundOf(DartType type) {
  var found = type.extensionTypeErasure;
  while (found is TypeParameterType) {
    found = found.bound.extensionTypeErasure;
  }
  return found;
}

/// Whether what has [type] can be of another type if type arguments of [owner]
/// are subtypes of those known.
///
/// They are used as they are, or as what functions take if [isTaken].
bool mentions(DartType type, Element? owner, {bool isTaken = false}) =>
    switch (type.extensionTypeErasure) {
      TypeParameterType(:final element) =>
        !isTaken && element.enclosingElement == owner,
      InterfaceType(:final typeArguments) => typeArguments.any(
        (argument) => mentions(argument, owner, isTaken: isTaken),
      ),
      FunctionType(
        :final returnType,
        :final formalParameters,
        :final typeParameters,
      ) =>
        boundsMention(typeParameters, owner) ||
            mentions(returnType, owner, isTaken: isTaken) ||
            formalParameters.any(
              (p) => mentions(p.type, owner, isTaken: !isTaken),
            ),
      final RecordType type => fieldsOf(
        type,
      ).any((field) => mentions(field, owner, isTaken: isTaken)),
      _ => false,
    };

/// Whether functions with [parameters] have other bounds if type arguments of
/// [owner] are others than those known.
bool boundsMention(List<TypeParameterElement> parameters, Element? owner) =>
    parameters.any(
      (parameter) => switch (parameter.bound) {
        final bound? =>
          mentions(bound, owner) || mentions(bound, owner, isTaken: true),
        null => false,
      },
    );

/// Whether [type] is [parameter].
bool isParameter(DartType type, TypeParameterElement parameter) =>
    type is TypeParameterType &&
    type.element == parameter &&
    type.nullabilitySuffix == .none;

/// The types of the fields of [type].
Iterable<DartType> fieldsOf(RecordType type) => [
  for (final field in type.positionalFields) field.type,
  for (final field
      in type.namedFields.toList()..sort((a, b) => a.name.compareTo(b.name)))
    field.type,
];

/// Whether [type] is made of other type parameters than [bound].
bool _hasFree(DartType type, Set<TypeParameterElement> bound) => switch (type) {
  TypeParameterType(:final element) => !bound.contains(element),
  InterfaceType(:final typeArguments) => typeArguments.any(
    (argument) => _hasFree(argument, bound),
  ),
  FunctionType(:final typeParameters) => () {
    final inner = {...bound, ...typeParameters};
    bool isFree(DartType type) => _hasFree(type, inner);
    return isFree(type.returnType) ||
        type.formalParameters.any((p) => isFree(p.type)) ||
        typeParameters.any((p) => p.bound != null && isFree(p.bound!));
  }(),
  RecordType() => fieldsOf(type).any((field) => _hasFree(field, bound)),
  _ => false,
};

/// Whether [type] is made of type parameters.
bool isOpen(DartType type) => switch (type.extensionTypeErasure) {
  TypeParameterType() => true,
  InterfaceType(:final typeArguments) => typeArguments.any(isOpen),
  FunctionType(typeParameters: [_, ...]) && final type => _hasFree(
    type,
    const {},
  ),
  FunctionType(:final returnType, :final formalParameters) =>
    isOpen(returnType) || formalParameters.any((p) => isOpen(p.type)),
  final RecordType type => fieldsOf(type).any(isOpen),
  _ => false,
};

/// The class whose objects, or null, are the values of a type.
InterfaceElement? classOf(DartType? declared) {
  final type = declared == null ? null : boundOf(declared);
  if (type is! InterfaceType || type.isDartAsyncFutureOr) return null;
  final element = type.element;
  return element is ExtensionTypeElement ? null : element;
}

/// The type [declared] as the official runtime calls it.
///
/// Type parameters have the names that [names] gives.
String describeType(
  DartType declared, [
  Map<TypeParameterElement, String> names = const {},
]) {
  final type = declared.extensionTypeErasure;
  if (type is TypeParameterType) {
    final name = names[type.element];
    if (name != null) {
      return type.nullabilitySuffix == .question ? '$name?' : name;
    }
  }
  final suffix = type.nullabilitySuffix == .question ? '?' : '';
  if (type is InterfaceType && type.typeArguments.isNotEmpty) {
    final arguments = type.typeArguments
        .map((argument) => describeType(argument, names))
        .join(', ');
    return '${type.element.displayName}<$arguments>$suffix';
  }
  if (type is RecordType) return '${_describeRecord(type, names)}$suffix';
  if (type is! FunctionType) return type.getDisplayString();
  final text = _describeFunction(type, names);
  return suffix.isEmpty ? text : '($text)$suffix';
}

String _describeRecord(
  RecordType type,
  Map<TypeParameterElement, String> names,
) {
  final named = [
    for (final field
        in type.namedFields.toList()..sort((a, b) => a.name.compareTo(b.name)))
      '${describeType(field.type, names)} ${field.name}',
  ];
  final fields = [
    for (final field in type.positionalFields) describeType(field.type, names),
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ];
  return '(${fields.join(', ')})';
}

/// The text before each parameter type in declaration order, then the result.
List<String> functionTypePrefixes(List<FormalParameterElement> parameters) {
  final parts = <String>[];
  var before = '(', close = '';
  for (final p in parameters) {
    if (parts.isNotEmpty) before += ', ';
    if (close.isEmpty && !p.isRequiredPositional) {
      before += p.isNamed ? '{' : '[';
      close = p.isNamed ? '}' : ']';
    }
    parts.add(p.isRequiredNamed ? '${before}required ' : before);
    before = p.isNamed ? ' ${p.name}' : '';
  }
  return parts..add('$before$close) => ');
}

String _describeFunction(
  FunctionType type,
  Map<TypeParameterElement, String> outer,
) {
  final names = {...outer};
  for (final parameter in type.typeParameters) {
    names[parameter] = 'Y${names.length}';
  }
  String describe(DartType type) => describeType(type, names);
  final parameters = type.formalParameters;
  final text = functionTypePrefixes(parameters);
  final parts = [
    for (final (i, p) in parameters.indexed) '${text[i]}${describe(p.type)}',
    '${text.last}${describe(type.returnType)}',
  ];
  final own = [
    for (final parameter in type.typeParameters)
      if (parameter.bound case final bound? when !isTop(bound))
        '${names[parameter]} extends ${describe(bound)}'
      else
        names[parameter]!,
  ];
  final generic = own.isEmpty ? '' : '<${own.join(', ')}>';
  return '$generic${parts.join()}';
}

/// Whether a function returning [type] gives its caller nothing to use.
///
/// Where the result is of type `void`, there can be one, which a caller that
/// does not know that type uses.
bool hasNoResult(DartType type) => isNever(type);

/// Whether expressions of [type] never give a value.
bool isNever(DartType? type) =>
    type is NeverType && type.nullabilitySuffix == .none;

/// The type arguments that make the generic [element] a function of [type].
List<DartType> typeArgumentsOf(ExecutableElement element, FunctionType type) {
  final owner = element.enclosingElement;
  final parameters = element.typeParameters.isNotEmpty
      ? element.typeParameters
      : owner is InterfaceElement
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
      case (RecordType a, RecordType b):
        final found = fieldsOf(b).toList();
        for (final (i, field) in fieldsOf(a).indexed) {
          if (i < found.length) match(field, found[i]);
        }
    }
  }

  match(element.type, type);
  return [
    for (final parameter in parameters)
      found[parameter] ?? element.library.typeProvider.dynamicType,
  ];
}

/// What [parameters] of generic functions are where a call does not tell.
List<DartType> defaultTypesOf(
  List<TypeParameterElement> parameters,
  LibraryElement library,
) => (library.typeSystem as TypeSystemImpl).instantiateTypeFormalsToBounds(
  parameters.cast(),
);

/// Whether objects of [sub] are objects of [superclass] too.
bool isSubclass(InterfaceElement sub, InterfaceElement superclass) =>
    sub == superclass ||
    sub.allSupertypes.any((type) => type.element == superclass) ||
    _isHiddenSubclass(sub, superclass);

/// Every integer is one of those that the official runtime calls small. The
/// class of functions does not tell that it implements another, and enums do
/// not tell what they extend.
bool _isHiddenSubclass(InterfaceElement sub, InterfaceElement superclass) =>
    superclass.library.isDartCore &&
    (superclass.name == '_Smi' && plainType(sub) == .integer ||
        superclass.name == '_Enum' && sub is EnumElement ||
        superclass.name == 'Function' &&
            sub.library.isDartCore &&
            sub.name == '_Closure');
