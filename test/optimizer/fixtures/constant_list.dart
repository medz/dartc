String read(int index) => const ['first', 'second'][index];

String checkedRead(int index) {
  try {
    return read(index);
  } on RangeError {
    return 'out of range';
  }
}

String nested() => const [
  ['first'],
  ['second'],
][1][0];

String fromCodes() => String.fromCharCodes(const [65, 0x1f642, 0xd800]);

int literalUnits() {
  const value = 'A\u{1f642}\ud800';
  return value.codeUnitAt(0) * 31 +
      value.codeUnitAt(1) * 7 +
      value.codeUnitAt(2) * 3 +
      value.codeUnitAt(3);
}

int createdLength() => String.fromCharCode(0x1f642).length;

int uniform(int index) {
  if (index < 0 || index >= 3) return -1;
  return const [7, 7, 7][index];
}
