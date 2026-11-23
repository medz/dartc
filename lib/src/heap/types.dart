// What types say about each other and about objects.
import 'machine.dart';
import 'program.dart';
import 'type_objects.dart';

/// Whether [value] is of [type].
bool isInstance(Object? value, RuntimeType type) => value == null
    ? isSubtype(const BasicType(nullKind), type)
    : isSubtype(typeOf(value), type);

/// [type] or null.
RuntimeType nullable(RuntimeType type) {
  if (type is NullableType) return type;
  if (type is BasicType) {
    if (type.kind == objectKind) return const BasicType(anyKind);
    if (type.kind == neverKind) return const BasicType(nullKind);
    return type;
  }
  return NullableType(type);
}

bool _isTop(RuntimeType type) => type is BasicType && type.kind <= anyKind;
bool _isKind(RuntimeType type, int kind) =>
    type is BasicType && type.kind == kind;

bool isSubtype(RuntimeType a, RuntimeType b) {
  if (isSame(a, b) || _isTop(b) || _isKind(a, neverKind)) return true;
  if (_isTop(a)) return false;
  if (_isKind(a, nullKind)) return b is NullableType || _isKind(b, nullKind);
  if (a is NullableType) return b is NullableType && isSubtype(a.inner, b);
  if (b is NullableType) return isSubtype(a, b.inner);
  if (b is BasicType) {
    return b.kind == objectKind || a is BasicType && a.kind == b.kind;
  }
  if (a is InterfaceType && b is InterfaceType) return _isSubclass(a, b);
  if (a is FunctionType) {
    if (b is FunctionType) return _isSubfunction(a, b);
    return b is InterfaceType && b.number == functionNumber();
  }
  return false;
}

bool _isSubclass(InterfaceType a, InterfaceType b) {
  if (a.number == b.number) return _areSubtypes(a.arguments, b.arguments);
  for (var at = superTypesOf(a.number); at != null; at = at.tail) {
    if (at.number == b.number) {
      return _areSubtypes(
        _substituteAll(at.arguments, a.arguments),
        b.arguments,
      );
    }
  }
  return false;
}

bool _areSubtypes(TypeList? a, TypeList? b) {
  while (a != null && b != null) {
    if (!isSubtype(a.head, b.head)) return false;
    a = a.tail;
    b = b.tail;
  }
  return true;
}

bool _isSubfunction(FunctionType a, FunctionType b) {
  if (!isSubtype(a.result, b.result)) return false;
  // What [a] takes, required and optional, in order.
  var from = a.required, to = b.required;
  var isOptional = false;
  while (to != null) {
    if (from == null && !isOptional) {
      from = a.optional;
      isOptional = true;
    }
    if (from == null || !isSubtype(to.head, from.head)) return false;
    from = from.tail;
    to = to.tail;
  }
  if (from != null && !isOptional) return false;
  if (!isOptional) from = a.optional;
  for (var rest = b.optional; rest != null; rest = rest.tail) {
    if (from == null || !isSubtype(rest.head, from.head)) return false;
    from = from.tail;
  }
  return _areNamed(a.named, b.named);
}

bool _areNamed(NamedList? a, NamedList? b) {
  while (a != null) {
    if (b != null && a.name == b.name) {
      if (a.isRequired && !b.isRequired || !isSubtype(b.type, a.type)) {
        return false;
      }
      b = b.tail;
    } else if (a.isRequired) {
      return false;
    }
    a = a.tail;
  }
  return b == null;
}

TypeList? _substituteAll(TypeList? list, TypeList? own) => list == null
    ? null
    : TypeList(_substitute(list.head, own), _substituteAll(list.tail, own));

/// [type] with the parameters of its class replaced by [own].
RuntimeType _substitute(RuntimeType type, TypeList? own) {
  if (type is VariableType) {
    var at = own;
    for (var i = type.index; i > 0 && at != null; i--) {
      at = at.tail;
    }
    return at == null ? const BasicType(dynamicKind) : at.head;
  }
  if (type is NullableType) return nullable(_substitute(type.inner, own));
  if (type is InterfaceType) {
    return InterfaceType(type.number, _substituteAll(type.arguments, own));
  }
  if (type is FunctionType) {
    return FunctionType(
      _substitute(type.result, own),
      _substituteAll(type.required, own),
      _substituteAll(type.optional, own),
      _substituteNamed(type.named, own),
    );
  }
  return type;
}

NamedList? _substituteNamed(NamedList? list, TypeList? own) => list == null
    ? null
    : NamedList(
        list.name,
        _substitute(list.type, own),
        list.isRequired,
        _substituteNamed(list.tail, own),
      );

/// Whether [a] and [b] are the same type.
bool isSameType(RuntimeType a, RuntimeType b) {
  if (isSame(a, b)) return true;
  if (a is BasicType) return b is BasicType && a.kind == b.kind;
  if (a is NullableType)
    return b is NullableType && isSameType(a.inner, b.inner);
  if (a is InterfaceType) {
    return b is InterfaceType &&
        a.number == b.number &&
        _areSame(a.arguments, b.arguments);
  }
  return a is FunctionType &&
      b is FunctionType &&
      isSameType(a.result, b.result) &&
      _areSame(a.required, b.required) &&
      _areSame(a.optional, b.optional) &&
      _areSameNamed(a.named, b.named);
}

bool _areSame(TypeList? a, TypeList? b) {
  while (a != null && b != null) {
    if (!isSameType(a.head, b.head)) return false;
    a = a.tail;
    b = b.tail;
  }
  return a == null && b == null;
}

bool _areSameNamed(NamedList? a, NamedList? b) {
  while (a != null && b != null) {
    final isSame =
        a.name == b.name &&
        a.isRequired == b.isRequired &&
        isSameType(a.type, b.type);
    if (!isSame) return false;
    a = a.tail;
    b = b.tail;
  }
  return a == null && b == null;
}

/// A number that is equal for equal types.
int hashOfType(RuntimeType type) {
  if (type is BasicType) return type.kind + 1;
  if (type is NullableType) return hashOfType(type.inner) * 7 + 1;
  if (type is InterfaceType) {
    return (_hashOfList(type.arguments) * 31 + type.number) & 0x3fffffff;
  }
  if (type is! FunctionType) return 0;
  var hash = hashOfType(type.result) + _hashOfList(type.required) * 5;
  for (var at = type.named; at != null; at = at.tail) {
    hash = (hash * 31 + at.name) & 0x3fffffff;
  }
  return (hash + _hashOfList(type.optional) * 3) & 0x3fffffff;
}

int _hashOfList(TypeList? list) {
  var hash = 0;
  for (var at = list; at != null; at = at.tail) {
    hash = (hash * 31 + hashOfType(at.head)) & 0x3fffffff;
  }
  return hash;
}

/// What the type of [object] is called.
String objectTypeName(Object? object) =>
    object == null ? 'Null' : typeName(typeOf(object));

/// What [type] is called.
String typeName(RuntimeType type) {
  if (type is BasicType) return _basicName(type.kind);
  if (type is InterfaceType) {
    final name = className(type.number), arguments = type.arguments;
    return arguments == null ? name : '$name<${_listName(arguments)}>';
  }
  if (type is NullableType) {
    final inner = type.inner, name = typeName(inner);
    return inner is FunctionType ? '($name)?' : '$name?';
  }
  return type is FunctionType ? _functionName(type) : '';
}

String _basicName(int kind) {
  if (kind == dynamicKind) return 'dynamic';
  if (kind == voidKind) return 'void';
  if (kind == anyKind) return 'Object?';
  if (kind == objectKind) return 'Object';
  return kind == nullKind ? 'Null' : 'Never';
}

String _listName(TypeList list) {
  var name = typeName(list.head);
  for (var at = list.tail; at != null; at = at.tail) {
    name = '$name, ${typeName(at.head)}';
  }
  return name;
}

String _functionName(FunctionType type) {
  final required = type.required, optional = type.optional, named = type.named;
  var parameters = required == null ? '' : _listName(required);
  if (optional != null) {
    if (required != null) parameters = '$parameters, ';
    parameters = '$parameters[${_listName(optional)}]';
  }
  if (named != null) {
    if (required != null) parameters = '$parameters, ';
    parameters = '$parameters{${_namedName(named)}}';
  }
  return '($parameters) => ${typeName(type.result)}';
}

String _namedName(NamedList list) {
  var name = '';
  for (NamedList? at = list; at != null; at = at.tail) {
    final own = '${typeName(at.type)} ${parameterName(at.name)}';
    name = '$name${at.isRequired ? 'required ' : ''}$own';
    if (at.tail != null) name = '$name, ';
  }
  return name;
}
