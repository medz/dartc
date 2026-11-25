import 'dart:io';

void main() {
  print('é😀\uD800|\uDC00 \x00\r');
  // expect: "é😀�|� \u0000\r"
  // expect:
  // expect: b
  print('');
  print('b');
  exit(3);
}
// exit: 3
