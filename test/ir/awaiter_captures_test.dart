import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final root = FunctionTarget(null, 'root', .voidType, []);
  final cell = CellType(.object);
  FunctionTarget closure(int? slot, {List<ValueType>? captures}) =>
      FunctionTarget(
        null,
        'callback',
        .voidType,
        [],
        kind: .closure,
        enclosing: root,
        sourceOffset: 0,
        captures: captures ?? [.string, cell],
        awaiterCapture: slot,
      );

  test('awaiter metadata preserves the existing capture and entry layouts', () {
    final target = closure(1);
    expect(target.awaiterCapture, 1);
    expect(target.captures, [ValueType.string, cell]);
    expect(target.parameterTypes, [target.signature, ValueType.string, cell]);
    expect(closure(null).awaiterCapture, isNull);
  });

  test('awaiter indices must belong to a lexical capture list', () {
    for (final slot in [-1, 2]) {
      expect(() => closure(slot), throwsArgumentError);
    }
    expect(() => closure(0, captures: []), throwsArgumentError);
    expect(
      () => FunctionTarget(null, 'ordinary', .voidType, [], awaiterCapture: 0),
      throwsArgumentError,
    );
  });
}
