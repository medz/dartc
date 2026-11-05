import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _library = Uri.parse('memory:late_fields');

FunctionTarget _target(
  String name,
  ValueType result, [
  List<ValueType> parameters = const [],
]) => FunctionTarget(_library, name, result, parameters);

FunctionTarget _initializer(ClassType owner, ValueType type) => FunctionTarget(
  owner.library,
  'initialize',
  type,
  [],
  owner: owner,
  kind: .fieldInitializer,
);

IrFunction _body(FunctionTarget target, void Function(Block) build) {
  final block = Block(target.parameterTypes);
  build(block);
  return IrFunction(target, [block]);
}

({FixtureRunner runner, IrFunction create, IrFunction read, IrFunction? write})
_fixture(
  InstanceField field, {
  IrFunction? initializer,
  ClassType? instanceType,
  ClassType? view,
  Map<(Uri, String), Object? Function(int)> imports = const {},
}) {
  instanceType ??= field.owner;
  view ??= instanceType;
  final ctor = FunctionTarget(
    _library,
    '',
    .voidType,
    [],
    owner: instanceType.declaration,
    kind: .initializer,
  );
  final create = _body(_target('create', instanceType), (block) {
    block.finish(
      Return(block.emit(Construct(ctor, [], instantiatedType: instanceType))),
    );
  });
  final read = _body(_target('read', field.typeFor(view), [view]), (block) {
    block.finish(Return(block.emit(LoadField(field, block.parameters.single))));
  });
  final write = field.isWritable
      ? _body(_target('write', .voidType, [view, field.typeFor(view)]), (
          block,
        ) {
          block.emit(
            StoreField(field, block.parameters[0], block.parameters[1]),
          );
          block.finish(const Return());
        })
      : null;
  final program = IrProgram(
    [
      IrClass(field.owner, [
        field,
      ], constructors: ctor.owner == field.owner ? [ctor] : []),
      if (ctor.owner != field.owner)
        IrClass(ctor.owner!, [], constructors: [ctor]),
    ],
    [
      _body(ctor, (block) => block.finish(const Return())),
      create,
      read,
      ?write,
      ?initializer,
    ],
  );
  return (
    runner: FixtureRunner(program, imports),
    create: create,
    read: read,
    write: write,
  );
}

Object _error(void Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  fail('Expected an error.');
}

void main() {
  group('late field declarations', () {
    test('preserve ordinary storage and use a receiver-only initializer', () {
      final owner = ClassType(_library, 'Box');
      final ordinary = InstanceField(owner, 'ordinary', .integer);
      final initializer = _initializer(owner, .integer);
      final field = InstanceField(
        owner,
        'value',
        .integer,
        isLate: true,
        isFinal: true,
        initializer: initializer,
      );
      final receiver = Block([owner]).parameters.single;
      expect(ordinary.isLate, isFalse);
      expect(ordinary.initializer, isNull);
      expect(ordinary.isWritable, isTrue);
      expect(LoadField(ordinary, receiver).mayThrow, isFalse);
      expect(
        StoreField(ordinary, receiver, const Constant.integer(1)).mayThrow,
        isFalse,
      );
      expect(field.isWritable, isFalse);
      expect(LoadField(field, receiver).mayThrow, isTrue);
      expect(initializer.parameterTypes, [owner]);
      expect(initializer.signature.parameters, isEmpty);
      expect(initializer.signature.result, ValueType.integer);
      expect(initializer.kind.hasReceiver, isTrue);
      expect(initializer.kind.isVirtual, isFalse);
      expect(() => FunctionConstant(initializer), throwsArgumentError);
      expect(
        () => IrClass(owner, [field], members: [initializer]),
        throwsArgumentError,
      );
      expect(
        () => IrClass(owner, [field], constructors: [initializer]),
        throwsArgumentError,
      );
    });

    test(
      'reject incompatible initializer owners, protocols and signatures',
      () {
        final owner = ClassType(_library, 'Box');
        final other = ClassType(_library, 'Other');
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        for (final target in [
          _initializer(other, .integer),
          _initializer(owner, .string),
          FunctionTarget(_library, 'static', .integer, [], owner: owner),
          FunctionTarget(
            _library,
            'getter',
            .integer,
            [],
            owner: owner,
            kind: .getter,
          ),
          FunctionTarget(
            _library,
            'ctor',
            .voidType,
            [],
            owner: owner,
            kind: .initializer,
          ),
        ]) {
          expect(
            () => InstanceField(
              owner,
              'value',
              .integer,
              isLate: true,
              initializer: target,
            ),
            throwsArgumentError,
            reason: target.name,
          );
        }
        expect(
          () => InstanceField(
            owner,
            'value',
            .integer,
            initializer: _initializer(owner, .integer),
          ),
          throwsArgumentError,
        );
        for (final make in <FunctionTarget Function()>[
          () => FunctionTarget(
            _library,
            'ownerless',
            .integer,
            [],
            kind: .fieldInitializer,
          ),
          () => FunctionTarget(
            _library,
            'argument',
            .integer,
            [.integer],
            owner: owner,
            kind: .fieldInitializer,
          ),
          () => FunctionTarget(
            _library,
            'generic',
            t,
            [],
            owner: owner,
            kind: .fieldInitializer,
            typeParameters: [t],
          ),
        ]) {
          expect(make, throwsArgumentError);
        }
      },
    );

    test(
      'late final writes differ from ordinary constructor-only final writes',
      () {
        final owner = ClassType(_library, 'Box');
        for (final isLate in [false, true]) {
          final field = InstanceField(
            owner,
            'value',
            .integer,
            isLate: isLate,
            isFinal: true,
          );
          final target = _target('write', .voidType, [owner]);
          final block = Block(target.parameterTypes);
          final write = block.emit(
            StoreField(
              field,
              block.parameters.single,
              const Constant.integer(1),
            ),
          );
          block.finish(const Return());
          expect(field.isWritable, isLate);
          expect(write.mayThrow, isLate);
          expect(
            () => IrFunction(target, [block]),
            isLate ? returnsNormally : throwsStateError,
          );
        }
        final field = InstanceField(
          owner,
          'value',
          .integer,
          isLate: true,
          isFinal: true,
          initializer: _initializer(owner, .integer),
        );
        final receiver = Block([owner]).parameters.single;
        expect(
          () => StoreField(field, receiver, const Constant.integer(1)),
          throwsArgumentError,
        );
      },
    );

    test('initializer body identity belongs to a declared field', () {
      final owner = ClassType(_library, 'Box');
      final target = _initializer(owner, .integer);
      final field = InstanceField(
        owner,
        'value',
        .integer,
        isLate: true,
        initializer: target,
      );
      final body = _body(
        target,
        (block) => block.finish(const Return(Constant.integer(1))),
      );
      final impostor = _body(
        _initializer(owner, .integer),
        (block) => block.finish(const Return(Constant.integer(1))),
      );
      expect(
        () => IrProgram([
          IrClass(owner, [field]),
        ], []),
        throwsArgumentError,
      );
      expect(
        () => IrProgram(
          [
            IrClass(owner, [field]),
          ],
          [impostor],
        ),
        throwsArgumentError,
      );
      expect(
        () => IrProgram([IrClass(owner, [])], [body]),
        throwsArgumentError,
      );
      expect(
        () => IrProgram(
          [
            IrClass(owner, [
              field,
              InstanceField(
                owner,
                'other',
                .integer,
                isLate: true,
                initializer: target,
              ),
            ]),
          ],
          [body],
        ),
        throwsArgumentError,
      );
      final program = IrProgram(
        [
          IrClass(owner, [field]),
        ],
        [body],
      );
      expect(program.classes.single.members, isEmpty);
      final text = StringBuffer();
      program.writeTo(text);
      expect(text.toString(), contains('late int value = initialize'));
    });

    test('field initializer scope admits owner parameters but rejects foreign ones', () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final u = TypeParameterType('U')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(_library, 'Box', typeParameters: [t]);
      for (final parameter in [t, u]) {
        final target = _initializer(owner, .typeType);
        expect(
          () => _body(
            target,
            (block) => block.finish(Return(block.emit(ReifyType(parameter)))),
          ),
          parameter == t ? returnsNormally : throwsStateError,
        );
      }
    });
  });

  group('late field storage', () {
    test(
      'unbound differs from bound null, with storage isolated by receiver',
      () {
        final field = InstanceField(
          ClassType(_library, 'Box'),
          'value',
          ValueType.integer.nullable,
          isLate: true,
          isFinal: true,
        );
        final f = _fixture(field);
        final first = f.runner.run(f.create, []);
        final second = f.runner.run(f.create, []);
        final missing = _error(() => f.runner.run(f.read, [first]));
        f.runner.run(f.write!, [first, null]);
        final repeated = _error(() => f.runner.run(f.write!, [first, 1]));
        expect(missing, isA<Error>());
        expect(missing.runtimeType.toString(), 'LateError');
        expect(repeated.runtimeType, missing.runtimeType);
        expect(f.runner.run(f.read, [first]), isNull);
        expect(() => f.runner.run(f.read, [second]), throwsA(isA<Error>()));
        expect(
          () => f.runner.run(f.write!, [first, 'wrong']),
          throwsA(isA<TypeError>()),
        );
      },
    );

    test('null results bind once and writes bypass a mutable initializer', () {
      final owner = ClassType(_library, 'Box');
      final target = _initializer(owner, ValueType.integer.nullable);
      final external = _target('observe', ValueType.integer.nullable, [
        .integer,
      ]);
      final field = InstanceField(
        owner,
        'value',
        ValueType.integer.nullable,
        isLate: true,
        initializer: target,
      );
      var calls = 0;
      final f = _fixture(
        field,
        initializer: _body(
          target,
          (block) => block.finish(
            Return(
              block.emit(DirectCall(external, [const Constant.integer(0)])),
            ),
          ),
        ),
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
      f.runner.run(f.write!, [first, null]);
      expect(f.runner.run(f.read, [first]), isNull);
      expect(calls, 0);
      expect(f.runner.run(f.read, [second]), isNull);
      expect(f.runner.run(f.read, [second]), isNull);
      expect(calls, 1);
    });

    for (final isFinal in [false, true]) {
      test(
        'recursive initializer ${isFinal ? 'keeps the inner final binding' : 'replaces the inner mutable binding'}',
        () {
          final owner = ClassType(_library, 'Box');
          final target = _initializer(owner, .integer);
          final external = _target('observe', .integer, [.integer]);
          final field = InstanceField(
            owner,
            'value',
            .integer,
            isLate: true,
            isFinal: isFinal,
            initializer: target,
          );
          var calls = 0;
          late Object? Function() readAgain;
          final f = _fixture(
            field,
            initializer: _body(
              target,
              (block) => block.finish(
                Return(
                  block.emit(DirectCall(external, [const Constant.integer(0)])),
                ),
              ),
            ),
            imports: {
              (_library, 'observe'): (_) =>
                  ++calls == 1 ? (readAgain() as int) + 1 : 20,
            },
          );
          final instance = f.runner.run(f.create, []);
          readAgain = () => f.runner.run(f.read, [instance]);
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
      test(
        'failed initializer ${writeBeforeThrow ? 'preserves its write' : 'retries while unbound'}',
        () {
          final owner = ClassType(_library, 'Box');
          final target = _initializer(owner, .integer);
          final external = _target('observe', .integer, [.integer]);
          final field = InstanceField(
            owner,
            'value',
            .integer,
            isLate: true,
            initializer: target,
          );
          final error = StateError('original');
          final trace = StackTrace.fromString(
            'original field initializer trace',
          );
          var calls = 0;
          final f = _fixture(
            field,
            initializer: _body(target, (block) {
              if (writeBeforeThrow) {
                block.emit(
                  StoreField(
                    field,
                    block.parameters.single,
                    const Constant.integer(10),
                  ),
                );
              }
              block.finish(
                Return(
                  block.emit(
                    DirectCall(external, [const Constant.integer(11)]),
                  ),
                ),
              );
            }),
            imports: {
              (_library, 'observe'): (value) {
                if (++calls == 1) Error.throwWithStackTrace(error, trace);
                return value;
              },
            },
          );
          final instance = f.runner.run(f.create, []);
          try {
            f.runner.run(f.read, [instance]);
            fail('Expected the original initializer error.');
          } catch (caught, caughtTrace) {
            expect(caught, same(error));
            expect(caughtTrace.toString(), trace.toString());
          }
          expect(f.runner.run(f.read, [instance]), writeBeforeThrow ? 10 : 11);
          expect(calls, writeBeforeThrow ? 1 : 2);
        },
      );
    }

    test('late reads and writes carry real errors along Invoke edges', () {
      final owner = ClassType(_library, 'Box');
      final field = InstanceField(
        owner,
        'value',
        .integer,
        isLate: true,
        isFinal: true,
      );
      final f = _fixture(field);
      final instance = f.runner.run(f.create, []);
      for (final store in [false, true]) {
        final target = _target('caught', .object, [owner]);
        final entry = Block(target.parameterTypes);
        final success = Block(), failure = Block([.object]);
        final op = store
            ? StoreField(
                field,
                entry.parameters.single,
                const Constant.integer(2),
              )
            : LoadField(field, entry.parameters.single);
        entry.finish(
          Invoke(
            op,
            onReturn: Jump(success),
            onThrow: Jump(failure, [UnwindValue.exception]),
          ),
        );
        success.finish(const Return(Constant.string('success')));
        failure.finish(Return(failure.parameters.single));
        final caught = IrFunction(target, [entry, success, failure]);
        if (store) f.runner.run(f.write!, [instance, 1]);
        final error = f.runner.run(caught, [instance]);
        expect(error, isA<Error>());
        expect(error.runtimeType.toString(), 'LateError');
      }
    });

    test(
      'inherited initializers use the actual declaring-owner environment',
      () {
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final u = TypeParameterType('U')
          ..initializeBound(ValueType.object.nullable);
        final base = ClassType(_library, 'Base', typeParameters: [t]);
        final child = ClassType(
          _library,
          'Child',
          typeParameters: [u],
          superclass: base.instantiate([CoreTypes.listOf(u)]),
        );
        final target = _initializer(base, .typeType);
        final field = InstanceField(
          base,
          'value',
          .typeType,
          isLate: true,
          initializer: target,
        );
        final f = _fixture(
          field,
          initializer: _body(
            target,
            (block) => block.finish(Return(block.emit(ReifyType(t)))),
          ),
          instanceType: child.instantiate([ValueType.integer]),
          view: base.instantiate([ValueType.object]),
        );
        final instance = f.runner.run(f.create, []);
        expect(f.runner.run(f.read, [instance]).toString(), 'List<int>');
      },
    );

    test(
      'generic late final casts precede binding and repeated-write checks',
      () {
        final t = TypeParameterType('T')
          ..initializeBound(ValueType.object.nullable);
        final owner = ClassType(_library, 'Box', typeParameters: [t]);
        final field = InstanceField(
          owner,
          'value',
          t,
          isLate: true,
          isFinal: true,
        );
        final f = _fixture(
          field,
          instanceType: owner.instantiate([ValueType.integer]),
          view: owner.instantiate([ValueType.number]),
        );
        final instance = f.runner.run(f.create, []);
        // IR storage retains its actual type regardless of source setter lowering.
        expect(
          () => f.runner.run(f.write!, [instance, 1.5]),
          throwsA(isA<TypeError>()),
        );
        f.runner.run(f.write!, [instance, 7]);
        expect(
          () => f.runner.run(f.write!, [instance, 1.5]),
          throwsA(isA<TypeError>()),
        );
        expect(
          _error(() => f.runner.run(f.write!, [instance, 8])).runtimeType
              .toString(),
          'LateError',
        );
        expect(f.runner.run(f.read, [instance]), 7);
      },
    );
  });
}
