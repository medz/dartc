@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/descriptor_write_ffi.dart';

void main() {
  test('writes actual bytes and reports descriptor errors', () {
    final io = IoLibrary('descriptor_write');
    addTearDown(io.close);
    final descriptors = io.state.cast<Int32>();
    expect(io.pipe(descriptors), 0);
    final input = descriptors[0], output = descriptors[1];
    addTearDown(() {
      expect(io.closeDescriptor(input), 0);
      expect(io.closeDescriptor(output), 0);
    });
    const data = [0, 1, 127, 128, 255, 10];
    io.bytes.asTypedList(data.length).setAll(0, data);
    expect(io.write(output, io.bytes, data.length), data.length);
    expect(io.read(input, io.bytes + 64, data.length), data.length);
    expect((io.bytes + 64).asTypedList(data.length), data);
    expect(io.write(output, io.bytes, 0), 0);
    expect(io.write(input, io.bytes, data.length), -9);
    expect(io.write(-1, io.bytes, data.length), -9);
    expect(io.write(output + 0x100000000, io.bytes, data.length), -9);
    expect(io.write(output, io.bytes, -1), -22);
  });

  test('retries EINTR without repeating partial or failed writes', () {
    final io = IoLibrary('descriptor_write_scripted');
    addTearDown(io.close);
    for (final (result, error, interruptions, expected) in [
      (8, 0, 0, 8),
      (3, 0, 2, 3),
      (0, 0, 1, 0),
      (-1, 11, 0, -11),
      (-1, 35, 1, -35),
      (-1, 5, 2, -5),
    ]) {
      io.state.asTypedList(8).fillRange(0, 8, 0);
      io.state[1] = result;
      io.state[2] = interruptions;
      io.state[7] = error;
      expect(io.write(7, io.bytes + 2, 8), expected);
      expect(io.state[0], interruptions + 1);
      expect(io.state[3], 7);
      expect(io.state[4], (io.bytes + 2).address);
      expect(io.state[5], 8);
    }
    io.state[0] = 0;
    expect(io.write(-1, io.bytes, 8), -9);
    expect(io.write(0x100000007, io.bytes, 8), -9);
    expect(io.write(7, io.bytes, -1), -22);
    expect(io.state[0], 0);
  });
}
