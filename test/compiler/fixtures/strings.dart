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
  if (a != b ||
      a.hashCode != b.hashCode ||
      string != b ||
      string == code ||
      string.hashCode != b.hashCode ||
      unit.length != 1 ||
      unit.codeUnitAt(0) != string.codeUnitAt(index)) {
    return -1;
  }
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
