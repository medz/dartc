import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _library = Uri.parse('memory:dynamic-runtime');
MemberSelector _selector(String name, [FunctionKind kind = .method]) =>
    (name: name, kind: kind, privateScope: null);

Object? _run(
  Value Function(Block) build, {
  List<IrClass> classes = const [],
  List<IrFunction> bodies = const [],
}) {
  final block = Block();
  final result = build(block);
  block.finish(Return(result));
  final function = IrFunction(
    FunctionTarget(_library, 'main', result.type, []),
    [block],
  );
  return IrInterpreter(
    IrProgram(classes, [function, ...bodies]),
    {},
  ).run(function, []);
}

void main() {
  const one = Constant.integer(1);
  const wrong = Constant.string('wrong');
  const nil = Constant.nullValue();

  test(
    'static calls and tear-offs reject surviving typed-forwarder guards',
    () {
      final owner = ClassType(_library, 'Guarded');
      final member = FunctionTarget(
        _library,
        'missing',
        .integer,
        [],
        owner: owner,
        kind: .method,
        isAbstract: true,
      );
      final receiver = ObjectConstant(owner, {});
      final definition = IrClass(
        owner,
        [],
        members: [member],
        unsupportedForwarders: {member.selector},
      );
      for (final bind in [false, true]) {
        expect(
          () => _run(
            (b) => b.emit(
              bind
                  ? BindMethod(member, receiver)
                  : InstanceCall(member, receiver, []),
            ),
            classes: [definition],
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  test('null Object bridges and real NoSuchMethodError', () {
    expect(
      _run((b) => b.emit(DynamicDispatch(nil, _selector('toString'), []))),
      'null',
    );
    expect(
      _run((b) => b.emit(DynamicDispatch(nil, _selector('=='), [nil]))),
      true,
    );
    expect(
      () => _run(
        (b) => b.emit(DynamicDispatch(nil, _selector('toString'), [one])),
      ),
      throwsA(isA<NoSuchMethodError>()),
    );
    expect(
      () => _run((b) => b.emit(DynamicDispatch(nil, _selector('missing'), []))),
      throwsA(isA<NoSuchMethodError>()),
    );
    expect(
      _run(
        (b) => b.emit(
          TypeTest(
            b.emit(DynamicDispatch(nil, _selector('runtimeType', .getter), [])),
            .typeType,
          ),
        ),
      ),
      true,
    );
  });

  test('scalar bridges validate shape before argument types', () {
    expect(_run((b) => b.emit(DynamicDispatch(one, _selector('+'), [one]))), 2);
    expect(
      () => _run((b) => b.emit(DynamicDispatch(one, _selector('+'), [wrong]))),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => _run(
        (b) => b.emit(DynamicDispatch(one, _selector('+'), [wrong, one])),
      ),
      throwsA(isA<NoSuchMethodError>()),
    );
    expect(
      _run((b) {
        final f = b.emit(
          DynamicDispatch(one, _selector('toString', .getter), []),
        );
        return b.emit(DynamicDispatch(f, _selector('call'), []));
      }),
      '1',
    );
  });

  test('generic function defaults and shape-before-bound ordering', () {
    final t = TypeParameterType('T')
      ..initializeBound(.number)
      ..initializeDefaultType(.number);
    final target = FunctionTarget(_library, 'id', t, [t], typeParameters: [t]);
    final body = Block(target.parameterTypes);
    body.finish(Return(body.parameters.single));
    final functions = [
      IrFunction(target, [body]),
    ];
    Object? call(
      List<Value> args, [
      List<ValueType> types = const [],
      Map<String, Value> named = const {},
    ]) => _run(
      (b) => b.emit(
        DynamicDispatch(
          FunctionConstant(target),
          _selector('call'),
          args,
          named,
          types,
        ),
      ),
      bodies: functions,
    );
    expect(call([one]), 1);
    expect(() => call([one], [.string]), throwsA(isA<TypeError>()));
    expect(
      () => call([one], [.string], {'wrong': one}),
      throwsA(isA<NoSuchMethodError>()),
    );
    expect(() => call([wrong]), throwsA(isA<TypeError>()));
    expect(
      () => call([one], [.integer, .integer]),
      throwsA(isA<NoSuchMethodError>()),
    );
    expect(
      () => _run(
        (b) => b.emit(
          DynamicDispatch(
            FunctionConstant(target, typeArguments: [.integer]),
            _selector('call'),
            [one],
            {},
            [.integer],
          ),
        ),
        bodies: functions,
      ),
      throwsA(isA<NoSuchMethodError>()),
    );
  });

  test(
    'shape failure never demands absent default metadata or optional values',
    () {
      final t = TypeParameterType('T')..initializeBound(.number);
      final target = FunctionTarget(
        _library,
        'missingDefaults',
        .integer,
        [.integer, .integer],
        namedParameters: {'optional': false, 'required': true},
        typeParameters: [t],
      );
      final block = Block(target.parameterTypes)..finish(Return(one));
      expect(
        () => _run(
          (b) => b.emit(
            DynamicDispatch(FunctionConstant(target), _selector('call'), []),
          ),
          bodies: [
            IrFunction(target, [block], defaults: {0: one}),
          ],
        ),
        throwsA(isA<NoSuchMethodError>()),
      );
    },
  );

  test(
    'user lookup, method tear-offs, custom noSuchMethod and forwarding guard',
    () {
      final owner = ClassType(_library, 'Receiver');
      final method = FunctionTarget(
        _library,
        'value',
        .integer,
        [],
        owner: owner,
        kind: .method,
      );
      final methodBody = Block(method.parameterTypes)..finish(Return(one));
      final handler = FunctionTarget(
        _library,
        'noSuchMethod',
        .dynamicType,
        [CoreTypes.invocation],
        owner: owner,
        kind: .method,
      );
      final handlerBody = Block(handler.parameterTypes);
      handlerBody.finish(Return(handlerBody.parameters.last));
      final definition = IrClass(
        owner,
        [],
        members: [method, handler],
        unsupportedForwarders: {_selector('guarded')},
      );
      final bodies = [
        IrFunction(method, [methodBody]),
        IrFunction(handler, [handlerBody]),
      ];
      final receiver = ObjectConstant(owner, {});
      expect(
        _run(
          (b) => b.emit(DynamicDispatch(receiver, _selector('value'), [])),
          classes: [definition],
          bodies: bodies,
        ),
        1,
      );
      expect(
        _run(
          (b) {
            final tearoff = b.emit(
              DynamicDispatch(receiver, _selector('value', .getter), []),
            );
            return b.emit(DynamicDispatch(tearoff, _selector('call'), []));
          },
          classes: [definition],
          bodies: bodies,
        ),
        1,
      );
      expect(
        _run(
          (b) {
            final invocation = b.emit(
              DynamicDispatch(
                receiver,
                _selector('missing'),
                [one],
                {'z': one, 'a': wrong},
              ),
            );
            return b.emit(
              DynamicDispatch(invocation, _selector('isMethod', .getter), []),
            );
          },
          classes: [definition],
          bodies: bodies,
        ),
        true,
      );
      expect(
        () => _run(
          (b) => b.emit(DynamicDispatch(receiver, _selector('guarded'), [])),
          classes: [definition],
          bodies: bodies,
        ),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'bound Object tear-offs compare by receiver identity and support call',
    () {
      expect(
        _run((b) {
          final first = b.emit(
            DynamicDispatch(nil, _selector('toString', .getter), []),
          );
          final second = b.emit(
            DynamicDispatch(nil, _selector('toString', .getter), []),
          );
          return b.emit(Equals(first, second));
        }),
        true,
      );
      expect(
        _run((b) {
          final first = b.emit(
            DynamicDispatch(nil, _selector('toString', .getter), []),
          );
          final call = b.emit(
            DynamicDispatch(first, _selector('call', .getter), []),
          );
          return b.emit(DynamicDispatch(call, _selector('call'), []));
        }),
        'null',
      );
    },
  );

  test('built-in getter method syntax invokes the getter result', () {
    final owner = ClassType(_library, 'Missing');
    final handler = FunctionTarget(
      _library,
      'noSuchMethod',
      .dynamicType,
      [CoreTypes.invocation],
      owner: owner,
      kind: .method,
    );
    final body = Block(handler.parameterTypes)..finish(Return(one));
    expect(
      () => _run(
        (b) => b.emit(
          DynamicDispatch(ObjectConstant(owner, {}), _selector('hashCode'), []),
        ),
        classes: [
          IrClass(owner, [], members: [handler]),
        ],
        bodies: [
          IrFunction(handler, [body]),
        ],
      ),
      throwsA(isA<NoSuchMethodError>()),
    );
    final record = RecordConstant(RecordType([], {'f': .integer}), [one]);
    expect(
      () => _run((b) => b.emit(DynamicDispatch(record, _selector('f'), []))),
      throwsA(isA<NoSuchMethodError>()),
    );
  });

  test(
    'unmodeled concrete collection runtime types are not public interfaces',
    () {
      final map = MapConstant(CoreTypes.mapOf(.integer, .integer), [
        (one, one),
      ]);
      final set = SequenceConstant(CoreTypes.setOf(.integer), [one]);
      for (final value in [map, set]) {
        expect(
          () => _run(
            (b) => b.emit(
              DynamicDispatch(value, _selector('runtimeType', .getter), []),
            ),
          ),
          throwsUnsupportedError,
        );
      }
    },
  );

  test(
    'runtime Invocation empty collections canonicalize for all selector kinds',
    () {
      final owner = ClassType(_library, 'Capture');
      final handler = FunctionTarget(
        _library,
        'noSuchMethod',
        .dynamicType,
        [CoreTypes.invocation],
        owner: owner,
        kind: .method,
      );
      final body = Block(handler.parameterTypes);
      body.finish(Return(body.parameters.last));
      final identicalTarget = FunctionTarget(
        Uri.parse('dart:core'),
        'identical',
        .boolean,
        [ValueType.object.nullable, ValueType.object.nullable],
      );
      for (final kind in [
        FunctionKind.method,
        FunctionKind.getter,
        FunctionKind.setter,
      ]) {
        final empties = <String, Constant>{
          'typeArguments': SequenceConstant(CoreTypes.listOf(.typeType), []),
          if (kind != .setter)
            'positionalArguments': SequenceConstant(
              CoreTypes.listOf(ValueType.object.nullable),
              [],
            ),
          'namedArguments': MapConstant(
            CoreTypes.mapOf(CoreTypes.symbol, ValueType.object.nullable),
            [],
          ),
        };
        for (final entry in empties.entries) {
          expect(
            _run(
              (b) {
                final invocation = b.emit(
                  DynamicDispatch(
                    ObjectConstant(owner, {}),
                    _selector('missing', kind),
                    kind == .setter ? [one] : [],
                  ),
                );
                final value = b.emit(
                  DynamicDispatch(
                    invocation,
                    _selector(entry.key, .getter),
                    [],
                  ),
                );
                return b.emit(
                  DirectCall(identicalTarget, [value, entry.value]),
                );
              },
              classes: [
                IrClass(owner, [], members: [handler]),
              ],
              bodies: [
                IrFunction(handler, [body]),
              ],
            ),
            true,
            reason: '$kind ${entry.key}',
          );
        }
      }
    },
  );

  test('raw host functions stay an unsupported callable boundary', () {
    final block = Block([ValueType.dynamicType]);
    final result = block.emit(
      DynamicDispatch(block.parameters.single, _selector('call'), []),
    );
    block.finish(Return(result));
    final target = FunctionTarget(_library, 'hostCall', .dynamicType, [
      .dynamicType,
    ]);
    final function = IrFunction(target, [block]);
    final runner = IrInterpreter(IrProgram([], [function]), {});
    expect(() => runner.run(function, [() => 1]), throwsUnsupportedError);
  });

  test('existing unsupported SDK member does not become missing', () {
    final list = SequenceConstant(CoreTypes.listOf(.integer), [one]);
    expect(
      () => _run((b) => b.emit(DynamicDispatch(list, _selector('join'), []))),
      throwsUnsupportedError,
    );
    expect(
      _run(
        (b) => b.emit(DynamicDispatch(list, _selector('length', .getter), [])),
      ),
      1,
    );
  });
}
