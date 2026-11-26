// What the language itself throws.
import 'dart:_heap/objects.dart' show isSubclassOfError, throwWith;
import 'dart:_heap/type_objects.dart' show RuntimeType, TypeList;
import 'dart:_heap/types.dart' show isSubtype, objectTypeName, typeName;
import 'dart:_internal' show LateError, writeText;

Never _throwDivisionByZero() => throw const IntegerDivisionByZeroException();

Never _throwNegativeShift(int amount) => throw ArgumentError(amount);

Never _throwNotFinite() => throw UnsupportedError('Infinity or NaN toInt');

Never _throwNull() =>
    throw _typeError('Null check operator used on a null value');

_TypeError _typeError(String message) => _TypeError._create('', 0, 0, message);

Never _throwCast(Object? value, String type, String ending) => throw _typeError(
  "type '${objectTypeName(value)}' is not a subtype of type "
  "'$type'$ending",
);

Never _throwCastTo(Object? value, RuntimeType type, String ending) =>
    _throwCast(value, typeName(type), ending);

/// Throws unless [type], which is given for the type parameter [name], is
/// within [bound].
void _checkBound(RuntimeType type, RuntimeType bound, String name) {
  if (isSubtype(type, bound)) return;
  throw _typeError(
    "type '${typeName(type)}' is not a subtype of type "
    "'${typeName(bound)}' of '$name'",
  );
}

Never _throwAssertion(
  String text,
  String uri,
  int line,
  int column,
  Object? message,
) => throw _AssertionError._create(text, uri, line, column, message);

Never _throwLate(String message) => throw LateError(message);

/// Calls the `noSuchMethod` of [receiver] for a method, a getter or a setter,
/// depending on [kind]. The last of [arguments] have [names].
Object? _missing(
  Object? receiver,
  int kind,
  String name,
  TypeList? types,
  List arguments,
  List names,
  String? found,
) {
  final count = arguments.length - names.length;
  final named = <Symbol, Object?>{};
  for (var i = 0; i < names.length; i++) {
    named[internal.Symbol.unvalidated(names[i])] = arguments[count + i];
  }
  final given = <Type>[];
  for (var at = types; at != null; at = at.tail) {
    given.add(_newType(at.head));
  }
  final invocation = _InvocationMirror._withType(
    internal.Symbol.unvalidated(name),
    kind,
    List.unmodifiable(given),
    List.unmodifiable(arguments.take(count)),
    Map.unmodifiable(named),
  );
  final isFunction = receiver is Function && kind != 2;
  invocation._found = isFunction ? objectTypeName(receiver) : found;
  return receiver.noSuchMethod(invocation);
}

@patch
class _InvocationMirror {
  /// What the member takes that is there, if any.
  String? _found;

  // The text of an error asks for these first.
  @patch
  List<Type> get typeArguments {
    NoSuchMethodError._found = _found;
    return _typeArguments!;
  }
}

@patch
class NoSuchMethodError {
  static String? _found;

  @patch
  static String? _existingMethodSignature(
    Object? receiver,
    String methodName,
    int invocationType,
  ) => _found;
}

/// Throws the error for a use of a member called [name], of [class_] if it is
/// of one, which is declared but not implemented. It is like one that takes
/// [found].
Never _throwExternal(Object? class_, String name, int type, String? found) {
  if (class_ is String) class_ = _NamedClass(class_);
  final invocation = _InvocationMirror._withType(
    internal.Symbol.unvalidated(name),
    type,
    const [],
    const [],
    const {},
  ).._found = found;
  throw NoSuchMethodError.withInvocation(class_, invocation);
}

/// A class that the program does not name, as a type in errors.
final class _NamedClass implements Type {
  final String _name;
  _NamedClass(this._name);
  String toString() => _name;
}

/// The trace of where [error] is thrown, which it keeps if it does that.
StackTrace _markThrown(Object error) {
  final trace = _traceHere();
  if (isSubclassOfError(error)) {
    final own = unsafeCast<Error>(error);
    if (own._stackTrace == null) own._stackTrace = trace;
  }
  return trace;
}

@patch
class Error {
  @patch
  static Never _throw(Object error, StackTrace stackTrace) {
    if (isSubclassOfError(error)) {
      final own = unsafeCast<Error>(error);
      if (own._stackTrace == null) own._stackTrace = stackTrace;
    }
    throwWith(error, stackTrace);
  }
}

/// Reports what ends the program, and where it was thrown.
void _reportUncaught(Object error, Object trace) {
  writeText(2, 'Unhandled exception:', true);
  writeText(2, error.toString(), true);
  writeText(2, trace.toString(), false);
}
