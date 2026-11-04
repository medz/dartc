import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test('core collection identities preserve covariant protocol arguments', () {
    final list = CoreTypes.listOf(ValueType.integer);
    expect(CoreTypes.iterableOf(ValueType.number).accepts(list), isTrue);
    expect(CoreTypes.listOf(ValueType.number).accepts(list), isTrue);
    expect(CoreTypes.listOf(ValueType.string).accepts(list), isFalse);
    expect(list.asInstanceOf(CoreTypes.iterable)!.typeArguments, [
      ValueType.integer,
    ]);
    expect(
      CoreTypes.mapOf(ValueType.integer, ValueType.string).dartName,
      'Map<int, String>',
    );
  });
  test('collection effects remain ordered throwing instructions', () {
    final list = NewCollection(CoreTypes.listOf(ValueType.integer));
    final map = NewCollection(
      CoreTypes.mapOf(ValueType.integer, ValueType.string),
    );
    const key = Constant.integer(1), value = Constant.string('v');
    final iterator = GetIterator(list);
    final effects = <Instruction>[
      list,
      map,
      CollectionAdd(list, key),
      CollectionSpread(list, list),
      MapPut(map, key, value),
      iterator,
      IteratorMoveNext(iterator),
      IteratorCurrent(iterator),
      CollectionLength(list),
      CollectionGet(map, key),
      ListSet(list, key, key),
    ];
    expect(effects.every((op) => op.mayThrow), isTrue);
    expect(IteratorCurrent(iterator).type, ValueType.integer);
    expect(CollectionGet(map, key).type, ValueType.string.nullable);
    // Source typing may widen a reference; writes must still check the actual
    // reified receiver at runtime instead of rejecting the narrower SSA operand.
    expect(CollectionAdd(list, const Constant.floating(1.5)).mayThrow, isTrue);
  });
  test(
    'collection instructions reject storage and invalid receiver protocols',
    () {
      final list = NewCollection(CoreTypes.listOf(ValueType.integer));
      final cell = NewCell(
        CellType(ValueType.integer),
        const Constant.integer(1),
      );
      expect(() => NewCollection(ValueType.integer), throwsArgumentError);
      expect(() => GetIterator(const Constant.integer(1)), throwsArgumentError);
      expect(() => IteratorCurrent(list), throwsArgumentError);
      expect(() => CollectionAdd(list, cell), throwsArgumentError);
      expect(
        () => CollectionGet(list, const Constant.string('x')),
        throwsArgumentError,
      );
      expect(
        () => CollectionSpread(list, const Constant.integer(1)),
        throwsArgumentError,
      );
    },
  );
}
