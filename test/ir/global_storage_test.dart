import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _library = Uri.parse('memory:globals');

FunctionTarget _target(
  String name,
  ValueType result, [
  List<ValueType> parameters = const [],
]) => FunctionTarget(_library, name, result, parameters);

IrFunction _body(FunctionTarget target, void Function(Block) build) {
  final block = Block(target.parameterTypes);
  build(block);
  return IrFunction(target, [block]);
}

IrFunction _reader(GlobalVariable global, [String name = 'read']) => _body(
  _target(name, global.type),
  (block) => block.finish(Return(block.emit(LoadGlobal(global)))),
);

IrFunction _writer(GlobalVariable global) =>
    _body(_target('write', .voidType, [global.type]), (block) {
      block.emit(StoreGlobal(global, block.parameters.single));
      block.finish(const Return());
    });

Object _error(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  fail('Expected an error.');
}

void main() {
  group('global declarations', () {
    test(
      'retain source identity and support closed generic function types',
      () {
        final a = GlobalVariable(_library, 'value', ValueType.integer.nullable);
        final b = GlobalVariable(_library, 'value', ValueType.integer.nullable);
        expect(a, isNot(same(b)));
        expect(a.library, _library);
        expect(a.name, 'value');
        expect(a.owner, isNull);
        expect(a.isFinal, isFalse);
        expect(a.isLate, isFalse);
        expect(a.isWritable, isTrue);
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final generic = FunctionType(t, [t], typeParameters: [t]);
        expect(
          GlobalVariable(_library, 'identity', generic, isLate: true).type,
          generic,
        );
      },
    );

    test('reject storage and free type parameters, including nested types', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      for (final type in <ValueType>[
        CellType(ValueType.integer),
        t,
        CoreTypes.listOf(t),
        FunctionType(ValueType.integer, [t]),
        RecordType([t]),
      ]) {
        expect(
          () => GlobalVariable(_library, 'value', type, isLate: true),
          throwsArgumentError,
        );
      }
    });

    test(
      'non-late storage without initializer must allow its initial null',
      () {
        expect(
          () => GlobalVariable(_library, 'value', .integer),
          throwsArgumentError,
        );
        expect(
          () => GlobalVariable(
            _library,
            'value',
            ValueType.integer.nullable,
            isFinal: true,
          ),
          throwsArgumentError,
        );
        expect(
          () => GlobalVariable(_library, 'value', .dynamicType),
          returnsNormally,
        );
      },
    );

    test('static storage requires the matching class declaration', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(_library, 'Box', typeParameters: [t]);
      expect(
        () => GlobalVariable(
          _library,
          'value',
          .integer,
          owner: owner,
          isLate: true,
        ),
        returnsNormally,
      );
      for (final invalid in [
        ClassType(Uri.parse('memory:foreign'), 'Other'),
        owner.instantiate([ValueType.integer]),
      ]) {
        expect(
          () => GlobalVariable(
            _library,
            'value',
            .integer,
            owner: invalid,
            isLate: true,
          ),
          throwsArgumentError,
        );
      }
    });

    test(
      'initializer must be closed, zero-argument and match type and owner',
      () {
        final owner = ClassType(_library, 'Box');
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final outer = _target('outer', .voidType);
        final invalid = [
          _target('wrongResult', .string),
          _target('argument', .integer, [.integer]),
          FunctionTarget(Uri.parse('memory:foreign'), 'foreign', .integer, []),
          FunctionTarget(_library, 'owned', .integer, [], owner: owner),
          FunctionTarget(
            _library,
            'generic',
            .integer,
            [],
            typeParameters: [t],
          ),
          FunctionTarget(_library, 'getter', .integer, [], kind: .staticGetter),
          FunctionTarget(
            _library,
            'closure',
            .integer,
            [],
            kind: .closure,
            enclosing: outer,
            sourceOffset: 1,
          ),
        ];
        for (final initializer in invalid) {
          expect(
            () => GlobalVariable(
              _library,
              'value',
              .integer,
              initializer: initializer,
            ),
            throwsArgumentError,
            reason: initializer.name,
          );
        }
        expect(
          () => GlobalVariable(
            _library,
            'value',
            .integer,
            initializer: _target('valid', .integer),
          ),
          returnsNormally,
        );
      },
    );
  });

  group('global operations', () {
    test('reads may throw and expose the declared type without SSA inputs', () {
      final global = GlobalVariable(_library, 'value', .integer, isLate: true);
      final read = LoadGlobal(global);
      expect(read.global, same(global));
      expect(read.type, ValueType.integer);
      expect(read.inputs, isEmpty);
      expect(read.mayThrow, isTrue);
    });

    test('writes accept only writable slots and already compatible values', () {
      final global = GlobalVariable(_library, 'value', .integer, isLate: true);
      const value = Constant.integer(1);
      final write = StoreGlobal(global, value);
      expect(write.global, same(global));
      expect(write.value, same(value));
      expect(write.type, ValueType.voidType);
      expect(write.inputs, [value]);
      expect(write.mayThrow, isFalse);
      final lateFinal = GlobalVariable(
        _library,
        'once',
        .integer,
        isLate: true,
        isFinal: true,
      );
      expect(lateFinal.isWritable, isTrue);
      expect(StoreGlobal(lateFinal, value).mayThrow, isTrue);
      for (final isLate in [false, true]) {
        final readOnly = GlobalVariable(
          _library,
          'fixed',
          .integer,
          isLate: isLate,
          isFinal: true,
          initializer: _target('init', .integer),
        );
        expect(readOnly.isWritable, isFalse);
        expect(() => StoreGlobal(readOnly, value), throwsArgumentError);
      }
      expect(
        () => StoreGlobal(global, const Constant.string('wrong')),
        throwsArgumentError,
      );
      expect(
        () => StoreGlobal(global, NewCell(CellType(.integer), value)),
        throwsArgumentError,
      );
    });
  });

  group('program global linkage', () {
    test('rejects duplicate declarations and missing initializer bodies', () {
      final global = GlobalVariable(_library, 'value', .integer, isLate: true);
      for (final duplicate in [
        global,
        GlobalVariable(_library, 'value', .integer, isLate: true),
      ]) {
        expect(
          () => IrProgram([], [], globals: [global, duplicate]),
          throwsArgumentError,
        );
      }
      final initializer = _target('initialize', .integer);
      final initialized = GlobalVariable(
        _library,
        'initialized',
        .integer,
        initializer: initializer,
      );
      expect(
        () => IrProgram([], [], globals: [initialized]),
        throwsArgumentError,
      );
      final impostor = _body(
        _target('initialize', .integer),
        (block) => block.finish(const Return(Constant.integer(1))),
      );
      expect(
        () => IrProgram([], [impostor], globals: [initialized]),
        throwsArgumentError,
      );
      final body = _body(
        initializer,
        (block) => block.finish(const Return(Constant.integer(1))),
      );
      expect(
        () => IrProgram([], [body], globals: [initialized]),
        returnsNormally,
      );
    });

    test('checks class ownership and allows same names in distinct scopes', () {
      final owner = ClassType(_library, 'Box');
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        owner: owner,
        isLate: true,
      );
      expect(() => IrProgram([], [], globals: [global]), throwsArgumentError);
      expect(
        () => IrProgram(
          [IrClass(ClassType(_library, 'Box'), [])],
          [],
          globals: [global],
        ),
        throwsArgumentError,
      );
      expect(
        () => IrProgram(
          [IrClass(owner, [])],
          [],
          globals: [
            global,
            GlobalVariable(_library, 'value', .integer, isLate: true),
            GlobalVariable(
              Uri.parse('memory:other'),
              'value',
              .integer,
              isLate: true,
            ),
          ],
        ),
        returnsNormally,
      );
    });

    test(
      'checks load and store identity, including exceptional operations',
      () {
        final declared = GlobalVariable(
          _library,
          'value',
          .integer,
          isLate: true,
          isFinal: true,
        );
        final foreign = GlobalVariable(
          _library,
          'value',
          .integer,
          isLate: true,
          isFinal: true,
        );
        for (final function in [_reader(foreign), _writer(foreign)]) {
          expect(function.globals, {foreign});
          expect(
            () => IrProgram([], [function], globals: [declared]),
            throwsArgumentError,
          );
        }
        for (final operation in <Instruction>[
          LoadGlobal(foreign),
          StoreGlobal(foreign, const Constant.integer(1)),
        ]) {
          final entry = Block(), success = Block(), failure = Block();
          entry.finish(
            Invoke(operation, onReturn: Jump(success), onThrow: Jump(failure)),
          );
          success.finish(const Return(Constant.integer(1)));
          failure.finish(const Return(Constant.integer(-1)));
          final function = IrFunction(_target('caught', .integer), [
            entry,
            success,
            failure,
          ]);
          expect(function.globals, {foreign});
          expect(() => function.globals.add(declared), throwsUnsupportedError);
          expect(
            () => IrProgram([], [function], globals: [declared]),
            throwsArgumentError,
          );
        }
        final noGlobals = _body(
          _target('plain', .integer),
          (block) => block.finish(const Return(Constant.integer(1))),
        );
        expect(noGlobals.globals, isEmpty);
        expect(() => noGlobals.globals.add(declared), throwsUnsupportedError);
      },
    );

    test(
      'static initializer bodies cannot use their class type parameters',
      () {
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final owner = ClassType(_library, 'Box', typeParameters: [t]);
        final initializer = FunctionTarget(
          _library,
          'initialize',
          .integer,
          [],
          owner: owner,
        );
        final block = Block();
        block.emit(ReifyType(t));
        block.finish(const Return(Constant.integer(1)));
        expect(() => IrFunction(initializer, [block]), throwsStateError);
      },
    );

    test('writes stable declaration names and global operations', () {
      final owner = ClassType(_library, 'Box');
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        owner: owner,
        isFinal: true,
        isLate: true,
      );
      final program = IrProgram(
        [IrClass(owner, [])],
        [_reader(global), _writer(global)],
        globals: [global],
      );
      final output = StringBuffer();
      program.writeTo(output);
      expect(
        output.toString(),
        contains('global late final int memory:globals::Box.value'),
      );
      expect(
        output.toString(),
        contains('loadGlobal memory:globals::Box.value'),
      );
      expect(
        output.toString(),
        contains('storeGlobal memory:globals::Box.value'),
      );
      expect(() => program.globals.add(global), throwsUnsupportedError);
    });
  });

  group('fixture global storage', () {
    test('nullable default is bound but nullable late storage is unbound', () {
      final ordinary = GlobalVariable(
        _library,
        'ordinary',
        ValueType.integer.nullable,
      );
      final lateValue = GlobalVariable(
        _library,
        'lateValue',
        ValueType.integer.nullable,
        isLate: true,
      );
      final readOrdinary = _reader(ordinary, 'readOrdinary');
      final readLate = _reader(lateValue, 'readLate');
      final writeLate = _writer(lateValue);
      final program = IrProgram(
        [],
        [readOrdinary, readLate, writeLate],
        globals: [ordinary, lateValue],
      );
      final runner = IrInterpreter(program, {});
      expect(runner.run(readOrdinary, []), isNull);
      final error = _error(() => runner.run(readLate, []));
      expect(error, isA<Error>());
      expect(error.runtimeType.toString(), 'LateError');
      runner.run(writeLate, [null]);
      expect(runner.run(readLate, []), isNull);
    });

    test('initializers are lazy, cached and isolated between runners', () {
      final initializer = _target('initialize', .integer);
      final external = _target('observe', .integer, [.integer]);
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        initializer: initializer,
      );
      final body = _body(initializer, (block) {
        final result = block.emit(
          DirectCall(external, [const Constant.integer(7)]),
        );
        block.finish(Return(result));
      });
      final read = _reader(global);
      var calls = 0;
      final program = IrProgram([], [body, read], globals: [global]);
      IrInterpreter runner() => IrInterpreter(program, {
        (_library, 'observe'): (value) {
          calls++;
          return value;
        },
      });
      final first = runner();
      expect(calls, 0);
      expect(first.run(read, []), 7);
      expect(first.run(read, []), 7);
      expect(calls, 1);
      expect(runner().run(read, []), 7);
      expect(calls, 2);
    });

    test('write before read suppresses initializer for mutable storage', () {
      final initializer = _target('initialize', .integer);
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        initializer: initializer,
      );
      final body = _body(
        initializer,
        (block) => block.finish(Throw(const Constant.string('must not run'))),
      );
      final read = _reader(global), write = _writer(global);
      final runner = IrInterpreter(
        IrProgram([], [body, read, write], globals: [global]),
        {},
      );
      runner.run(write, [8]);
      expect(runner.run(read, []), 8);
    });

    test(
      'late final reads and repeat writes raise the same private error type',
      () {
        final global = GlobalVariable(
          _library,
          'once',
          ValueType.integer.nullable,
          isLate: true,
          isFinal: true,
        );
        final read = _reader(global), write = _writer(global);
        final runner = IrInterpreter(
          IrProgram([], [read, write], globals: [global]),
          {},
        );
        final missing = _error(() => runner.run(read, []));
        runner.run(write, [null]);
        final repeated = _error(() => runner.run(write, [1]));
        expect(repeated.runtimeType, missing.runtimeType);
        expect(repeated, isA<Error>());
        expect(runner.run(read, []), isNull);
      },
    );

    test('late final type checks happen before repeated-write checks', () {
      final global = GlobalVariable(
        _library,
        'once',
        .integer,
        isLate: true,
        isFinal: true,
      );
      final read = _reader(global), write = _writer(global);
      final runner = IrInterpreter(
        IrProgram([], [read, write], globals: [global]),
        {},
      );
      runner.run(write, [3]);
      expect(() => runner.run(write, ['bad']), throwsA(isA<TypeError>()));
      expect(runner.run(read, []), 3);
    });

    test('failed initializers retry only while storage remains unbound', () {
      final initializer = _target('initialize', .integer);
      final external = _target('observe', .integer, [.integer]);
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        initializer: initializer,
      );
      final body = _body(initializer, (block) {
        final result = block.emit(
          DirectCall(external, [const Constant.integer(7)]),
        );
        block.finish(Return(result));
      });
      final read = _reader(global);
      var calls = 0;
      final error = StateError('original');
      final runner = IrInterpreter(
        IrProgram([], [body, read], globals: [global]),
        {
          (_library, 'observe'): (value) {
            if (++calls == 1) throw error;
            return value;
          },
        },
      );
      expect(_error(() => runner.run(read, [])), same(error));
      expect(runner.run(read, []), 7);
      expect(calls, 2);
    });

    for (final throwsAfterWrite in [false, true]) {
      test(
        'initializer ${throwsAfterWrite ? 'throw preserves' : 'return replaces'} its mutable write',
        () {
          final initializer = _target('initialize', .integer);
          final global = GlobalVariable(
            _library,
            'value',
            .integer,
            initializer: initializer,
          );
          final body = _body(initializer, (block) {
            block.emit(StoreGlobal(global, const Constant.integer(10)));
            block.finish(
              throwsAfterWrite
                  ? Throw(const Constant.string('original'))
                  : const Return(Constant.integer(11)),
            );
          });
          final read = _reader(global);
          final runner = IrInterpreter(
            IrProgram([], [body, read], globals: [global]),
            {},
          );
          if (throwsAfterWrite) {
            expect(() => runner.run(read, []), throwsA('original'));
            expect(runner.run(read, []), 10);
          } else {
            expect(runner.run(read, []), 11);
            expect(runner.run(read, []), 11);
          }
        },
      );
    }

    test('pure recursive initialization reaches the host stack overflow', () {
      final initializer = _target('initialize', .integer);
      final global = GlobalVariable(
        _library,
        'recursive',
        .integer,
        initializer: initializer,
      );
      final body = _body(initializer, (block) {
        block.finish(Return(block.emit(LoadGlobal(global))));
      });
      final read = _reader(global);
      final runner = IrInterpreter(
        IrProgram([], [body, read], globals: [global]),
        {},
      );
      expect(() => runner.run(read, []), throwsA(isA<StackOverflowError>()));
    });

    test('initializer errors retain their original object and stack trace', () {
      final initializer = _target('initialize', .integer);
      final external = _target('observe', .integer, [.integer]);
      final global = GlobalVariable(
        _library,
        'value',
        .integer,
        initializer: initializer,
      );
      final body = _body(initializer, (block) {
        final result = block.emit(
          DirectCall(external, [const Constant.integer(0)]),
        );
        block.finish(Return(result));
      });
      final read = _reader(global);
      final error = StateError('original');
      final originalTrace = StackTrace.fromString('original initializer trace');
      final runner = IrInterpreter(
        IrProgram([], [body, read], globals: [global]),
        {
          (_library, 'observe'): (_) =>
              Error.throwWithStackTrace(error, originalTrace),
        },
      );
      try {
        runner.run(read, []);
        fail('Expected the initializer to fail.');
      } catch (caught, trace) {
        expect(caught, same(error));
        expect(trace.toString(), originalTrace.toString());
      }
    });

    for (final isFinal in [false, true]) {
      test(
        'recursive initializer ${isFinal ? 'preserves inner final binding' : 'can complete without a busy state'}',
        () {
          final initializer = _target('initialize', .integer);
          final external = _target('observe', .integer, [.integer]);
          final global = GlobalVariable(
            _library,
            'value',
            .integer,
            isFinal: isFinal,
            initializer: initializer,
          );
          final body = _body(initializer, (block) {
            final result = block.emit(
              DirectCall(external, [const Constant.integer(0)]),
            );
            block.finish(Return(result));
          });
          final read = _reader(global);
          var calls = 0;
          late IrInterpreter runner;
          runner = IrInterpreter(
            IrProgram([], [body, read], globals: [global]),
            {
              (_library, 'observe'): (_) =>
                  ++calls == 1 ? (runner.run(read, []) as int) + 1 : 20,
            },
          );
          if (isFinal) {
            final error = _error(() => runner.run(read, []));
            expect(error.runtimeType.toString(), 'LateError');
            expect(runner.run(read, []), 20);
          } else {
            expect(runner.run(read, []), 21);
            expect(runner.run(read, []), 21);
          }
          expect(calls, 2);
        },
      );
    }
  });
}
