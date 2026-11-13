int milliseconds(int millis) => DateTime.fromMillisecondsSinceEpoch(
  millis,
  isUtc: true,
).microsecondsSinceEpoch;

int compare(int first, int second) {
  final a = DateTime.fromMicrosecondsSinceEpoch(first, isUtc: true);
  final b = DateTime.fromMicrosecondsSinceEpoch(second, isUtc: true);
  return a.compareTo(b) * 100 +
      (a.isBefore(b) ? 10 : 0) +
      (a.isAfter(b) ? 1 : 0);
}

bool identity(int micros) {
  final utc = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  final local = utc.toLocal();
  final again = local.toUtc();
  return utc != local &&
      utc.isAtSameMomentAs(local) &&
      utc.compareTo(local) == 0 &&
      utc == again &&
      utc.hashCode == again.hashCode &&
      identical(utc, utc.toUtc()) &&
      identical(local, local.toLocal());
}

Object validation(int value, bool micros) {
  try {
    final date = micros
        ? DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    return date.microsecondsSinceEpoch;
  } on RangeError catch (error) {
    final max = micros ? 8640000000000000000 : 8640000000000000;
    if (error.invalidValue != value ||
        error.start != -max ||
        error.end != max ||
        error.name !=
            (micros ? 'microsecondsSinceEpoch' : 'millisecondsSinceEpoch')) {
      throw StateError('RangeError payload');
    }
    return 'range';
  }
}
