// Exercise the operators directly, including comparisons with unrelated types.
// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_is_empty, unrelated_type_equality_checks

import 'dart:ffi';

import 'package:dartc/interop.dart';

String text(int kind) => switch (kind) {
  0 => '',
  1 => 'Dart',
  2 => 'A\u0000\u{1F600}Z',
  _ => '\uD800\uDC00\uDFFF',
};

@Export<Int64 Function(Int64)>()
int stringLength(int kind) {
  final String? value = kind < 0 ? null : text(kind);
  return value?.length ?? -1;
}

int _generic<T extends String>(T value, int index) => value.codeUnitAt(index);

final class _Text(final String value);

@Export<Int64 Function(Int64, Int64)>()
int stringCodeUnits(int kind, int index) => text(kind).codeUnits[index];

List<int>? _savedUnits;

@Export<Int64 Function(Int64, Int64)>()
int stringUnitsState(int mode, int count) {
  final units = (String.fromCharCode(65) + '\u{1F600}').codeUnits;
  _savedUnits = units;
  for (var i = 0; i < count; i++) {
    _Text(String.fromCharCode(i & 0xffff));
  }
  try {
    switch (mode) {
      case 0:
        units[0] = 1;
      case 1:
        units.add(1);
      case 2:
        units.addAll(const <int>[]);
      case 3:
        units.length = units.length;
      case 4:
        units[-1];
      case 6:
        final List<num> numbers = units;
        numbers.add(1.5);
      case 7:
        final List<num> numbers = units;
        numbers.addAll(<num>[]);
    }
  } on UnsupportedError {
    return units[0];
  } on RangeError {
    return units.length;
  } on TypeError {
    return 2;
  }
  var result = 0;
  for (final unit in units) {
    result += unit;
  }
  return result;
}

@Export<Int64 Function(Int64)>()
int stringSavedUnit(int index) => _savedUnits![index];

@Export<
  Int64 Function(Pointer<Int64>, Int64, Int64, Int64, Pointer<Uint16>, Int64)
>()
int encodeCharacters(
  Pointer<Int64> input,
  int count,
  int start,
  int end,
  Pointer<Uint16> output,
  int capacity,
) {
  if (count < 0 || capacity < 0 || (count > 0 && input.address == 0)) return -1;
  try {
    final codes = <int>[for (var i = 0; i < count; i++) input[i]];
    final result = String.fromCharCodes(codes, start, end == -1 ? null : end);
    _saved = result;
    if (result.length > capacity) return -10 - result.length;
    if (result.length != 0 && output.address == 0) return -1;
    for (var i = 0; i < result.length; i++) {
      output[i] = result.codeUnitAt(i);
    }
    return result.length;
  } on ArgumentError {
    return -2;
  }
}

int _codesTrace = 0;

final class _Codes(final int failure) extends Iterable<int> {
  @override
  Iterator<int> get iterator {
    _codesTrace = _codesTrace * 10 + 1;
    return _CodeIterator(failure);
  }
}

final class _CodeIterator(final int failure) implements Iterator<int> {
  int index = 0;
  @override
  bool moveNext() {
    _codesTrace = _codesTrace * 10 + 2;
    if ((failure == 1 || failure == 3) && index == 1) {
      throw StateError('moveNext');
    }
    return index++ < 2;
  }

  @override
  int get current {
    _codesTrace = _codesTrace * 10 + 3;
    if (failure == 2 && index == 2) throw StateError('current');
    return failure >= 3 ? -1 : (index == 1 ? 0x41 : 0x1f600);
  }
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int stringCodesProtocol(int start, int end, int failure) {
  _codesTrace = 0;
  try {
    final construct = String.fromCharCodes;
    _saved = construct(_Codes(failure), start, end == -1 ? null : end);
  } on StateError {
    _codesTrace = _codesTrace * 10 + 4;
  } on ArgumentError {
    _codesTrace = _codesTrace * 10 + 5;
  } finally {
    _codesTrace = _codesTrace * 10 + 6;
  }
  return _codesTrace;
}

@Export<Int64 Function(Int64, Int64, Int64, Int64)>()
int stringRead(int kind, int index, int mode, int count) {
  var value = text(kind);
  final read = value.codeUnitAt;
  num Function(int) widened = read;
  for (var i = 0; i < count; i++) {
    value = _Text(value).value;
  }
  return switch (mode) {
    0 => value.codeUnitAt(index),
    1 => read(index),
    2 => _generic(value, index),
    _ => widened(index) as int,
  };
}

final class _Order() {
  int log = 0;
  String receiver(int kind) {
    log = log * 10 + 1;
    return text(kind) + '';
  }

  int index(int value) {
    log = log * 10 + 2;
    return value;
  }
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int stringFailure(int kind, int index, int bound) {
  final order = _Order();
  try {
    if (bound == 0) {
      order.receiver(kind).codeUnitAt(order.index(index));
    } else if (bound == 1) {
      final read = order.receiver(kind).codeUnitAt;
      read(order.index(index));
    } else {
      order.receiver(kind)[order.index(index)];
    }
    return -1;
  } on RangeError catch (error) {
    if (error.invalidValue != index ||
        error.start != 0 ||
        error.end != text(kind).length - 1) {
      return -2;
    }
    order.log = order.log * 10 + 3;
  } finally {
    order.log = order.log * 10 + 4;
  }
  return order.log;
}

@Export<Int64 Function(Int64, Int64, Int64)>()
int stringConstruct(int code, int index, int bound) {
  final make = String.fromCharCode;
  final string = bound == 0 ? String.fromCharCode(code) : make(code);
  final unit = string[index];
  final Object a = string, b = String.fromCharCode(code);
  if (a != b) return -11;
  if (a.hashCode != b.hashCode) return -12;
  if (string != b) return -13;
  if (string == code) return -14;
  if (string.hashCode != b.hashCode) return -15;
  if (unit.length != 1) return -16;
  if (unit.codeUnitAt(0) != string.codeUnitAt(index)) return -17;
  final empty = text(0) + text(0);
  if (string.runtimeType != String || String.fromCharCode(0x61) != 'a') {
    return -3;
  }
  if (empty != '' || empty.hashCode != ''.hashCode || empty.length != 0) {
    return -2;
  }
  return string.length * 0x10000 + unit.codeUnitAt(0);
}

String? _saved;

@Export<Int64 Function(Int64)>()
int stringSaved(int index) =>
    _saved!.length * 0x10000 + _saved!.codeUnitAt(index);

@Export<Int64 Function(Int64, Int64, Int64)>()
int stringGrowth(int code, int rounds, int count) {
  var value = String.fromCharCode(code);
  var twin = String.fromCharCode(code);
  for (var i = 0; i < rounds; i++) {
    value = value + value;
    twin = twin + twin;
  }
  final read = value.codeUnitAt;
  final hash = value.hashCode;
  _saved = value;
  var observed = 0;
  for (var i = 0; i < count; i++) {
    final allocated = String.fromCharCode(i & 0xffff) + '\u0000';
    observed += allocated.codeUnitAt(0);
  }
  final Object other = twin;
  if (_saved != other ||
      value != twin ||
      value.hashCode != hash ||
      other.hashCode != hash ||
      ('' + value) != (value + '') ||
      value == (twin + 'x') ||
      observed != count * (count - 1) ~/ 2) {
    return -1;
  }
  return value.length * 0x100000000 +
      read(0) * 0x10000 +
      read(value.length - 1);
}

@Export<Int64 Function(Int64, Int64)>()
int stringInvalidCode(int code, int bound) {
  final order = _Order();
  try {
    final make = String.fromCharCode;
    if (bound == 0) {
      String.fromCharCode(order.index(code));
    } else {
      make(order.index(code));
    }
    return -1;
  } on RangeError catch (error) {
    if (error.invalidValue != code ||
        error.start != 0 ||
        error.end != 0x10ffff) {
      return -2;
    }
    order.log = order.log * 10 + 3;
  } finally {
    order.log = order.log * 10 + 4;
  }
  return order.log;
}
