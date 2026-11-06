import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

Object? execute(Value Function(Block) build) {
  final block = Block();
  final result = build(block);
  block.finish(
    result.type == ValueType.never ? Unreachable(result) : Return(result),
  );
  final function = IrFunction(
    FunctionTarget(Uri.parse('memory:patterns'), 'test', result.type, []),
    [block],
  );
  return FixtureRunner(IrProgram([], [function]), {}).run(function, []);
}

void main() {
  const zero = Constant.integer(0), one = Constant.integer(1);
  test('pattern operations retain types, operands, and throwing effects', () {
    final list = NewCollection(CoreTypes.listOf(ValueType.integer));
    final map = NewCollection(
      CoreTypes.mapOf(ValueType.string, ValueType.integer),
    );
    final tail = ListSublist(list, zero);
    expect(tail.type, CoreTypes.listOf(ValueType.integer));
    expect(tail.inputs, [list, zero]);
    expect(ListSublist(list, zero, one).inputs, [list, zero, one]);
    expect(
      ListSublist(list, zero, const Constant.nullValue()).inputs.length,
      3,
    );
    final contains = MapContainsKey(map, const Constant.nullValue());
    expect(contains.type, ValueType.boolean);
    expect(contains.inputs, [map, const Constant.nullValue()]);
    final failure = PatternMatchFailure();
    expect(failure.type, ValueType.never);
    expect(failure.inputs, isEmpty);
    expect([tail, contains, failure].every((op) => op.mayThrow), isTrue);
    expect(ValueType.error.accepts(ValueType.stateError), isTrue);
  });

  test('invalid protocols, indices, and compiler storage are rejected', () {
    final list = NewCollection(CoreTypes.listOf(ValueType.integer));
    final map = NewCollection(
      CoreTypes.mapOf(ValueType.string, ValueType.integer),
    );
    final cell = NewCell(CellType(ValueType.integer), one);
    expect(() => ListSublist(map, zero), throwsArgumentError);
    expect(
      () => ListSublist(list, const Constant.nullValue()),
      throwsArgumentError,
    );
    expect(
      () => ListSublist(list, zero, const Constant.string('bad')),
      throwsArgumentError,
    );
    expect(() => ListSublist(list, cell), throwsArgumentError);
    expect(() => MapContainsKey(list, zero), throwsArgumentError);
    expect(() => MapContainsKey(map, cell), throwsArgumentError);
    final nullable = Block([list.type.nullable]).parameters.single;
    expect(() => ListSublist(nullable, zero), throwsArgumentError);
  });

  test(
    'sublist returns a fresh growable list and does not mutate its source',
    () {
      expect(
        execute((b) {
          final list = b.emit(
            NewCollection(CoreTypes.listOf(ValueType.integer)),
          );
          b.emit(CollectionAdd(list, one));
          final tail = b.emit(ListSublist(list, zero));
          b.emit(ListSet(tail, zero, const Constant.integer(2)));
          b.emit(CollectionAdd(tail, const Constant.integer(3)));
          return b.emit(CollectionGet(list, zero));
        }),
        1,
      );
    },
  );

  test('sublist retains actual reified element type after static widening', () {
    expect(
      () => execute((b) {
        final list = b.emit(NewCollection(CoreTypes.listOf(ValueType.integer)));
        b.emit(CollectionAdd(list, one));
        final widened = b.emit(
          TypeView(list, CoreTypes.listOf(ValueType.number)),
        );
        final tail = b.emit(ListSublist(widened, zero));
        return b.emit(CollectionAdd(tail, const Constant.floating(1.5)));
      }),
      throwsA(isA<TypeError>()),
    );
  });

  test(
    'map presence differs from nullable lookup and failure is a StateError',
    () {
      expect(
        execute((b) {
          final map = b.emit(
            NewCollection(
              CoreTypes.mapOf(ValueType.string, ValueType.integer.nullable),
            ),
          );
          b.emit(
            MapPut(
              map,
              const Constant.string('present'),
              const Constant.nullValue(),
            ),
          );
          return b.emit(MapContainsKey(map, const Constant.string('present')));
        }),
        isTrue,
      );
      expect(
        execute((b) {
          final map = b.emit(
            NewCollection(
              CoreTypes.mapOf(ValueType.string, ValueType.integer.nullable),
            ),
          );
          return b.emit(MapContainsKey(map, const Constant.string('absent')));
        }),
        isFalse,
      );
      expect(
        () => execute((b) => b.emit(PatternMatchFailure())),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Pattern matching error',
          ),
        ),
      );
    },
  );

  test('dynamic casts and tests accept reified collection wrappers', () {
    expect(
      execute((b) {
        final list = b.emit(NewCollection(CoreTypes.listOf(ValueType.integer)));
        final dynamic = b.emit(TypeCast(list, ValueType.dynamicType));
        return b.emit(TypeTest(dynamic, ValueType.dynamicType));
      }),
      isTrue,
    );
  });

  test(
    'sublist range failures propagate instead of fabricating an empty list',
    () {
      expect(
        () => execute((b) {
          final list = b.emit(
            NewCollection(CoreTypes.listOf(ValueType.integer)),
          );
          return b.emit(ListSublist(list, one));
        }),
        throwsRangeError,
      );
      expect(
        () => execute((b) {
          final list = b.emit(
            NewCollection(CoreTypes.listOf(ValueType.integer)),
          );
          return b.emit(ListSublist(list, zero, one));
        }),
        throwsRangeError,
      );
      expect(
        execute((b) {
          final list = b.emit(
            NewCollection(CoreTypes.listOf(ValueType.integer)),
          );
          final copy = b.emit(
            ListSublist(list, zero, const Constant.nullValue()),
          );
          return b.emit(CollectionLength(copy));
        }),
        0,
      );
    },
  );

  test(
    'pattern failure follows an exceptional edge and matches StateError',
    () {
      final entry = Block(), handler = Block([ValueType.object]);
      entry.finish(
        Invoke(
          PatternMatchFailure(),
          onReturn: null,
          onThrow: Jump(handler, [UnwindValue.exception]),
        ),
      );
      final matches = handler.emit(
        TypeTest(handler.parameters.single, ValueType.stateError),
      );
      handler.finish(Return(matches));
      final function = IrFunction(
        FunctionTarget(
          Uri.parse('memory:patterns'),
          'caught',
          ValueType.boolean,
          [],
        ),
        [entry, handler],
      );
      expect(
        FixtureRunner(IrProgram([], [function]), {}).run(function, []),
        isTrue,
      );
    },
  );

  test('formatting includes range arity and pattern failure', () {
    final b = Block();
    final list = b.emit(NewCollection(CoreTypes.listOf(ValueType.integer)));
    b.emit(ListSublist(list, zero));
    b.emit(ListSublist(list, zero, one));
    final map = b.emit(
      NewCollection(CoreTypes.mapOf(ValueType.string, ValueType.integer)),
    );
    b.emit(MapContainsKey(map, one));
    final failure = b.emit(PatternMatchFailure());
    b.finish(Unreachable(failure));
    final f = IrFunction(
      FunctionTarget(
        Uri.parse('memory:patterns'),
        'format',
        ValueType.never,
        [],
      ),
      [b],
    );
    final text = StringBuffer();
    f.writeTo(text);
    expect(text.toString(), contains('listSublist'));
    expect(text.toString(), contains('mapContainsKey'));
    expect(text.toString(), contains('patternMatchFailure'));
  });
}
