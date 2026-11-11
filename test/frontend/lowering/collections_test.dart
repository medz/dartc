import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/collections.dart' as sdk;

void main() {
  late IrProgram program;
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/frontend/lowering/fixtures/collections.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {});
    functions = {
      for (final f in program.functions)
        if (f.target.enclosing == null) f.target.name: f,
    };
  });
  Object? run(String name, [List<Object?> args = const []]) =>
      runner.run(functions[name]!, args);
  test('typed list elements, conditional and null-aware spreads', () {
    for (final choose in [false, true]) {
      for (final maybe in <int?>[null, 4]) {
        expect(
          run('literal', [choose, maybe, null]),
          sdk.literal(choose, maybe, null),
        );
      }
    }
  });
  test('set/map literals retain insertion and overwrite semantics', () {
    expect(run('setLiteral'), sdk.setLiteral());
    expect(run('mapLiteral', [null, 9]), sdk.mapLiteral(null, 9));
    expect(run('mapLiteral', [2, 9]), sdk.mapLiteral(2, 9));
    expect(run('mapNullOrder'), sdk.mapNullOrder());
    expect(run('equalityKeys'), sdk.equalityKeys());
  });
  test('redirecting SDK factories retain storage and initializer bodies', () {
    final entry = program.classes.singleWhere(
      (c) => c.type == CoreTypes.mapEntry,
    );
    expect(entry.fields, [CoreTypes.mapEntryKey, CoreTypes.mapEntryValue]);
    expect(
      program.implementationOf(entry.constructors['_']!),
      isA<IrFunction>(),
    );
    final mapped = program.classes.singleWhere(
      (c) =>
          c.type.library == Uri.parse('dart:_internal') &&
          c.type.name == 'MappedIterable',
    );
    expect(
      program.implementationOf(mapped.constructors['new']!),
      isA<IrFunction>(),
    );
  });
  test('iterator loops, pattern headers and per-iteration captures', () {
    expect(run('loopControl'), sdk.loopControl());
    expect(run('capturedLoop'), sdk.capturedLoop());
    expect(run('existingLoop'), sdk.existingLoop());
    expect(run('patternLoop'), sdk.patternLoop());
    expect(run('nestedCollection'), sdk.nestedCollection());
    expect(run('countedCollection'), sdk.countedCollection());
    expect(run('patternConditional'), sdk.patternConditional());
    expect(run('listUpdates'), sdk.listUpdates());
    expect(run('customIteration'), sdk.customIteration());
    expect(run('customMapSpread'), sdk.customMapSpread());
    expect(run('loopFinally'), sdk.loopFinally());
    expect(run('genericCollection'), sdk.genericCollection());
  });
  test('collection loop closures preserve fresh and reused bindings', () {
    expect(run('countedCollectionClosures'), sdk.countedCollectionClosures());
    expect(run('forInCollectionClosures'), sdk.forInCollectionClosures());
    expect(run('existingCollectionClosures'), sdk.existingCollectionClosures());
  });
  test(
    'iterator failures stop current, body and subsequent elements in order',
    () {
      for (final failure in [0, 1, 2, 3, 4]) {
        expect(
          run('collectionExceptionOrder', [failure]),
          sdk.collectionExceptionOrder(failure),
          reason: 'collection failure $failure',
        );
      }
      for (final failure in [0, 1, 2, 3]) {
        expect(
          run('spreadExceptionOrder', [failure]),
          sdk.spreadExceptionOrder(failure),
          reason: 'spread failure $failure',
        );
      }
    },
  );
  test('covariant writes and iterator mutation errors match the SDK', () {
    Object? observe(Object? Function() action) {
      try {
        action();
        return null;
      } catch (error) {
        return switch (error) {
          TypeError() => TypeError,
          ConcurrentModificationError() => ConcurrentModificationError,
          _ => error.runtimeType,
        };
      }
    }

    for (final (name, reference, expected)
        in <(String, Object? Function(), Type)>[
          ('aliasCheck', sdk.aliasCheck, TypeError),
          ('aliasSpreadCheck', sdk.aliasSpreadCheck, TypeError),
          ('mutation', sdk.mutation, ConcurrentModificationError),
        ]) {
      final sdkError = observe(reference);
      expect(sdkError, expected, reason: '$name SDK baseline');
      expect(
        observe(() => run(name)),
        sdkError,
        reason: '$name lowered exception',
      );
    }
  });
  for (final (file, type) in [
    ('collection_const_list.dart', CoreTypes.listOf(ValueType.integer)),
    ('collection_const_set.dart', CoreTypes.setOf(ValueType.integer)),
    (
      'collection_const_map.dart',
      CoreTypes.mapOf(ValueType.integer, ValueType.integer),
    ),
  ]) {
    test('retains a typed constant in $file', () async {
      final program = await AnalysisSession([
        'test/frontend/lowering/fixtures/$file',
      ]).use((input) async => (await Lowering().lower(input)).program);
      final function = program.functions.singleWhere(
        (function) => function.target.name == 'unsupportedCollection',
      );
      final result = (function.entry.end as Return).value;
      expect(result, anyOf(isA<SequenceConstant>(), isA<MapConstant>()));
      expect(result!.type, type);
    });
  }
}
