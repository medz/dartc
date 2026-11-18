import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'module native data owns immutable bytes and distinct declaration identity',
    () {
      final bytes = [1, 2, 3];
      final data = NativeData(bytes, alignment: 8);
      bytes[0] = 99;
      expect(data.bytes, [1, 2, 3]);
      expect(() => data.bytes[0] = 99, throwsUnsupportedError);
      expect(
        () => data.bytes.buffer.asUint8List()[0] = 99,
        throwsUnsupportedError,
      );
      expect(NativeData([1, 2, 3], alignment: 8), isNot(same(data)));
      for (final bytes in [
        <int>[],
        [-1],
        [256],
      ]) {
        expect(() => NativeData(bytes), throwsArgumentError);
      }
      for (final alignment in [-1, 0, 3, 7]) {
        expect(
          () => NativeData([0], alignment: alignment),
          throwsArgumentError,
        );
      }
    },
  );

  test('native addresses retain data identity through graph copying', () {
    final data = NativeData([0, 1], alignment: 2, writable: false);
    final address = NativeDataAddress(data);
    final copy = address.mapInputs(
      (_) => throw StateError('No operands'),
    ) as NativeDataAddress;
    expect(copy.declaration, same(data));
    expect(copy.type, ValueType.integer);
    expect(copy.inputs, isEmpty);
    expect(copy.effects, isEmpty);
    expect(copy.mayThrow, isFalse);
    final target = FunctionTarget(null, 'dataAddress', .integer, []);
    expect(
      () => IrFunction(target, [Block()..finish(Return(address))]),
      throwsStateError,
    );
    final entry = Block();
    entry.emit(address);
    entry.finish(Return(entry.emit(copy)));
    final body = IrFunction(target, [entry]);
    IrProgram([], [body]);
    final text = StringBuffer();
    body.writeTo(text);
    expect(
      text.toString(),
      contains('nativeData0 bytes=2 align=2 writable=false'),
    );
    expect(text.toString(), isNot(contains('nativeData1')));
    expect(body.observesCallerFrame, isFalse);
  });
}
