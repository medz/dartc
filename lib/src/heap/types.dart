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

/// Writes the type of [object] to standard error.
void writeObjectType(Object? object) =>
    writeType(object == null ? const BasicType(nullKind) : typeOf(object));

/// Writes [type] to standard error.
void writeType(RuntimeType type) {
  if (type is BasicType) {
    writeBasicName(type.kind);
  } else if (type is InterfaceType) {
    writeClassName(type.number);
    if (type.arguments != null) {
      writeError(60);
      _writeList(type.arguments);
      writeError(62);
    }
  } else if (type is NullableType) {
    final inner = type.inner;
    if (inner is FunctionType) writeError(40);
    writeType(inner);
    if (inner is FunctionType) writeError(41);
    writeError(63);
  } else if (type is FunctionType) {
    _writeFunction(type);
  }
}

void _writeList(TypeList? list) {
  for (var at = list; at != null; at = at.tail) {
    writeType(at.head);
    if (at.tail != null) _writeComma();
  }
}

void _writeComma() {
  writeError(44);
  writeError(32);
}

void _writeFunction(FunctionType type) {
  writeError(40);
  _writeList(type.required);
  if (type.optional != null) {
    if (type.required != null) _writeComma();
    writeError(91);
    _writeList(type.optional);
    writeError(93);
  }
  if (type.named != null) {
    if (type.required != null) _writeComma();
    writeError(123);
    for (var at = type.named; at != null; at = at.tail) {
      if (at.isRequired) writeRequired();
      writeType(at.type);
      writeError(32);
      writeParameterName(at.name);
      if (at.tail != null) _writeComma();
    }
    writeError(125);
  }
  writeError(41);
  writeError(32);
  writeError(61);
  writeError(62);
  writeError(32);
  writeType(type.result);
}
