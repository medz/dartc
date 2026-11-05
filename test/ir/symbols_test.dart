import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _library = Uri.parse('memory:symbols');
final _constructor = FunctionTarget(
  CoreTypes.symbolStorage.library,
  'new',
  .voidType,
  [.string],
  owner: CoreTypes.symbolStorage,
  kind: .initializer,
);
final _factory = FunctionTarget(
  CoreTypes.symbol.library,
  'new',
  CoreTypes.symbol,
  [.string],
  owner: CoreTypes.symbol,
  kind: .factory,
  redirect: _constructor,
);
final _hashCode = FunctionTarget(
  CoreTypes.symbol.library,
  'hashCode',
  .integer,
  [],
  owner: CoreTypes.symbol,
  kind: .getter,
  isAbstract: true,
);
final _toString = FunctionTarget(
  ValueType.object.library,
  'toString',
  .string,
  [],
  owner: ValueType.object,
  kind: .method,
);
final _identical = FunctionTarget(
  Uri.parse('dart:core'),
  'identical',
  .boolean,
  [ValueType.object.nullable, ValueType.object.nullable],
);

ObjectConstant _symbol(String name, [String? privateLibrary]) =>
    ObjectConstant(CoreTypes.symbolStorage, {
      CoreTypes.symbolName: Constant.string(name),
      CoreTypes.symbolPrivateLibrary: privateLibrary == null
          ? const Constant.nullValue()
          : Constant.string(privateLibrary),
    });

Object? _execute(
  Value Function(Block) build, {
  List<IrClass> classes = const [],
  List<IrFunction> functions = const [],
}) {
  final block = Block();
  final result = build(block);
  block.finish(Return(result));
  final function = IrFunction(
    FunctionTarget(_library, 'test', result.type, []),
    [block],
  );
  return FixtureRunner(
    IrProgram(classes, [...functions, function]),
    {},
  ).run(function, []);
}

IrFunction _return(FunctionTarget target, Constant value) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(Return(value))]);

void main() {
  test('Symbol separates its public interface from final built-in storage', () {
    expect(CoreTypes.symbol.library, Uri.parse('dart:core'));
    expect(CoreTypes.symbol.isAbstract, isTrue);
    expect(CoreTypes.symbolStorage.library, Uri.parse('dart:_internal'));
    expect(CoreTypes.symbolStorage.dartName, 'Symbol');
    expect(CoreTypes.symbolStorage.isAbstract, isFalse);
    expect(CoreTypes.symbol.accepts(CoreTypes.symbolStorage), isTrue);
    expect(CoreTypes.symbolStorage.accepts(CoreTypes.symbol), isFalse);
    expect(CoreTypes.symbolName.owner, CoreTypes.symbolStorage);
    expect(CoreTypes.symbolName.type, ValueType.string);
    expect(CoreTypes.symbolName.isFinal, isTrue);
    expect(CoreTypes.symbolPrivateLibrary.owner, CoreTypes.symbolStorage);
    expect(CoreTypes.symbolPrivateLibrary.type, ValueType.string.nullable);
    expect(CoreTypes.symbolPrivateLibrary.isFinal, isTrue);
    expect(() => ObjectConstant(CoreTypes.symbol, {}), throwsArgumentError);
    expect(
      () => ObjectConstant(CoreTypes.symbolStorage, {
        CoreTypes.symbolName: const Constant.integer(1),
      }),
      throwsArgumentError,
    );
  });

  test('Symbol constants use ordinary canonical object storage', () {
    final first = _symbol('value');
    final second = _symbol('value');
    expect(constantKey(first), constantKey(second));
    expect(
      _execute((b) => b.emit(DirectCall(_identical, [first, second]))),
      isTrue,
    );
    expect(
      _execute((b) => b.emit(LoadField(CoreTypes.symbolName, first))),
      'value',
    );
    expect(
      _execute((b) => b.emit(LoadField(CoreTypes.symbolPrivateLibrary, first))),
      isNull,
    );
  });

  test(
    'runtime Symbol construction is fresh but equal to matching constants',
    () {
      const name = Constant.string('value');
      expect(
        _execute((b) {
          final first = b.emit(Construct(_constructor, [name]));
          final second = b.emit(Construct(_constructor, [name]));
          return b.emit(DirectCall(_identical, [first, second]));
        }),
        isFalse,
      );
      expect(
        _execute((b) {
          final value = b.emit(Construct(_constructor, [name]));
          return b.emit(DirectCall(_identical, [value, _symbol('value')]));
        }),
        isFalse,
      );
      expect(
        _execute((b) {
          final value = b.emit(Construct(_constructor, [name]));
          return b.emit(Equals(value, _symbol('value')));
        }),
        isTrue,
      );
      expect(
        _execute((b) {
          final value = b.emit(Construct(_constructor, [name]));
          return b.emit(LoadField(CoreTypes.symbolPrivateLibrary, value));
        }),
        isNull,
      );
    },
  );

  test('Symbol retains its actual nominal type through widened views', () {
    expect(
      _execute((b) {
        final value = b.emit(TypeView(_symbol('value'), ValueType.object));
        return b.emit(TypeTest(value, CoreTypes.symbol));
      }),
      isTrue,
    );
    expect(
      _execute((b) {
        final value = b.emit(TypeView(_symbol('value'), ValueType.object));
        return b.emit(TypeTest(value, CoreTypes.symbolStorage));
      }),
      isTrue,
    );
  });

  test('private library provenance participates in identity and equality', () {
    final public = _symbol('_name');
    final first = _symbol('_name', 'package:a/a.dart');
    final same = _symbol('_name', 'package:a/a.dart');
    final other = _symbol('_name', 'package:b/b.dart');
    expect(constantKey(first), constantKey(same));
    expect(constantKey(first), isNot(constantKey(other)));
    expect(constantKey(first), isNot(constantKey(public)));
    expect(
      _execute((b) => b.emit(DirectCall(_identical, [first, same]))),
      isTrue,
    );
    for (final different in [
      other,
      public,
      _symbol('_other', 'package:a/a.dart'),
    ]) {
      expect(_execute((b) => b.emit(Equals(first, different))), isFalse);
      expect(
        _execute((b) => b.emit(DirectCall(_identical, [first, different]))),
        isFalse,
      );
    }
    expect(
      _execute((b) => b.emit(ObjectHashCode(first))),
      _execute((b) => b.emit(ObjectHashCode(same))),
    );
    expect(
      _execute((b) => b.emit(InstanceCall(_toString, first, []))),
      Symbol('_name').toString(),
    );
  });

  test(
    'Symbol accepts arbitrary strings and uses host hash and formatting',
    () {
      for (final name in [
        '',
        'name',
        '_name',
        'foo._bar',
        '[]=',
        'unary-',
        'a b',
        '"\\\n',
        'get:foo',
        'set:foo',
        'abc@123',
        '_A@123._b@456',
      ]) {
        final value = _symbol(name);
        expect(
          _execute((b) => b.emit(ObjectHashCode(value))),
          Symbol(name).hashCode,
          reason: name,
        );
        expect(
          _execute((b) => b.emit(InstanceCall(_hashCode, value, []))),
          Symbol(name).hashCode,
          reason: name,
        );
        expect(
          _execute((b) => b.emit(InstanceCall(_toString, value, []))),
          Symbol(name).toString(),
          reason: name,
        );
        expect(
          _execute((b) {
            final instance = b.emit(
              Construct(_constructor, [Constant.string(name)]),
            );
            return b.emit(Equals(instance, value));
          }),
          isTrue,
          reason: name,
        );
      }
    },
  );

  test('Symbol toString extraction shares dispatch with direct invocation', () {
    final value = _symbol('get:foo');
    expect(
      _execute((b) {
        final method = b.emit(BindMethod(_toString, value));
        return b.emit(FunctionCall(method, []));
      }),
      Symbol('get:foo').toString(),
    );
    expect(
      _execute((b) {
        final first = b.emit(BindMethod(_toString, value));
        final second = b.emit(BindMethod(_toString, value));
        return b.emit(Equals(first, second));
      }),
      isTrue,
    );
  });

  test(
    'Symbol.new tear-offs resolve the factory to fresh built-in storage',
    () {
      final constructor = FunctionConstant(_factory);
      expect(
        _execute((b) {
          final value = b.emit(
            FunctionCall(constructor, [const Constant.string('x')]),
          );
          return b.emit(Equals(value, _symbol('x')));
        }),
        isTrue,
      );
      expect(
        _execute((b) {
          final first = b.emit(
            FunctionCall(constructor, [const Constant.string('x')]),
          );
          final second = b.emit(
            FunctionCall(constructor, [const Constant.string('x')]),
          );
          return b.emit(DirectCall(_identical, [first, second]));
        }),
        isFalse,
      );
      expect(
        _execute(
          (b) => b.emit(
            TypeTest(constructor, FunctionType(CoreTypes.symbol, [.string])),
          ),
        ),
        isTrue,
      );
    },
  );

  test('direct Object.toString keeps its implementation on Symbol storage', () {
    final value = _symbol('name');
    expect(
      _execute((b) => b.emit(DirectCall(_toString, [value]))),
      "Instance of 'Symbol'",
    );
    expect(
      _execute((b) {
        final method = b.emit(BindMethod(_toString, value, direct: true));
        return b.emit(FunctionCall(method, []));
      }),
      "Instance of 'Symbol'",
    );
    expect(
      _execute((b) {
        final direct = b.emit(BindMethod(_toString, value, direct: true));
        final virtual = b.emit(BindMethod(_toString, value));
        return b.emit(Equals(direct, virtual));
      }),
      isFalse,
    );
    expect(
      _execute((b) => b.emit(InstanceCall(_toString, value, []))),
      Symbol('name').toString(),
    );
  });

  test(
    'direct Object.toString inside a Symbol override does not redispatch',
    () {
      final custom = ClassType(
        _library,
        'Custom',
        interfaces: [CoreTypes.symbol],
      );
      final method = FunctionTarget(
        _library,
        'toString',
        .string,
        [],
        owner: custom,
        kind: .method,
      );
      final body = Block(method.parameterTypes);
      body.finish(Return(body.emit(DirectCall(_toString, body.parameters))));
      final classes = [
        IrClass(custom, [], members: [method]),
      ];
      final functions = [
        IrFunction(method, [body]),
      ];
      final value = ObjectConstant(custom, {});
      expect(
        _execute(
          (b) => b.emit(InstanceCall(_toString, value, [])),
          classes: classes,
          functions: functions,
        ),
        "Instance of 'Custom'",
      );
      expect(
        _execute(
          (b) {
            final bound = b.emit(BindMethod(_toString, value));
            return b.emit(FunctionCall(bound, []));
          },
          classes: classes,
          functions: functions,
        ),
        "Instance of 'Custom'",
      );
    },
  );

  test(
    'user Symbol implementations retain equality, hashCode and toString',
    () {
      final custom = ClassType(
        _library,
        'Custom',
        interfaces: [CoreTypes.symbol],
      );
      final child = ClassType(_library, 'Child', superclass: custom);
      final equality = FunctionTarget(
        _library,
        '==',
        .boolean,
        [.object],
        owner: custom,
        kind: .method,
      );
      final hash = FunctionTarget(
        _library,
        'hashCode',
        .integer,
        [],
        owner: custom,
        kind: .getter,
      );
      final string = FunctionTarget(
        _library,
        'toString',
        .string,
        [],
        owner: custom,
        kind: .method,
      );
      final classes = [
        IrClass(custom, [], members: [equality, hash, string]),
        IrClass(child, []),
      ];
      final functions = [
        _return(equality, const Constant.boolean(true)),
        _return(hash, const Constant.integer(37)),
        _return(string, const Constant.string('custom')),
      ];
      Object? run(Value Function(Block) build) =>
          _execute(build, classes: classes, functions: functions);
      for (final type in [custom, child]) {
        final value = ObjectConstant(type, {});
        expect(run((b) => b.emit(Equals(_symbol('x'), value))), isFalse);
        expect(run((b) => b.emit(Equals(value, _symbol('x')))), isTrue);
        expect(run((b) => b.emit(ObjectHashCode(value))), 37);
        expect(run((b) => b.emit(InstanceCall(_hashCode, value, []))), 37);
        expect(
          run((b) => b.emit(InstanceCall(_toString, value, []))),
          'custom',
        );
        expect(
          run((b) {
            final method = b.emit(BindMethod(_toString, value));
            return b.emit(FunctionCall(method, []));
          }),
          'custom',
        );
      }
    },
  );

  test('user Symbol implementations inherit ordinary Object fallback', () {
    final custom = ClassType(
      _library,
      'Custom',
      interfaces: [CoreTypes.symbol],
    );
    final value = ObjectConstant(custom, {});
    final classes = [IrClass(custom, [])];
    final block = Block();
    final hash = block.emit(InstanceCall(_hashCode, value, []));
    final objectHash = block.emit(ObjectHashCode(value));
    block.finish(Return(block.emit(Equals(hash, objectHash))));
    final function = IrFunction(
      FunctionTarget(_library, 'hash', .boolean, []),
      [block],
    );
    expect(
      FixtureRunner(IrProgram(classes, [function]), {}).run(function, []),
      isTrue,
    );
    expect(
      _execute(
        (b) => b.emit(InstanceCall(_toString, value, [])),
        classes: classes,
      ),
      "Instance of 'Custom'",
    );
  });

  test('Object hash retains direct selection without changing ordinary IR', () {
    final block = Block([ValueType.object]);
    final receiver = block.parameters.single;
    final virtual = block.emit(ObjectHashCode(receiver));
    final direct = block.emit(ObjectHashCode(receiver, direct: true));
    expect(virtual.direct, isFalse);
    expect(direct.direct, isTrue);
    for (final hash in [virtual, direct]) {
      expect(hash.type, ValueType.integer);
      expect(hash.inputs, [receiver]);
      expect(hash.mayThrow, isTrue);
    }
    block.finish(Return(direct));
    final function = IrFunction(
      FunctionTarget(_library, 'hash', .integer, [.object]),
      [block],
    );
    final text = StringBuffer();
    function.writeTo(text);
    expect(text.toString(), contains(' = hashCode %0'));
    expect(text.toString(), contains(' = direct hashCode %0'));
    expect(
      () => ObjectHashCode(NewCell(CellType(.integer), null), direct: true),
      throwsArgumentError,
    );
  });

  test(
    'super Object hash uses stable identity without redispatching overrides',
    () {
      for (final symbol in [false, true]) {
        final custom = ClassType(
          _library,
          'Custom',
          interfaces: [if (symbol) CoreTypes.symbol],
        );
        final method = FunctionTarget(
          _library,
          'hashCode',
          .integer,
          [],
          owner: custom,
          kind: .getter,
        );
        final body = Block(method.parameterTypes);
        final identity = body.emit(
          ObjectHashCode(body.parameters.single, direct: true),
        );
        body.finish(
          Return(
            body.emit(IntBinary(.add, identity, const Constant.integer(1))),
          ),
        );
        final classes = [
          IrClass(custom, [], members: [method]),
        ];
        final functions = [
          IrFunction(method, [body]),
        ];
        final value = ObjectConstant(custom, {});
        expect(
          _execute(
            (b) {
              final virtual = b.emit(ObjectHashCode(value));
              final direct = b.emit(ObjectHashCode(value, direct: true));
              return b.emit(IntBinary(.subtract, virtual, direct));
            },
            classes: classes,
            functions: functions,
          ),
          1,
        );
        expect(
          _execute(
            (b) {
              final first = b.emit(ObjectHashCode(value, direct: true));
              b.emit(ObjectHashCode(value));
              final second = b.emit(ObjectHashCode(value, direct: true));
              return b.emit(Equals(first, second));
            },
            classes: classes,
            functions: functions,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'Symbol fallback requires exact owners and rejects unmodeled objects',
    () {
      final lookalike = ClassType(
        CoreTypes.symbol.library,
        'Symbol',
        isAbstract: true,
      );
      final custom = ClassType(
        _library,
        'Custom',
        interfaces: [CoreTypes.symbol, lookalike],
      );
      final hash = FunctionTarget(
        lookalike.library,
        'hashCode',
        .integer,
        [],
        owner: lookalike,
        kind: .getter,
      );
      expect(
        () => _execute(
          (b) => b.emit(InstanceCall(hash, ObjectConstant(custom, {}), [])),
        ),
        throwsStateError,
      );
      final plain = ClassType(_library, 'Plain');
      expect(
        () => _execute(
          (b) => b.emit(InstanceCall(_toString, ObjectConstant(plain, {}), [])),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => _execute(
          (b) => b.emit(BindMethod(_toString, ObjectConstant(plain, {}))),
        ),
        throwsUnsupportedError,
      );
    },
  );
}
