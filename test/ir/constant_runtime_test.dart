import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

Object? _execute(
  Value Function(Block) build, [
  List<IrClass> classes = const [],
]) {
  final block = Block();
  final result = build(block);
  block.finish(Return(result));
  final function = IrFunction(
    FunctionTarget(
      Uri.parse('memory:constant-runtime'),
      'test',
      result.type,
      [],
    ),
    [block],
  );
  return IrInterpreter(IrProgram(classes, [function]), {}).run(function, []);
}

final _identical = FunctionTarget(
  Uri.parse('dart:core'),
  'identical',
  .boolean,
  [ValueType.object.nullable, ValueType.object.nullable],
);

void main() {
  const zero = Constant.integer(0), one = Constant.integer(1);
  const wrong = Constant.string('wrong');
  final listType = CoreTypes.listOf(ValueType.integer);
  final setType = CoreTypes.setOf(ValueType.integer);
  final mapType = CoreTypes.mapOf(ValueType.integer, ValueType.integer);
  final list = SequenceConstant(listType, [one]);
  final set = SequenceConstant(setType, [one]);
  final map = MapConstant(mapType, [(one, one)]);

  test(
    'constant aggregates canonicalize recursively across separate operands',
    () {
      Constant nested() => RecordConstant(RecordType([listType, mapType]), [
        SequenceConstant(listType, [one]),
        MapConstant(mapType, [(one, one)]),
      ]);
      expect(
        _execute((b) => b.emit(DirectCall(_identical, [nested(), nested()]))),
        isTrue,
      );
      expect(
        _execute(
          (b) => b.emit(
            DirectCall(_identical, [
              list,
              SequenceConstant(CoreTypes.listOf(ValueType.number), [one]),
            ]),
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'object canonicalization retains nominal field slots and actual type',
    () {
      final type = ClassType(Uri.parse('memory:constant-runtime'), 'Pair');
      final first = InstanceField(
        type,
        'first',
        ValueType.integer,
        isFinal: true,
      );
      final second = InstanceField(
        type,
        'second',
        ValueType.integer,
        isFinal: true,
      );
      final definition = IrClass(type, [first, second]);
      final a = ObjectConstant(type, {first: zero, second: one});
      final b = ObjectConstant(type, {second: one, first: zero});
      final c = ObjectConstant(type, {first: one, second: zero});
      expect(
        _execute((block) => block.emit(DirectCall(_identical, [a, b])), [
          definition,
        ]),
        isTrue,
      );
      expect(
        _execute((block) => block.emit(DirectCall(_identical, [a, c])), [
          definition,
        ]),
        isFalse,
      );
      expect(
        _execute((block) => block.emit(LoadField(second, a)), [definition]),
        1,
      );
    },
  );

  test('supported constant reads and iterators preserve contents', () {
    expect(_execute((b) => b.emit(CollectionLength(list))), 1);
    expect(_execute((b) => b.emit(CollectionGet(list, zero))), 1);
    expect(_execute((b) => b.emit(CollectionGet(map, one))), 1);
    expect(_execute((b) => b.emit(MapContainsKey(map, one))), isTrue);
    for (final sequence in [list, set]) {
      expect(
        _execute((b) {
          final iterator = b.emit(GetIterator(sequence));
          b.emit(IteratorMoveNext(iterator));
          return b.emit(IteratorCurrent(iterator));
        }),
        1,
      );
    }
  });

  test('constant sublist is new mutable storage', () {
    expect(
      _execute((b) {
        final copy = b.emit(ListSublist(list, zero));
        b.emit(ListSet(copy, zero, zero));
        b.emit(CollectionAdd(copy, one));
        return b.emit(CollectionLength(copy));
      }),
      2,
    );
    expect(_execute((b) => b.emit(CollectionGet(list, zero))), 1);
  });

  test('mutable addAll checks reified source type even when empty', () {
    for (final (type, source) in <(ClassType, Constant)>[
      (listType, SequenceConstant(CoreTypes.listOf(ValueType.number), [])),
      (setType, SequenceConstant(CoreTypes.listOf(ValueType.number), [])),
      (
        mapType,
        MapConstant(CoreTypes.mapOf(ValueType.number, ValueType.number), []),
      ),
    ]) {
      expect(
        () => _execute((b) {
          final collection = b.emit(NewCollection(type));
          b.emit(CollectionSpread(collection, source, isMethodCall: true));
          return b.emit(CollectionLength(collection));
        }),
        throwsA(isA<TypeError>()),
      );
    }
  });

  test('literal spreads retain per-element checks for dynamic sources', () {
    final source = SequenceConstant(CoreTypes.listOf(ValueType.dynamicType), [
      one,
    ]);
    for (final type in [listType, setType]) {
      expect(
        _execute((b) {
          final collection = b.emit(NewCollection(type));
          b.emit(CollectionSpread(collection, source));
          return b.emit(CollectionLength(collection));
        }),
        1,
      );
    }
    expect(
      _execute((b) {
        final collection = b.emit(NewCollection(mapType));
        b.emit(
          CollectionSpread(
            collection,
            MapConstant(
              CoreTypes.mapOf(ValueType.dynamicType, ValueType.dynamicType),
              [(one, one)],
            ),
          ),
        );
        return b.emit(CollectionGet(collection, one));
      }),
      1,
    );
  });

  test('constant writes check arguments before immutability and bounds', () {
    for (final operation in <Instruction>[
      CollectionAdd(list, one),
      CollectionAdd(set, one),
      MapPut(map, one, one),
      ListSet(list, const Constant.integer(99), one),
      CollectionSpread(
        list,
        SequenceConstant(listType, []),
        isMethodCall: true,
      ),
      CollectionSpread(set, SequenceConstant(listType, []), isMethodCall: true),
      CollectionSpread(map, MapConstant(mapType, []), isMethodCall: true),
    ]) {
      expect(
        () => _execute((b) {
          b.emit(operation);
          return zero;
        }),
        throwsUnsupportedError,
      );
    }
    for (final operation in <Instruction>[
      CollectionAdd(list, wrong),
      CollectionAdd(set, wrong),
      MapPut(map, wrong, one),
      MapPut(map, one, wrong),
      ListSet(list, const Constant.integer(99), wrong),
      CollectionSpread(
        list,
        SequenceConstant(CoreTypes.listOf(ValueType.string), []),
        isMethodCall: true,
      ),
      CollectionSpread(
        set,
        SequenceConstant(CoreTypes.listOf(ValueType.string), []),
        isMethodCall: true,
      ),
      CollectionSpread(
        map,
        MapConstant(CoreTypes.mapOf(ValueType.string, ValueType.string), []),
        isMethodCall: true,
      ),
    ]) {
      expect(
        () => _execute((b) {
          b.emit(operation);
          return zero;
        }),
        throwsA(isA<TypeError>()),
      );
    }
  });
}
