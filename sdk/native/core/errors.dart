// What the language itself throws.
import 'dart:_heap/type_objects.dart' show RuntimeType;
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

Never _throwMissing(Object? object, String kind, String name) =>
    throw _MissingError(
      object == null
          ? "The $kind '$name' was called on null."
          : "Class '${objectTypeName(object)}' has no instance $kind '$name'.",
    );

final class _CastError extends Error implements TypeError {
  final String _text;
  _CastError(this._text);
  String toString() => _text;
}

final class _MissingError extends Error implements NoSuchMethodError {
  final String _text;
  _MissingError(this._text);
  Object? get _receiver => null;
  Invocation get _invocation => throw this;
  String toString() => 'NoSuchMethodError: $_text';
}

/// Reports what ends the program.
void _reportUncaught(Object error) {
  writeText(2, 'Unhandled exception:', true);
  writeText(2, error.toString(), true);
}
