import '../../runtime.dart' show rtObjectToString;
import '../../runtime/exceptions.dart' show rtRaiseException;

class Error {
  // The runtime fills this field on the first throw of an actual subclass.
  final StackTrace? stackTrace = null;

  Error();

  static String safeToString(Object? object) {
    if (object == null || object is num || object is bool)
      return object.toString();
    if (object is String) return _quotedString(object);
    if (object is List) return "Instance(length:${object.length}) of 'List'";
    if (object is Function) return 'Closure';
    return rtObjectToString(object);
  }

  static Never throwWithStackTrace(Object error, StackTrace stackTrace) =>
      rtRaiseException(error, stackTrace);
}

String _quotedString(String text) {
  const hex = '0123456789abcdef';
  final units = <int>[34];
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    var escape = 0;
    if (unit == 34 || unit == 92) escape = unit;
    if (unit == 8) escape = 98;
    if (unit == 9) escape = 116;
    if (unit == 10) escape = 110;
    if (unit == 12) escape = 102;
    if (unit == 13) escape = 114;
    if (escape != 0) {
      units.add(92);
      units.add(escape);
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      units.add(unit);
      units.add(text.codeUnitAt(++i));
    } else if (unit < 32 || unit >= 0xd800 && unit <= 0xdfff) {
      units.add(92);
      units.add(117);
      units.add(hex.codeUnitAt((unit >> 12) & 15));
      units.add(hex.codeUnitAt((unit >> 8) & 15));
      units.add(hex.codeUnitAt((unit >> 4) & 15));
      units.add(hex.codeUnitAt(unit & 15));
    } else {
      units.add(unit);
    }
  }
  units.add(34);
  return String.fromCharCodes(units);
}

class AssertionError extends Error {
  final Object? message;

  AssertionError([this.message]);

  String toString() => message == null
      ? 'Assertion failed'
      : 'Assertion failed: ${Error.safeToString(message)}';
}

class TypeError extends Error {}

class ArgumentError extends Error {
  final bool _hasValue;
  final dynamic invalidValue;
  final String? name;
  final dynamic message;

  ArgumentError([this.message, this.name])
    : invalidValue = null,
      _hasValue = false;

  ArgumentError.value(value, [this.name, this.message])
    : invalidValue = value,
      _hasValue = true;

  ArgumentError.notNull([this.name])
    : invalidValue = null,
      message = 'Must not be null',
      _hasValue = false;

  static T checkNotNull<T>(T? argument, [String? name]) =>
      argument ?? (throw ArgumentError.notNull(name));

  String get _errorName =>
      _hasValue ? 'Invalid argument' : 'Invalid argument(s)';
  String get _errorExplanation => '';

  String toString() {
    final parameter = name == null ? '' : ' ($name)';
    final detail = message == null ? '' : ': $message';
    final prefix = '$_errorName$parameter$detail';
    if (!_hasValue) return prefix;
    return '$prefix$_errorExplanation: ${Error.safeToString(invalidValue)}';
  }
}

class RangeError extends ArgumentError {
  final num? start;
  final num? end;

  num? get invalidValue => super.invalidValue;

  RangeError(message) : start = null, end = null, super(message);

  RangeError.value(num value, [String? name, String? message])
    : start = null,
      end = null,
      super.value(value, name, message ?? 'Value not in range');

  RangeError.range(
    num invalidValue,
    int? minValue,
    int? maxValue, [
    String? name,
    String? message,
  ]) : start = minValue,
       end = maxValue,
       super.value(invalidValue, name, message ?? 'Invalid value');

  static int checkValueInInterval(
    int value,
    int minValue,
    int maxValue, [
    String? name,
    String? message,
  ]) {
    if (value < minValue || value > maxValue)
      throw RangeError.range(value, minValue, maxValue, name, message);
    return value;
  }

  static int checkValidRange(
    int start,
    int? end,
    int length, [
    String? startName,
    String? endName,
    String? message,
  ]) {
    if (start < 0 || start > length)
      throw RangeError.range(start, 0, length, startName ?? 'start', message);
    if (end != null) {
      if (end < start || end > length)
        throw RangeError.range(end, start, length, endName ?? 'end', message);
      return end;
    }
    return length;
  }

  static int checkNotNegative(int value, [String? name, String? message]) {
    if (value < 0)
      throw RangeError.range(value, 0, null, name ?? 'index', message);
    return value;
  }

  String get _errorName => 'RangeError';

  String get _errorExplanation {
    final lower = start;
    final upper = end;
    if (lower == null)
      return upper == null ? '' : ': Not less than or equal to $upper';
    if (upper == null) return ': Not greater than or equal to $lower';
    if (upper > lower) return ': Not in inclusive range $lower..$upper';
    if (upper < lower) return ': Valid value range is empty';
    return ': Only valid value is $lower';
  }
}

class IndexError extends ArgumentError implements RangeError {
  final Object? indexable;
  final int length;

  IndexError.withLength(
    int invalidValue,
    this.length, {
    this.indexable,
    String? name,
    String? message,
  }) : super.value(invalidValue, name, message ?? 'Index out of range');

  int get invalidValue => super.invalidValue;
  int get start => 0;
  int get end => length - 1;
  String get _errorName => 'RangeError';

  String get _errorExplanation {
    if (invalidValue < 0) return ': index must not be negative';
    if (length == 0) return ': no indices are valid';
    return ': index should be less than $length';
  }

  static int check(
    int index,
    int length, {
    Object? indexable,
    String? name,
    String? message,
  }) {
    if (index < 0 || index >= length)
      throw IndexError.withLength(
        index,
        length,
        indexable: indexable,
        name: name ?? 'index',
        message: message,
      );
    return index;
  }
}

class UnsupportedError extends Error {
  final String? message;

  UnsupportedError(String this.message);

  String toString() => 'Unsupported operation: $message';
}

class UnimplementedError extends Error implements UnsupportedError {
  final String? message;

  UnimplementedError([this.message]);

  String toString() =>
      message == null ? 'UnimplementedError' : 'UnimplementedError: $message';
}

class StateError extends Error {
  final String message;

  StateError(this.message);

  String toString() => 'Bad state: $message';
}

class ConcurrentModificationError extends Error {
  final Object? modifiedObject;

  ConcurrentModificationError([this.modifiedObject]);

  String toString() => modifiedObject == null
      ? 'Concurrent modification during iteration.'
      : 'Concurrent modification during iteration: ${Error.safeToString(modifiedObject)}.';
}
