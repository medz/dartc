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
    return text(kind);
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
    } else {
      final read = order.receiver(kind).codeUnitAt;
      read(order.index(index));
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
