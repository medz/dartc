import 'machine.dart';

/// Writes [value] to standard error.
void writeNumber(int value) {
  if (value < 0) {
    writeError(45);
    _writeDigits(value);
  } else {
    _writeDigits(-value);
  }
}

/// Writes [value], which is not positive, without its sign.
void _writeDigits(int value) {
  final rest = value ~/ 10;
  if (rest != 0) _writeDigits(rest);
  writeError(48 + rest * 10 - value);
}
