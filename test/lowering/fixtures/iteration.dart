int checksum(List<int?> values) {
  var result = 0;
  for (final value in values) {
    result = result * 31 + (value ?? -1);
  }
  return result;
}

int constantHeaders() {
  var step = 0;
  final result = <int>[];
  for (const pair = (2, 3); step < 2; step++) {
    result.add(pair.$1 + pair.$2 + step);
  }
  step = 0;
  return checksum([
    ...result,
    for (const pair = (2, 3); step < 2; step++) pair.$1 + pair.$2 + step,
  ]);
}

int deferredHeaders() {
  var step = 0;
  final result = <int?>[];
  for (int? value; step < 1; step++) {
    value = 3;
    result.add(value);
  }
  step = 0;
  return checksum([
    ...result,
    for (int? value; step < 1; step++) (value = 4) + value,
  ]);
}

int updateCaptures(int limit) {
  final bodies = <int Function()>[];
  final updates = <int Function()>[];
  for (var i = 0; i < limit; updates.add(() => i), i++) {
    bodies.add(() => i);
    try {
      if (i == 1) continue;
      if (i == 3) break;
    } finally {
      bodies.add(() => i + 10);
    }
  }
  final collections = [
    for (var i = 0; i < limit; updates.add(() => i), i++) () => i,
  ];
  return checksum([
    for (final f in bodies) f(),
    for (final f in updates) f(),
    for (final f in collections) f(),
  ]);
}

int expressionAndPatternHeaders() {
  var i = -1;
  final result = [for (i = 0; i < 3; i++) i];
  for (var (a, b) = (0, 4); a < b; a++, b--) {
    result.add(a + b);
  }
  return checksum([
    ...result,
    for (var (a, b) = (0, 4); a < b; a++, b--) a + b,
  ]);
}

int nullableFinalHeaders() {
  var step = 0;
  // ignore: unused_local_variable
  for (final int? value; step < 2; step++) {}
  final result = [
    // ignore: unused_local_variable
    for (final int? value; step < 4; step++) step,
  ];
  return checksum(result);
}

int abruptHeaders(int failure) {
  var ticks = 0;
  try {
    final result = [
      for (
        var i = failure == 0 ? throw 10 : 0;
        failure == 1 ? throw 20 : i < 3;
        i = failure == 2 ? throw 30 : i + 1
      )
        ++ticks,
    ];
    return checksum(result);
  } on int catch (error) {
    return error + ticks;
  }
}
