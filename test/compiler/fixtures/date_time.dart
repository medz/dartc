void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

String describe(DateTime date) => [
  date.toIso8601String(),
  date.toString(),
  date.microsecondsSinceEpoch,
  date.millisecondsSinceEpoch,
  date.weekday,
  date.timeZoneName,
  date.timeZoneOffset.inSeconds,
  date.millisecond,
  date.microsecond,
].join('|');

void rangeError(void Function() action, String name, int value, int limit) {
  try {
    action();
    throw StateError('out-of-range timestamp accepted');
  } on RangeError catch (error) {
    check(
      error.name == name &&
          error.invalidValue == value &&
          error.start == -limit &&
          error.end == limit,
      'timestamp error payload',
    );
  }
}

void main(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == 'duration') {
    checkDurations();
    return;
  }
  final now = DateTime.now();
  final timestamp = DateTime.timestamp();
  print(now.microsecondsSinceEpoch);
  print(timestamp.microsecondsSinceEpoch);
  check(!now.isUtc && timestamp.isUtc, 'clock zone identity');
  check(
    DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true).toIso8601String() ==
        '1969-12-31T23:59:59.999999Z',
    'negative epoch fields',
  );
  check(
    DateTime.utc(1900, 2, 29) == DateTime.utc(1900, 3, 1) &&
        DateTime.utc(2000, 2, 29).day == 29 &&
        DateTime.utc(2100, 2, 29) == DateTime.utc(2100, 3, 1),
    'Gregorian leap centuries',
  );
  for (final micros in [
    -8640000000000000000,
    -2147483648000000,
    -1000001,
    -1000,
    -1,
    0,
    1,
    1234567,
    86400000000,
    946684800000000,
    1710053999000000,
    1710054000000000,
    1712415599000000,
    1712415600000000,
    1728142199000000,
    1728142200000000,
    1730613599000000,
    1730613600000000,
    2147483647000000,
    2147483648000000,
    8640000000000000000,
  ]) {
    final utc = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    final local = utc.toLocal();
    final again = local.toUtc();
    check(
      utc != local &&
          utc.isAtSameMomentAs(local) &&
          utc.compareTo(local) == 0 &&
          utc == again &&
          utc.hashCode == again.hashCode &&
          identical(utc, utc.toUtc()) &&
          identical(local, local.toLocal()),
      'instant and zone identity',
    );
    print(describe(utc));
    print(describe(local));
  }
  for (final fields in <List<int>>[
    [2000, 2, 29, 25, -61, 61, -1, 1001],
    [1900, 2, 29, 0, 0, 0, 0, 0],
    [2100, 2, 29, 0, 0, 0, 0, 0],
    [0, 13, 0, 0, 0, 0, 0, 0],
    [-1, -12, -40, 0, 0, 0, 0, 0],
    [10000, 1, 1, 0, 0, 0, 0, 0],
    [2024, 0, 40, 0, 0, 0, 0, 0],
    [2024, 25, -40, 0, 0, 0, 0, 0],
    [2024, 3, 10, 2, 30, 0, 0, 0],
    [2024, 11, 3, 1, 30, 0, 0, 0],
    [2024, 4, 7, 1, 45, 0, 0, 0],
    [2024, 10, 6, 2, 15, 0, 0, 0],
  ]) {
    for (final create in [DateTime.utc, DateTime.new]) {
      final date = create(
        fields[0],
        fields[1],
        fields[2],
        fields[3],
        fields[4],
        fields[5],
        fields[6],
        fields[7],
      );
      print(describe(date));
      print(describe(date.copyWith(month: 2, day: 30, microsecond: 1000)));
      print(describe(date.copyWith(isUtc: !date.isUtc)));
      final add = date.add;
      final advanced = add(const Duration(days: 1, microseconds: 1));
      check(
        advanced.difference(date).inMicroseconds == 86400000001 &&
            advanced.isAfter(date) &&
            date.isBefore(advanced) &&
            advanced.compareTo(date) == 1 &&
            advanced.subtract(const Duration(days: 1, microseconds: 1)) == date,
        'elapsed arithmetic',
      );
      print(describe(advanced));
    }
  }
  for (final isUtc in [false, true]) {
    for (final limit in [8640000000000000, 8640000000000000000]) {
      final create = limit == 8640000000000000
          ? DateTime.fromMillisecondsSinceEpoch
          : DateTime.fromMicrosecondsSinceEpoch;
      final name = limit == 8640000000000000
          ? 'millisecondsSinceEpoch'
          : 'microsecondsSinceEpoch';
      for (final sign in [-1, 1]) {
        rangeError(
          () => create(sign * (limit + 1), isUtc: isUtc),
          name,
          sign * (limit + 1),
          limit,
        );
        check(
          create(sign * limit, isUtc: isUtc).microsecondsSinceEpoch ==
              sign * 8640000000000000000,
          'inclusive timestamp boundary',
        );
      }
    }
  }
  for (final sign in [-1, 1]) {
    final date = DateTime.fromMicrosecondsSinceEpoch(
      sign * 8640000000000000000,
    );
    rangeError(
      () => date.add(Duration(microseconds: sign)),
      'microsecondsSinceEpoch',
      sign * 8640000000000000001,
      8640000000000000000,
    );
  }
  final dynamic construct = DateTime.fromMicrosecondsSinceEpoch;
  try {
    construct('0');
    throw StateError('dynamic timestamp accepted');
  } on TypeError {
    // The constructor function value retains its int parameter contract.
  }
  final retained = DateTime(2024, 3, 10, 1, 30);
  final before = describe(retained);
  var sum = 0;
  for (var i = 0; i < 5000; i++) {
    sum += DateTime.utc(2000, 1, 1, 0, 0, 0, 0, i).microsecond;
  }
  check(
    sum == 2497500 && describe(retained) == before,
    'cached fields survive GC',
  );
  print('date_time:ok');
}

void checkDurations() {
  const mixed = Duration(
    days: 2,
    hours: -25,
    minutes: 61,
    seconds: -60,
    milliseconds: 1001,
    microseconds: -1,
  );
  const normalized = Duration(days: 1, seconds: 1, microseconds: 999);
  final construct = Duration.new;
  final copy = construct(microseconds: mixed.inMicroseconds);
  check(
    mixed == normalized && mixed == copy && mixed.hashCode == copy.hashCode,
    'mixed units and runtime constructor',
  );
  check(
    const Duration(microseconds: -1).inMilliseconds == 0 &&
        const Duration(microseconds: -1001).inMilliseconds == -1 &&
        (const Duration(microseconds: -3) ~/ 2).inMicroseconds == -1 &&
        (const Duration(microseconds: -3) * 0.5).inMicroseconds == -2 &&
        (const Duration(microseconds: 3) * 0.5).inMicroseconds == 2,
    'truncation and multiplication rounding',
  );
  check(
    const Duration(microseconds: -1).toString() == '-0:00:00.000001' &&
        const Duration(hours: 25, minutes: 3, microseconds: 9).toString() ==
            '25:03:00.000009',
    'duration formatting',
  );
  final keys = <Duration, String>{mixed: 'first', copy: 'replacement'};
  check(keys.length == 1 && keys[normalized] == 'replacement', 'duration keys');
  for (final micros in [
    -0x8000000000000000,
    -9007199254740993,
    -86400000001,
    -3600000001,
    -60000001,
    -1000001,
    -1001,
    -1,
    0,
    1,
    999,
    1001,
    1000001,
    60000001,
    3600000001,
    86400000001,
    9007199254740993,
    0x7fffffffffffffff,
  ]) {
    final duration = construct(microseconds: micros);
    final format = duration.toString;
    final absolute = duration.abs;
    print(
      '${format()}|${duration.inDays}/${duration.inHours}/'
      '${duration.inMinutes}/${duration.inSeconds}/${duration.inMilliseconds}/'
      '${duration.inMicroseconds}|${duration.isNegative}/'
      '${absolute().inMicroseconds}/${(-duration).inMicroseconds}',
    );
    final compare = duration.compareTo;
    for (final other in [Duration.zero, mixed, -mixed, duration]) {
      print(
        '${(duration + other).inMicroseconds}/'
        '${(duration - other).inMicroseconds}/'
        '${compare(other)}/${duration == other}/'
        '${duration < other}/${duration <= other}/'
        '${duration > other}/${duration >= other}',
      );
    }
    for (final factor in <num>[0, 1, -1, 2, 0.5, -0.5, 1.25, 1 / 3]) {
      print((duration * factor).inMicroseconds);
    }
    for (final quotient in [1, -1, 2, -2, 1000001]) {
      print((duration ~/ quotient).inMicroseconds);
    }
  }
  var rejected = 0;
  for (final factor in [double.nan, double.infinity, double.negativeInfinity]) {
    try {
      mixed * factor;
    } on UnsupportedError {
      rejected++;
    }
  }
  try {
    mixed ~/ 0;
  } on UnsupportedError {
    rejected++;
  }
  final dynamic dynamicConstructor = construct;
  final dynamic dynamicDuration = mixed;
  try {
    dynamicConstructor(seconds: '1');
  } on TypeError {
    rejected++;
  }
  try {
    dynamicDuration * '2';
  } on TypeError {
    rejected++;
  }
  try {
    dynamicDuration.compareTo(1);
  } on TypeError {
    rejected++;
  }
  check(rejected == 7, 'invalid duration arithmetic and arguments');
  print('duration:ok');
}
