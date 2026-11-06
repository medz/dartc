import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

Object? _execute(Value Function(Block) build) {
  final block = Block();
  final result = build(block);
  block.finish(Return(result));
  final function = IrFunction(
    FunctionTarget(Uri.parse('memory:map-entry'), 'test', result.type, []),
    [block],
  );
  return FixtureRunner(IrProgram([], [function]), {}).run(function, []);
}

void main() {
  const key = Constant.integer(1), value = Constant.string('value');
  final entryType = CoreTypes.mapEntryOf(ValueType.integer, ValueType.string);
  final constant = ObjectConstant(entryType, {
    CoreTypes.mapEntryKey: key,
    CoreTypes.mapEntryValue: value,
  });

  test(
    'MapEntry uses canonical generic fields and ordinary object constants',
    () {
      expect(entryType.dartName, 'MapEntry<int, String>');
      expect(CoreTypes.mapEntry.isAbstract, isFalse);
      expect(CoreTypes.mapEntryKey.typeFor(entryType), ValueType.integer);
      expect(CoreTypes.mapEntryValue.typeFor(entryType), ValueType.string);
      expect(CoreTypes.mapEntryKey.isFinal, isTrue);
      expect(CoreTypes.mapEntryValue.isFinal, isTrue);
      for (final (field, expected) in [
        (CoreTypes.mapEntryKey, 1),
        (CoreTypes.mapEntryValue, 'value'),
      ]) {
        expect(_execute((b) => b.emit(LoadField(field, constant))), expected);
      }
    },
  );

  test('MapEntry construction initializes the same field slots', () {
    final constructor = FunctionTarget(
      Uri.parse('dart:core'),
      'new',
      ValueType.voidType,
      CoreTypes.mapEntry.typeParameters,
      owner: CoreTypes.mapEntry,
      kind: FunctionKind.initializer,
    );
    expect(
      _execute((b) {
        final entry = b.emit(
          Construct(constructor, [key, value], instantiatedType: entryType),
        );
        return b.emit(LoadField(CoreTypes.mapEntryValue, entry));
      }),
      'value',
    );
  });

  test(
    'map spread protocol follows static arguments, not runtime source types',
    () {
      final narrow = NewCollection(
        CoreTypes.mapOf(ValueType.integer, ValueType.string),
      );
      final broad = NewCollection(
        CoreTypes.mapOf(ValueType.dynamicType, ValueType.dynamicType),
      );
      final nullable = NewCollection(
        CoreTypes.mapOf(ValueType.object.nullable, ValueType.object.nullable),
      );
      final keyOnly = NewCollection(
        CoreTypes.mapOf(ValueType.integer, ValueType.object.nullable),
      );
      final valueOnly = NewCollection(
        CoreTypes.mapOf(ValueType.object.nullable, ValueType.string),
      );
      expect(CollectionSpread(narrow, broad).checksMapEntries, isTrue);
      expect(CollectionSpread(keyOnly, broad).checksMapEntries, isTrue);
      expect(CollectionSpread(valueOnly, broad).checksMapEntries, isTrue);
      expect(CollectionSpread(narrow, narrow).checksMapEntries, isFalse);
      expect(CollectionSpread(nullable, broad).checksMapEntries, isFalse);
      expect(
        CollectionSpread(narrow, broad, isMethodCall: true).checksMapEntries,
        isFalse,
      );
      final parameter = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final generic = NewCollection(CoreTypes.mapOf(parameter, parameter));
      expect(CollectionSpread(generic, broad).checksMapEntries, isTrue);
      expect(CollectionSpread(generic, generic).checksMapEntries, isFalse);
    },
  );

  test('built-in map entries share MapEntry storage during checked spread', () {
    final source = MapConstant(
      CoreTypes.mapOf(ValueType.dynamicType, ValueType.dynamicType),
      [(key, value)],
    );
    expect(
      _execute((b) {
        final map = b.emit(
          NewCollection(CoreTypes.mapOf(ValueType.integer, ValueType.string)),
        );
        b.emit(CollectionSpread(map, source));
        return b.emit(CollectionGet(map, key));
      }),
      'value',
    );
  });
  test('entries getter retains actual generic arguments after widening', () {
    expect(
      _execute((b) {
        final map = b.emit(
          NewCollection(CoreTypes.mapOf(ValueType.integer, ValueType.string)),
        );
        final widened = b.emit(
          TypeView(
            map,
            CoreTypes.mapOf(ValueType.dynamicType, ValueType.dynamicType),
          ),
        );
        final entries = b.emit(MapEntries(widened));
        expect(entries.mayThrow, isTrue);
        return b.emit(TypeTest(entries, CoreTypes.iterableOf(entryType)));
      }),
      isTrue,
    );
    expect(() => MapEntries(key), throwsArgumentError);
  });

  test(
    'checked host maps and host MapEntry extraction use the same protocol',
    () {
      final sourceType = CoreTypes.mapOf(
        ValueType.dynamicType,
        ValueType.dynamicType,
      );
      final block = Block([sourceType]);
      final map = block.emit(
        NewCollection(CoreTypes.mapOf(ValueType.integer, ValueType.string)),
      );
      block.emit(CollectionSpread(map, block.parameters.single));
      block.finish(Return(block.emit(CollectionGet(map, key))));
      final function = IrFunction(
        FunctionTarget(
          Uri.parse('memory:map-entry'),
          'host',
          ValueType.string.nullable,
          [sourceType],
        ),
        [block],
      );
      final runner = FixtureRunner(IrProgram([], [function]), {});
      expect(
        runner.run(function, [
          <dynamic, dynamic>{1: 'value'},
        ]),
        'value',
      );
      expect(
        () => runner.run(function, [
          <dynamic, dynamic>{'wrong': 'value'},
        ]),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => runner.run(function, [
          <dynamic, dynamic>{1: 2},
        ]),
        throwsA(isA<TypeError>()),
      );
    },
  );
}
