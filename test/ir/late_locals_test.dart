import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _library = Uri.parse('memory:late_locals');

FunctionTarget _target(
  String name,
  ValueType result, [
  List<ValueType> parameters = const [],
]) => FunctionTarget(_library, name, result, parameters);

IrFunction _body(FunctionTarget target, void Function(Block) build) {
  final entry = Block(target.parameterTypes);
  build(entry);
  return IrFunction(target, [entry]);
}

Object _error(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  fail('Expected an error.');
}

({FixtureRunner runner, IrFunction create, IrFunction read, IrFunction write})
_fixture(
  CellType type, {
  Value? initial,
  IrFunction? initializer,
  Map<(Uri, String), Object? Function(int)> imports = const {},
}) {
  final pairType = RecordType([
    FunctionType(type.content, []),
    FunctionType(.voidType, [type.content]),
  ]);
  final createTarget = _target('create', pairType);
  final readTarget = FunctionTarget(
    _library,
    'read',
    type.content,
    [],
    kind: .closure,
    enclosing: createTarget,
    sourceOffset: 1,
    captures: [type],
  );
  final writeTarget = FunctionTarget(
    _library,
    'write',
    .voidType,
    [type.content],
    kind: .closure,
    enclosing: createTarget,
    sourceOffset: 2,
    captures: [type],
  );
  final create = _body(createTarget, (block) {
    final cell = block.emit(
      NewCell(
        type,
        initial,
        initializer: initializer == null
            ? null
            : FunctionConstant(initializer.target),
      ),
    );
    block.finish(
      Return(
        block.emit(
          MakeRecord(pairType, [
            block.emit(MakeClosure(readTarget, [cell])),
            block.emit(MakeClosure(writeTarget, [cell])),
          ]),
        ),
      ),
    );
  });
  final read = _body(_target('callRead', type.content, [pairType]), (block) {
    final function = block.emit(RecordGet(block.parameters.single, 0));
    block.finish(Return(block.emit(FunctionCall(function, []))));
  });
  final write = _body(
    _target('callWrite', .voidType, [pairType, type.content]),
    (block) {
      final function = block.emit(RecordGet(block.parameters.first, 1));
      block.emit(FunctionCall(function, [block.parameters.last]));
      block.finish(const Return());
    },
  );
  final program = IrProgram([], [
    create,
    read,
    write,
    _body(readTarget, (block) {
      block.finish(Return(block.emit(ReadCell(block.parameters[1]))));
    }),
    _body(writeTarget, (block) {
      block.emit(WriteCell(block.parameters[1], block.parameters.last));
      block.finish(const Return());
    }),
    ?initializer,
  ]);
  return (
    runner: FixtureRunner(program, imports),
    create: create,
    read: read,
    write: write,
  );
}

IrFunction _observedInitializer(ValueType type) => _body(
  _target('initialize', type),
  (block) => block.finish(
    Return(
      block.emit(
        DirectCall(_target('observe', type, [.integer]), [
          const Constant.integer(0),
        ]),
      ),
    ),
  ),
);

void main() {
  group('late cell metadata', () {
    test('ordinary identity, spelling and effects remain unchanged', () {
      final ordinary = CellType(.integer);
      final lateMutable = CellType(.integer, isLate: true);
      final lateFinal = CellType(.integer, isLate: true, isFinal: true);
      expect(ordinary, CellType(.integer));
      expect(ordinary.hashCode, Object.hash(CellType, ValueType.integer));
      expect(ordinary.dartName, 'cell<int>');
      expect(lateMutable.dartName, 'late cell<int>');
      expect(lateFinal.dartName, 'late final cell<int>');
      expect({ordinary, lateMutable, lateFinal}, hasLength(3));
      expect(ordinary.accepts(lateMutable), isFalse);
      expect(lateMutable.accepts(lateFinal), isFalse);
      expect(() => CellType(.integer, isFinal: true), throwsArgumentError);
      expect(() => CellType(ordinary, isLate: true), throwsArgumentError);
      for (final type in [ordinary, lateMutable, lateFinal]) {
        final cell = NewCell(type, null);
        expect(ReadCell(cell).mayThrow, type.isLate);
        expect(
          WriteCell(cell, const Constant.integer(1)).mayThrow,
          type.isFinal,
        );
        expect(CopyCell(cell).type, same(type));
      }
      final function = _body(_target('ordinary', .integer), (block) {
        final cell = block.emit(NewCell(ordinary, const Constant.integer(1)));
        block.finish(Return(block.emit(ReadCell(cell))));
      });
      final text = StringBuffer();
      function.writeTo(text);
      expect(text.toString(), contains('  %0 = cell 1\n'));
    });

    test('substitution preserves late final flags and type scope', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final original = CellType(t, isLate: true, isFinal: true);
      final changed = substituteType(original, {t: ValueType.integer});
      expect(changed, CellType(.integer, isLate: true, isFinal: true));
      expect(
        changed.hashCode,
        CellType(.integer, isLate: true, isFinal: true).hashCode,
      );
      expect(typeParametersIn(original), [t]);
      expect(typeParametersIn(changed), isEmpty);
      expect(substituteType(original, const {}), same(original));
      final target = _target('foreign', .voidType);
      expect(
        () => _body(target, (block) {
          block.emit(NewCell(original, null));
          block.finish(const Return());
        }),
        throwsStateError,
      );
    });

    test('lazy initializer is a compatible zero-argument function value', () {
      final type = CellType(.integer, isLate: true);
      final function = FunctionConstant(_target('initialize', .integer));
      final cell = NewCell(type, null, initializer: function);
      expect(cell.initial, isNull);
      expect(cell.initializer, same(function));
      expect(cell.inputs, [function]);
      expect(
        NewCell(
          type,
          null,
          initializer: FunctionConstant(_target('never', .never)),
        ).inputs,
        hasLength(1),
      );
      expect(
        () => NewCell(type, const Constant.integer(1), initializer: function),
        throwsArgumentError,
      );
      expect(
        () => NewCell(CellType(.integer), null, initializer: function),
        throwsArgumentError,
      );
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      for (final invalid in <Value>[
        const Constant.integer(1),
        NewCell(CellType(.integer), null),
        FunctionConstant(_target('wrongResult', .string)),
        FunctionConstant(_target('argument', .integer, [.integer])),
        FunctionConstant(
          FunctionTarget(
            _library,
            'generic',
            .integer,
            [],
            typeParameters: [t],
          ),
        ),
        Block([FunctionType(.integer, []).nullable]).parameters.single,
        Block([ValueType.function]).parameters.single,
        Block([
          FunctionType(.integer, [.integer], optionalPositional: 1),
        ]).parameters.single,
      ]) {
        expect(
          () => NewCell(type, null, initializer: invalid),
          throwsArgumentError,
        );
      }
    });

    test('lazy initializer operands participate in SSA verification', () {
      final target = _target('invalidOrder', .integer);
      final entry = Block();
      final initializer = TypeView(
        FunctionConstant(_target('initialize', .integer)),
        FunctionType(.integer, []),
      );
      final cell = entry.emit(
        NewCell(
          CellType(.integer, isLate: true),
          null,
          initializer: initializer,
        ),
      );
      entry.emit(initializer);
      entry.finish(Return(entry.emit(ReadCell(cell))));
      expect(() => IrFunction(target, [entry]), throwsStateError);
    });
  });

  group('late local runtime', () {
    test(
      'capturing unbound storage does not read and null binds distinctly',
      () {
        final f = _fixture(
          CellType(ValueType.integer.nullable, isLate: true, isFinal: true),
        );
        final first = f.runner.run(f.create, []);
        final second = f.runner.run(f.create, []);
        final missing = _error(() => f.runner.run(f.read, [first]));
        expect(missing, isA<Error>());
        expect(missing.runtimeType.toString(), 'LateError');
        f.runner.run(f.write, [first, null]);
        expect(f.runner.run(f.read, [first]), isNull);
        expect(
          _error(() => f.runner.run(f.write, [first, 1])).runtimeType,
          missing.runtimeType,
        );
        expect(
          _error(() => f.runner.run(f.read, [second])).runtimeType,
          missing.runtimeType,
        );
      },
    );

    test(
      'null lazy results bind once and writes suppress mutable initialization',
      () {
        var calls = 0;
        final f = _fixture(
          CellType(ValueType.integer.nullable, isLate: true),
          initializer: _observedInitializer(ValueType.integer.nullable),
          imports: {
            (_library, 'observe'): (_) {
              calls++;
              return null;
            },
          },
        );
        final first = f.runner.run(f.create, []);
        final second = f.runner.run(f.create, []);
        expect(calls, 0);
        f.runner.run(f.write, [first, null]);
        expect(f.runner.run(f.read, [first]), isNull);
        expect(calls, 0);
        expect(f.runner.run(f.read, [second]), isNull);
        expect(f.runner.run(f.read, [second]), isNull);
        expect(calls, 1);
      },
    );

    for (final isFinal in [false, true]) {
      test(
        'recursive initialization ${isFinal ? 'keeps the inner final binding' : 'overwrites the inner mutable binding'}',
        () {
          var calls = 0;
          late Object? Function() readAgain;
          final f = _fixture(
            CellType(.integer, isLate: true, isFinal: isFinal),
            initializer: _observedInitializer(.integer),
            imports: {
              (_library, 'observe'): (_) =>
                  ++calls == 1 ? (readAgain() as int) + 1 : 20,
            },
          );
          final pair = f.runner.run(f.create, []);
          readAgain = () => f.runner.run(f.read, [pair]);
          if (isFinal) {
            expect(_error(readAgain).runtimeType.toString(), 'LateError');
            expect(readAgain(), 20);
          } else {
            expect(readAgain(), 21);
            expect(readAgain(), 21);
          }
          expect(calls, 2);
        },
      );
    }

    for (final writeBeforeThrow in [false, true]) {
      for (final isFinal in [false, true]) {
        test(
          'failed ${isFinal ? 'final' : 'mutable'} initializer ${writeBeforeThrow ? 'preserves recursive writes' : 'retries while unbound'}',
          () {
            var calls = 0;
            late void Function() write;
            final error = StateError('original');
            final trace = StackTrace.fromString(
              'original local initializer trace',
            );
            final f = _fixture(
              CellType(.integer, isLate: true, isFinal: isFinal),
              initializer: _observedInitializer(.integer),
              imports: {
                (_library, 'observe'): (_) {
                  if (++calls == 1) {
                    if (writeBeforeThrow) write();
                    Error.throwWithStackTrace(error, trace);
                  }
                  return 11;
                },
              },
            );
            final pair = f.runner.run(f.create, []);
            write = () => f.runner.run(f.write, [pair, 10]);
            try {
              f.runner.run(f.read, [pair]);
              fail('Expected the initializer error.');
            } catch (caught, caughtTrace) {
              expect(caught, same(error));
              expect(caughtTrace.toString(), trace.toString());
            }
            expect(f.runner.run(f.read, [pair]), writeBeforeThrow ? 10 : 11);
            expect(calls, writeBeforeThrow ? 1 : 2);
          },
        );
      }
    }

    test('initializer conversion failures retry without binding', () {
      var calls = 0;
      final f = _fixture(
        CellType(.integer, isLate: true, isFinal: true),
        initializer: _observedInitializer(.integer),
        imports: {(_library, 'observe'): (_) => ++calls == 1 ? 'wrong' : 7},
      );
      final pair = f.runner.run(f.create, []);
      expect(() => f.runner.run(f.read, [pair]), throwsA(isA<TypeError>()));
      expect(f.runner.run(f.read, [pair]), 7);
      expect(f.runner.run(f.read, [pair]), 7);
      expect(calls, 2);
    });

    for (final isFinal in [false, true]) {
      test(
        'failed initializer conversion preserves ${isFinal ? 'final' : 'mutable'} recursive writes',
        () {
          late void Function() write;
          final f = _fixture(
            CellType(.integer, isLate: true, isFinal: isFinal),
            initializer: _observedInitializer(.integer),
            imports: {
              (_library, 'observe'): (_) {
                write();
                return 'wrong';
              },
            },
          );
          final pair = f.runner.run(f.create, []);
          write = () => f.runner.run(f.write, [pair, 10]);
          expect(() => f.runner.run(f.read, [pair]), throwsA(isA<TypeError>()));
          expect(f.runner.run(f.read, [pair]), 10);
        },
      );
    }

    test(
      'late reads and final writes carry real errors along Invoke edges',
      () {
        for (final store in [false, true]) {
          final target = _target('caught', .object);
          final entry = Block(), success = Block(), failure = Block([.object]);
          final cell = entry.emit(
            NewCell(
              CellType(.integer, isLate: true, isFinal: true),
              store ? const Constant.integer(1) : null,
            ),
          );
          final operation = store
              ? WriteCell(cell, const Constant.integer(2))
              : ReadCell(cell);
          entry.finish(
            Invoke(
              operation,
              onReturn: Jump(success),
              onThrow: Jump(failure, [UnwindValue.exception]),
            ),
          );
          success.finish(const Return(Constant.string('success')));
          failure.finish(Return(failure.parameters.single));
          final caught = IrFunction(target, [entry, success, failure]);
          final error = FixtureRunner(
            IrProgram([], [caught]),
            {},
          ).run(caught, []);
          expect(error, isA<Error>());
          expect(error.runtimeType.toString(), 'LateError');
        }
      },
    );

    test(
      'actual generic content is checked before binding and repeated writes',
      () {
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final target = FunctionTarget(
          _library,
          'write',
          .object,
          [t, t],
          typeParameters: [t],
        );
        final entry = Block(target.parameterTypes),
            success = Block(),
            failure = Block([.object]);
        final cell = entry.emit(
          NewCell(
            CellType(t, isLate: true, isFinal: true),
            entry.parameters.first,
          ),
        );
        entry.finish(
          Invoke(
            WriteCell(cell, entry.parameters.last),
            onReturn: Jump(success),
            onThrow: Jump(failure, [UnwindValue.exception]),
          ),
        );
        success.finish(const Return(Constant.string('success')));
        failure.finish(Return(failure.parameters.single));
        final body = IrFunction(target, [entry, success, failure]);
        final runner = FixtureRunner(IrProgram([], [body]), {});
        expect(
          runner.run(body, [7, 1.5], {t: ValueType.integer}),
          isA<TypeError>(),
        );
        expect(
          runner
              .run(body, [7, 8], {t: ValueType.integer})
              .runtimeType
              .toString(),
          'LateError',
        );
        expect(
          () => runner.run(body, [1.5, 7], {t: ValueType.integer}),
          throwsA(isA<TypeError>()),
        );
      },
    );

    test('failed generic write leaves a late final cell unbound', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final target = FunctionTarget(
        _library,
        'retry',
        t,
        [t, t],
        typeParameters: [t],
      );
      final entry = Block(target.parameterTypes),
          success = Block(),
          failure = Block();
      final cell = entry.emit(
        NewCell(CellType(t, isLate: true, isFinal: true), null),
      );
      entry.finish(
        Invoke(
          WriteCell(cell, entry.parameters.first),
          onReturn: Jump(success),
          onThrow: Jump(failure),
        ),
      );
      success.finish(Return(entry.parameters.first));
      failure.emit(WriteCell(cell, entry.parameters.last));
      failure.finish(Return(failure.emit(ReadCell(cell))));
      final body = IrFunction(target, [entry, success, failure]);
      final runner = FixtureRunner(IrProgram([], [body]), {});
      expect(runner.run(body, [1.5, 7], {t: ValueType.integer}), 7);
    });

    test('initializer closure retains actual generic types and latest mutable capture', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final resultType = RecordType([ValueType.typeType, ValueType.integer]);
      final target = FunctionTarget(
        _library,
        'capture',
        resultType,
        [],
        typeParameters: [t],
      );
      final capturedType = CellType(.integer);
      final initializer = FunctionTarget(
        _library,
        'initialize',
        resultType,
        [],
        kind: .closure,
        enclosing: target,
        sourceOffset: 1,
        captures: [capturedType],
      );
      final initBody = _body(initializer, (block) {
        block.finish(
          Return(
            block.emit(
              MakeRecord(resultType, [
                block.emit(ReifyType(t)),
                block.emit(ReadCell(block.parameters[1])),
              ]),
            ),
          ),
        );
      });
      final body = _body(target, (block) {
        final earlier = block.emit(
          NewCell(capturedType, const Constant.integer(1)),
        );
        final function = block.emit(MakeClosure(initializer, [earlier]));
        final cell = block.emit(
          NewCell(
            CellType(resultType, isLate: true),
            null,
            initializer: function,
          ),
        );
        block.emit(WriteCell(earlier, const Constant.integer(9)));
        block.finish(Return(block.emit(ReadCell(cell))));
      });
      final runner = FixtureRunner(IrProgram([], [body, initBody]), {});
      final result = runner.run(body, [], {
        t: CoreTypes.listOf(ValueType.integer),
      });
      final readType = _body(
        _target('readType', .typeType, [resultType]),
        (block) => block.finish(
          Return(block.emit(RecordGet(block.parameters.single, 0))),
        ),
      );
      final readInt = _body(
        _target('readInt', .integer, [resultType]),
        (block) => block.finish(
          Return(block.emit(RecordGet(block.parameters.single, 1))),
        ),
      );
      expect(runner.run(readType, [result]).toString(), 'List<int>');
      expect(runner.run(readInt, [result]), 9);
      final text = StringBuffer();
      body.writeTo(text);
      expect(text.toString(), contains('cell lazy'));
    });

    test('copying bound null preserves initialization without calling its lazy body', () {
      var calls = 0;
      final initializer = _observedInitializer(ValueType.integer.nullable);
      final body = _body(_target('copyNull', ValueType.integer.nullable), (
        block,
      ) {
        final source = block.emit(
          NewCell(
            CellType(ValueType.integer.nullable, isLate: true),
            null,
            initializer: FunctionConstant(initializer.target),
          ),
        );
        block.emit(WriteCell(source, const Constant.nullValue()));
        final copy = block.emit(CopyCell(source));
        block.emit(WriteCell(source, const Constant.integer(8)));
        block.finish(Return(block.emit(ReadCell(copy))));
      });
      final runner = FixtureRunner(IrProgram([], [body, initializer]), {
        (_library, 'observe'): (_) {
          calls++;
          return 3;
        },
      });
      expect(runner.run(body, []), isNull);
      expect(calls, 0);
    });

    test('copies preserve lazy initializer, independent unbound state, and final binding', () {
      var calls = 0;
      final initializer = _observedInitializer(.integer);
      final target = _target('copy', .integer);
      final body = _body(target, (block) {
        final source = block.emit(
          NewCell(
            CellType(.integer, isLate: true, isFinal: true),
            null,
            initializer: FunctionConstant(initializer.target),
          ),
        );
        final copy = block.emit(CopyCell(source));
        final first = block.emit(ReadCell(source));
        final second = block.emit(ReadCell(copy));
        block.finish(Return(block.emit(IntBinary(.add, first, second))));
      });
      final runner = FixtureRunner(IrProgram([], [body, initializer]), {
        (_library, 'observe'): (_) => ++calls,
      });
      expect(runner.run(body, []), 3);
      expect(calls, 2);
      final copiedBound = _body(_target('copyBound', .voidType), (block) {
        final source = block.emit(
          NewCell(
            CellType(.integer, isLate: true, isFinal: true),
            const Constant.integer(7),
          ),
        );
        final copy = block.emit(CopyCell(source));
        block.emit(WriteCell(copy, const Constant.integer(8)));
        block.finish(const Return());
      });
      expect(
        _error(() => runner.run(copiedBound, [])).runtimeType.toString(),
        'LateError',
      );
    });
  });
}
