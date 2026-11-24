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

/// [inner] or a future of it.
RuntimeType futureOr(RuntimeType inner) {
  if (_isTop(inner) || _isKind(inner, objectKind)) return inner;
  if (_isKind(inner, neverKind)) return _futureOf(inner);
  if (_isKind(inner, nullKind)) return NullableType(_futureOf(inner));
  return FutureOrType(inner);
}

RuntimeType _futureOf(RuntimeType inner) =>
    InterfaceType(futureNumber(), TypeList(inner, null));

bool _isTop(RuntimeType type) => type is BasicType && type.kind <= anyKind;
bool _isKind(RuntimeType type, int kind) =>
    type is BasicType && type.kind == kind;

bool isSubtype(RuntimeType a, RuntimeType b) {
  if (isSame(a, b) || _isTop(b) || _isKind(a, neverKind)) return true;
  if (_isTop(a)) return false;
  if (_isKind(a, nullKind)) {
    return b is NullableType ||
        _isKind(b, nullKind) ||
        b is FutureOrType && isSubtype(a, b.inner);
  }
  if (a is FutureOrType) {
    return isSubtype(_futureOf(a.inner), b) && isSubtype(a.inner, b);
  }
  if (a is NullableType) {
    return isSubtype(const BasicType(nullKind), b) && isSubtype(a.inner, b);
  }
  if (b is FutureOrType) {
    return isSubtype(a, b.inner) || isSubtype(a, _futureOf(b.inner));
  }
  if (b is NullableType) return isSubtype(a, b.inner);
  if (b is BasicType) {
    return b.kind == objectKind || a is BasicType && a.kind == b.kind;
  }
  if (a is InterfaceType && b is InterfaceType) return _isSubclass(a, b);
  if (a is BoundType) return b is BoundType && a.index == b.index;
  if (a is RecordType) {
    if (b is InterfaceType) return b.number == recordNumber();
    return b is RecordType &&
        _haveSameShape(a, b) &&
        _areSubtypes(a.fields, b.fields);
  }
  if (a is GenericType) {
    if (b is GenericType) {
      return _areSame(a.bounds, b.bounds) && isSubtype(a.inner, b.inner);
    }
    return b is InterfaceType && b.number == functionNumber();
  }
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

bool _haveSameShape(RecordType a, RecordType b) {
  if (!isSame(a.names, b.names)) return false;
  var left = a.fields, right = b.fields;
  while (left != null && right != null) {
    left = left.tail;
    right = right.tail;
  }
  return left == null && right == null;
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
  if (type is FutureOrType) return futureOr(_substitute(type.inner, own));
  if (type is RecordType) {
    return RecordType(_substituteAll(type.fields, own), type.names);
  }
  if (type is GenericType) {
    final inner = _substitute(type.inner, own);
    final bounds = _substituteAll(type.bounds, own);
    return inner is FunctionType && bounds != null
        ? GenericType(bounds, inner)
        : type;
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
  if (a is NullableType) {
    return b is NullableType && isSameType(a.inner, b.inner);
  }
  if (a is InterfaceType) {
    return b is InterfaceType &&
        a.number == b.number &&
        _areSame(a.arguments, b.arguments);
  }
  if (a is BoundType) return b is BoundType && a.index == b.index;
  if (a is FutureOrType) {
    return b is FutureOrType && isSameType(a.inner, b.inner);
  }
  if (a is RecordType) {
    return b is RecordType &&
        isSame(a.names, b.names) &&
        _areSame(a.fields, b.fields);
  }
  if (a is GenericType) {
    return b is GenericType &&
        _areSame(a.bounds, b.bounds) &&
        isSameType(a.inner, b.inner);
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
  if (type is BoundType) return type.index + 11;
  if (type is FutureOrType) return hashOfType(type.inner) * 19 + 5;
  if (type is RecordType) {
    return (_hashOfList(type.fields) * 17 + type.names.length) & 0x3fffffff;
  }
  if (type is GenericType) {
    return (_hashOfList(type.bounds) * 13 + hashOfType(type.inner)) &
        0x3fffffff;
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

/// What the class of [object] is called.
String objectClassName(Object object) {
  final type = typeOf(object);
  return type is InterfaceType ? className(type.number) : '';
}

/// How many type parameters functions around have, and those around them.
final class _Binders {
  final int count, before;
  final _Binders? outer;
  _Binders(this.count, this.before, this.outer);
}

/// What [type] is called.
String typeName(RuntimeType type) => _typeName(type, null);

String _typeName(RuntimeType type, _Binders? binders) {
  if (type is BasicType) return _basicName(type.kind);
  if (type is InterfaceType) {
    final name = className(type.number), arguments = type.arguments;
    return arguments == null ? name : '$name<${_listName(arguments, binders)}>';
  }
  if (type is NullableType) {
    final inner = type.inner, name = _typeName(inner, binders);
    final isPlain = inner is! FunctionType && inner is! GenericType;
    return isPlain ? '$name?' : '($name)?';
  }
  if (type is BoundType) return _boundName(type.index, binders);
  if (type is GenericType) return _genericName(type, binders);
  if (type is RecordType) return _recordName(type, binders);
  if (type is FutureOrType) {
    return 'FutureOr<${_typeName(type.inner, binders)}>';
  }
  return type is FunctionType ? _functionName(type, binders) : '';
}

String _boundName(int index, _Binders? binders) {
  var rest = index;
  for (var at = binders; at != null; at = at.outer) {
    if (rest < at.count) return 'Y${at.before + rest}';
    rest -= at.count;
  }
  return 'Y$rest';
}

String _genericName(GenericType type, _Binders? outer) {
  var count = 0;
  for (TypeList? at = type.bounds; at != null; at = at.tail) {
    count++;
  }
  final before = outer == null ? 0 : outer.before + outer.count;
  final binders = _Binders(count, before, outer);
  var parameters = '', index = before;
  for (TypeList? at = type.bounds; at != null; at = at.tail) {
    final bound = _typeName(at.head, binders);
    final isTop = bound == 'Object?' || bound == 'dynamic';
    final comma = index == before ? '' : ', ';
    parameters = '$parameters${comma}Y$index${isTop ? '' : ' extends $bound'}';
    index++;
  }
  return '<$parameters>${_functionName(type.inner, binders)}';
}

String _basicName(int kind) {
  if (kind == dynamicKind) return 'dynamic';
  if (kind == voidKind) return 'void';
  if (kind == anyKind) return 'Object?';
  if (kind == objectKind) return 'Object';
  return kind == nullKind ? 'Null' : 'Never';
}

String _listName(TypeList list, _Binders? binders) {
  var name = _typeName(list.head, binders);
  for (var at = list.tail; at != null; at = at.tail) {
    name = '$name, ${_typeName(at.head, binders)}';
  }
  return name;
}

String _recordName(RecordType type, _Binders? binders) {
  var count = 0;
  for (var at = type.fields; at != null; at = at.tail) {
    count++;
  }
  final first = count - type.names.length;
  var text = '', index = 0;
  for (var at = type.fields; at != null; at = at.tail) {
    if (index > 0) text = '$text, ';
    if (index == first) text = '$text{';
    text = '$text${_typeName(at.head, binders)}';
    if (index >= first) text = '$text ${type.names[index - first]}';
    index++;
  }
  return type.names.isEmpty ? '($text)' : '($text})';
}

String _functionName(FunctionType type, _Binders? binders) {
  final required = type.required, optional = type.optional, named = type.named;
  var parameters = required == null ? '' : _listName(required, binders);
  if (optional != null) {
    if (required != null) parameters = '$parameters, ';
    parameters = '$parameters[${_listName(optional, binders)}]';
  }
  if (named != null) {
    if (required != null) parameters = '$parameters, ';
    parameters = '$parameters{${_namedName(named, binders)}}';
  }
  return '($parameters) => ${_typeName(type.result, binders)}';
}

String _namedName(NamedList list, _Binders? binders) {
  var name = '';
  for (NamedList? at = list; at != null; at = at.tail) {
    final own = '${_typeName(at.type, binders)} ${parameterName(at.name)}';
    name = '$name${at.isRequired ? 'required ' : ''}$own';
    if (at.tail != null) name = '$name, ';
  }
  return name;
}
