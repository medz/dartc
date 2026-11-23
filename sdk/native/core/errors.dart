// What the language itself throws.
import 'dart:_heap/objects.dart' show isSubclassOfError, throwWith;
import 'dart:_heap/type_objects.dart' show RuntimeType, TypeList;
import 'dart:_heap/types.dart' show objectTypeName, typeName;
import 'dart:_internal' show LateError, writeText;

Never _throwDivisionByZero() => throw const IntegerDivisionByZeroException();

Never _throwNegativeShift(int amount) => throw ArgumentError(amount);

Never _throwNotFinite() => throw UnsupportedError('Infinity or NaN toInt');

Never _throwNull() =>
    throw _CastError('Null check operator used on a null value');

Never _throwCast(Object? value, String type, String ending) =>
    throw _CastError(
      "type '${objectTypeName(value)}' is not a subtype of type "
      "'$type'$ending",
    );

Never _throwCastTo(Object? value, RuntimeType type, String ending) =>
    _throwCast(value, typeName(type), ending);

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

final class _CastError extends Error implements TypeError {
  final String _text;
  _CastError(this._text);
  String toString() => _text;
}

/// Notes where [error] is thrown, if it keeps that.
void _markThrown(Object error) {
  if (!isSubclassOfError(error)) return;
  final own = unsafeCast<Error>(error);
  if (own._stackTrace == null) own._stackTrace = StackTrace.empty;
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

/// Reports what ends the program.
void _reportUncaught(Object error) {
  writeText(2, 'Unhandled exception:', true);
  writeText(2, error.toString(), true);
}
