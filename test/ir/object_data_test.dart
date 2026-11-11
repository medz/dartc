import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('reference payload access retains object, offset and stored value', () {
    final block = Block([.object, .integer, .object.nullable]);
    final [object, offset, value] = block.parameters;
    final load = LoadObjectReference(object, offset);
    final store = StoreObjectReference(object, offset, value);
    expect(load.type, ValueType.object.nullable);
    expect(load.inputs, [object, offset]);
    expect(load.effects, {Effect.readsStorage});
    expect(store.inputs, [object, offset, value]);
    expect(store.effects, {Effect.writesStorage});
    expect(() => LoadObjectReference(value, offset), throwsArgumentError);
    expect(() => LoadObjectReference(offset, offset), throwsArgumentError);
    expect(
      () => StoreObjectReference(object, object, value),
      throwsArgumentError,
    );
    expect(
      () => StoreObjectReference(
        object,
        offset,
        NewCell(CellType(.integer), const Constant.integer(1)),
      ),
      throwsArgumentError,
    );
  });
}
