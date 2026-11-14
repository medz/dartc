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
