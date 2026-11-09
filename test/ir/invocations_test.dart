import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _library = Uri.parse('memory:invocations');
final _nullableObject = ValueType.object.nullable;
final _types = CoreTypes.listOf(ValueType.typeType);
final _positionals = CoreTypes.listOf(ValueType.dynamicType);
final _named = CoreTypes.mapOf(CoreTypes.symbol, ValueType.dynamicType);
final _method = FunctionTarget(
  CoreTypes.invocation.library,
  'method',
  CoreTypes.invocation,
  [
    CoreTypes.symbol,
    CoreTypes.iterableOf(_nullableObject).nullable,
    CoreTypes.mapOf(CoreTypes.symbol, _nullableObject).nullable,
  ],
  owner: CoreTypes.invocation,
  kind: .factory,
  optionalPositional: 1,
);
final _genericMethod = FunctionTarget(
  CoreTypes.invocation.library,
  'genericMethod',
  CoreTypes.invocation,
  [
    CoreTypes.symbol,
    CoreTypes.iterableOf(ValueType.typeType).nullable,
    CoreTypes.iterableOf(_nullableObject).nullable,
    CoreTypes.mapOf(CoreTypes.symbol, _nullableObject).nullable,
  ],
  owner: CoreTypes.invocation,
  kind: .factory,
  optionalPositional: 1,
);
final _getter = FunctionTarget(
  CoreTypes.invocationStorage.library,
  'getter',
  .voidType,
  [CoreTypes.symbol],
  owner: CoreTypes.invocationStorage,
  kind: .initializer,
);
final _setter = FunctionTarget(
  CoreTypes.invocationStorage.library,
  'setter',
  .voidType,
  [CoreTypes.symbol, _nullableObject],
  owner: CoreTypes.invocationStorage,
  kind: .initializer,
);
final _identical = FunctionTarget(
  Uri.parse('dart:core'),
  'identical',
  .boolean,
  [_nullableObject, _nullableObject],
);
const _null = Constant.nullValue();
const _zero = Constant.integer(0);
const _one = Constant.integer(1);

ObjectConstant _symbol(String name) => ObjectConstant(CoreTypes.symbolStorage, {
  CoreTypes.symbolName: Constant.string(name),
  CoreTypes.symbolPrivateLibrary: _null,
});

final _properties = {
  for (final name in [
    'memberName',
    'typeArguments',
    'positionalArguments',
    'namedArguments',
    'isMethod',
    'isGetter',
    'isSetter',
    'isAccessor',
  ])
    name: _property(name, CoreTypes.invocation),
};

FunctionTarget _property(String name, [ClassType? owner]) => owner == null
    ? _properties[name]!
    : FunctionTarget(
        owner.library,
        name,
        switch (name) {
          'memberName' => CoreTypes.symbol,
          'typeArguments' => _types,
          'positionalArguments' => _positionals,
          'namedArguments' => _named,
          _ => ValueType.boolean,
        },
        [],
        owner: owner,
        kind: .getter,
      );

final _factories = {
  'method': _method,
  'genericMethod': _genericMethod,
  for (final kind in ['getter', 'setter'])
    kind: FunctionTarget(
      CoreTypes.invocation.library,
      kind,
      CoreTypes.invocation,
      [CoreTypes.symbol, if (kind == 'setter') _nullableObject],
      owner: CoreTypes.invocation,
      kind: .factory,
      redirect: kind == 'getter' ? _getter : _setter,
    ),
};

Value _get(Block block, Value receiver, String name) =>
    block.emit(InstanceCall(_property(name), receiver, []));

Value _same(Block block, Value a, Value b) =>
    block.emit(DirectCall(_identical, [a, b]));

Value _create(
  Block block,
  String kind, {
  Value? memberName,
  Value? types,
  Value? positional,
  Value? named,
  bool tearoff = false,
  bool omitNamed = false,
}) {
  final symbol = memberName ?? _symbol('name');
  final target = _factories[kind] ?? (throw ArgumentError(kind));
  final args = [
    symbol,
    if (kind == 'genericMethod') types ?? _null,
    if (kind != 'getter') positional ?? _null,
    if ((kind == 'method' || kind == 'genericMethod') && !omitNamed)
      named ?? _null,
  ];
  return tearoff
      ? block.emit(FunctionCall(FunctionConstant(target), args))
      : target.redirect != null
      ? block.emit(Construct(target.redirect!, args))
      : block.emit(DirectCall(target, args));
}

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
  return IrInterpreter(
    IrProgram(classes, [...functions, function]),
    {},
  ).run(function, []);
}

IrFunction _return(FunctionTarget target, Value value) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(Return(value))]);

void main() {
  test('Invocation separates its public interface from final storage', () {
    expect(CoreTypes.invocation.library, Uri.parse('dart:core'));
    expect(CoreTypes.invocation.dartName, 'Invocation');
    expect(CoreTypes.invocation.isAbstract, isTrue);
    expect(CoreTypes.invocationStorage.library, Uri.parse('dart:core'));
    expect(CoreTypes.invocationStorage.dartName, '_Invocation');
    expect(CoreTypes.invocationStorage.isAbstract, isFalse);
    expect(CoreTypes.invocation.accepts(CoreTypes.invocationStorage), isTrue);
    expect(CoreTypes.invocationStorage.accepts(CoreTypes.invocation), isFalse);
    final fields = {
      CoreTypes.invocationMemberName: CoreTypes.symbol,
      CoreTypes.invocationTypeArguments: _types,
      CoreTypes.invocationPositionalArguments: _positionals,
      CoreTypes.invocationNamedArguments: _named,
      CoreTypes.invocationKind: ValueType.integer,
    };
    for (final entry in fields.entries) {
      expect(entry.key.owner, CoreTypes.invocationStorage);
      expect(entry.key.type, entry.value);
      expect(entry.key.isFinal, isTrue);
    }
    expect(() => ObjectConstant(CoreTypes.invocation, {}), throwsArgumentError);
    expect(
      () => ObjectConstant(CoreTypes.invocationStorage, {
        CoreTypes.invocationMemberName: _one,
      }),
      throwsArgumentError,
    );
  });

  test('all factory paths preserve names, shape and nominal identity', () {
    for (final kind in ['method', 'genericMethod', 'getter', 'setter']) {
      for (final tearoff in [false, true]) {
        final name = _symbol(kind == 'setter' ? 'value=' : 'value');
        final nameResult = _execute((b) {
          final value = _create(b, kind, memberName: name, tearoff: tearoff);
          return _same(b, _get(b, value, 'memberName'), name);
        });
        expect(nameResult, isTrue, reason: '$kind tearoff=$tearoff');
        for (final flag in ['isMethod', 'isGetter', 'isSetter', 'isAccessor']) {
          final expected = switch (flag) {
            'isMethod' => kind == 'method' || kind == 'genericMethod',
            'isGetter' => kind == 'getter',
            'isSetter' => kind == 'setter',
            _ => kind == 'getter' || kind == 'setter',
          };
          expect(
            _execute((b) => _get(b, _create(b, kind, tearoff: tearoff), flag)),
            expected,
            reason: '$kind.$flag tearoff=$tearoff',
          );
        }
        expect(
          _execute((b) {
            final value = _create(b, kind, tearoff: tearoff);
            return b.emit(TypeTest(value, CoreTypes.invocationStorage));
          }),
          isTrue,
        );
        expect(
          _execute((b) {
            final a = _create(b, kind, tearoff: tearoff);
            final c = _create(b, kind, tearoff: tearoff);
            return _same(b, a, c);
          }),
          isFalse,
        );
      }
    }
  });

  test('method factory tear-offs bind their omitted named-map default', () {
    for (final kind in ['method', 'genericMethod']) {
      expect(
        _execute((b) {
          final value = _create(b, kind, tearoff: true, omitNamed: true);
          return b.emit(CollectionLength(_get(b, value, 'namedArguments')));
        }),
        0,
      );
    }
  });

  test(
    'source factory body and defaults take priority over builtin fallbacks',
    () {
      final fallback = MapConstant(
        CoreTypes.mapOf(CoreTypes.symbol, _nullableObject),
        [(_symbol('default'), _one)],
      );
      final body = Block(_method.parameterTypes);
      final positional = FunctionTarget(
        CoreTypes.invocation.library,
        'positionalArguments',
        _positionals,
        [],
        owner: CoreTypes.invocation,
        kind: .getter,
        isAbstract: true,
      );
      final value = body.emit(
        Construct(_setter, [body.parameters[0], body.parameters[2]]),
      );
      body.finish(Return(value));
      expect(
        _execute(
          (b) {
            final value = _create(b, 'method', tearoff: true, omitNamed: true);
            final supplied = b.emit(
              CollectionGet(b.emit(InstanceCall(positional, value, [])), _zero),
            );
            return _same(b, supplied, fallback);
          },
          classes: [
            IrClass(
              CoreTypes.invocation,
              [],
              members: [positional],
              constructors: [_method],
            ),
          ],
          functions: [
            IrFunction(_method, [body], defaults: {2: fallback}),
          ],
        ),
        isTrue,
      );
    },
  );

  test('null inputs reuse correctly typed canonical empty constants', () {
    for (final kind in ['method', 'genericMethod', 'getter', 'setter']) {
      final emptyTypes = SequenceConstant(_types, const []);
      final emptyPositional = SequenceConstant(
        CoreTypes.listOf(kind == 'getter' ? ValueType.object : _nullableObject),
        const [],
      );
      final emptyNamed = MapConstant(
        CoreTypes.mapOf(
          CoreTypes.symbol,
          kind == 'getter' || kind == 'setter'
              ? ValueType.object
              : _nullableObject,
        ),
        const [],
      );
      for (final (name, canonical) in [
        ('typeArguments', emptyTypes),
        if (kind != 'setter') ('positionalArguments', emptyPositional),
        ('namedArguments', emptyNamed),
      ]) {
        expect(
          _execute((b) => _same(b, _get(b, _create(b, kind), name), canonical)),
          isTrue,
          reason: '$kind.$name',
        );
        expect(
          _execute((b) {
            final value = _create(b, kind);
            return _same(b, _get(b, value, name), _get(b, value, name));
          }),
          isTrue,
        );
      }
      for (final name in ['positionalArguments', 'namedArguments']) {
        final dynamicEmpty = name == 'positionalArguments'
            ? SequenceConstant(_positionals, const [])
            : MapConstant(_named, const []);
        expect(
          _execute(
            (b) => _same(b, _get(b, _create(b, kind), name), dynamicEmpty),
          ),
          isFalse,
          reason: '$kind.$name does not canonicalize dynamic as Object?',
        );
      }
    }
  });

  test(
    'every provided iterable gets a fresh immutable list, including empties',
    () {
      for (final empty in [false, true]) {
        final types = SequenceConstant(_types, [
          if (!empty) TypeConstant(ValueType.integer),
        ]);
        final positional = SequenceConstant(CoreTypes.listOf(_nullableObject), [
          if (!empty) _one,
        ]);
        for (final (name, source) in [
          ('typeArguments', types),
          ('positionalArguments', positional),
        ]) {
          expect(
            _execute((b) {
              final value = _create(
                b,
                'genericMethod',
                types: types,
                positional: positional,
              );
              return _same(b, _get(b, value, name), source);
            }),
            isFalse,
          );
          expect(
            _execute((b) {
              final a = _create(
                b,
                'genericMethod',
                types: types,
                positional: positional,
              );
              final c = _create(
                b,
                'genericMethod',
                types: types,
                positional: positional,
              );
              return _same(b, _get(b, a, name), _get(b, c, name));
            }),
            isFalse,
          );
          expect(
            () => _execute((b) {
              final value = _create(
                b,
                'genericMethod',
                types: types,
                positional: positional,
              );
              return b.emit(
                CollectionAdd(
                  _get(b, value, name),
                  name == 'typeArguments'
                      ? TypeConstant(ValueType.string)
                      : _one,
                ),
              );
            }),
            throwsUnsupportedError,
          );
        }
      }
    },
  );

  test('empty provided maps canonicalize; nonempty maps always get fresh snapshots', () {
    for (final empty in [false, true]) {
      final named = MapConstant(
        CoreTypes.mapOf(CoreTypes.symbol, _nullableObject),
        [if (!empty) (_symbol('z'), _one)],
      );
      expect(
        _execute(
          (b) => _same(
            b,
            _get(b, _create(b, 'method', named: named), 'namedArguments'),
            named,
          ),
        ),
        empty,
      );
      expect(
        _execute((b) {
          final a = _create(b, 'method', named: named);
          final c = _create(b, 'method', named: named);
          return _same(
            b,
            _get(b, a, 'namedArguments'),
            _get(b, c, 'namedArguments'),
          );
        }),
        empty,
      );
      expect(
        () => _execute((b) {
          final value = _create(b, 'method', named: named);
          return b.emit(
            MapPut(_get(b, value, 'namedArguments'), _symbol('x'), _one),
          );
        }),
        throwsUnsupportedError,
      );
    }
  });

  test(
    'snapshots detach mutable inputs but preserve member and child identities',
    () {
      final customSymbol = ClassType(
        _library,
        'Name',
        interfaces: [CoreTypes.symbol],
      );
      final name = ObjectConstant(customSymbol, {});
      for (final property in [
        'typeArguments',
        'positionalArguments',
        'namedArguments',
      ]) {
        expect(
          _execute((b) {
            final types = b.emit(NewCollection(_types));
            final positional = b.emit(
              NewCollection(CoreTypes.listOf(_nullableObject)),
            );
            final named = b.emit(
              NewCollection(CoreTypes.mapOf(CoreTypes.symbol, _nullableObject)),
            );
            b.emit(CollectionAdd(types, TypeConstant(ValueType.integer)));
            b.emit(CollectionAdd(positional, _one));
            b.emit(MapPut(named, _symbol('x'), _one));
            final value = _create(
              b,
              'genericMethod',
              memberName: name,
              types: types,
              positional: positional,
              named: named,
            );
            b.emit(CollectionAdd(types, TypeConstant(ValueType.string)));
            b.emit(CollectionAdd(positional, _one));
            b.emit(MapPut(named, _symbol('y'), _one));
            return b.emit(CollectionLength(_get(b, value, property)));
          }),
          1,
        );
      }
      for (final kind in ['method', 'genericMethod', 'getter', 'setter']) {
        expect(
          _execute(
            (b) => _same(
              b,
              _get(b, _create(b, kind, memberName: name), 'memberName'),
              name,
            ),
          ),
          isTrue,
        );
      }
      for (final kind in ['method', 'genericMethod', 'setter']) {
        expect(
          _execute((b) {
            final child = b.emit(
              NewCollection(CoreTypes.listOf(ValueType.integer)),
            );
            final positional = b.emit(
              NewCollection(CoreTypes.listOf(_nullableObject)),
            );
            b.emit(CollectionAdd(positional, child));
            final value = _create(
              b,
              kind,
              positional: kind == 'setter' ? child : positional,
            );
            b.emit(CollectionAdd(child, _one));
            final stored = b.emit(
              CollectionGet(_get(b, value, 'positionalArguments'), _zero),
            );
            return _same(b, stored, child);
          }),
          isTrue,
        );
      }
      expect(
        _execute((b) {
          final child = b.emit(
            NewCollection(CoreTypes.listOf(ValueType.integer)),
          );
          final named = b.emit(
            NewCollection(CoreTypes.mapOf(CoreTypes.symbol, _nullableObject)),
          );
          b.emit(MapPut(named, _symbol('x'), child));
          final value = _create(b, 'method', named: named);
          final stored = b.emit(
            CollectionGet(_get(b, value, 'namedArguments'), _symbol('x')),
          );
          return _same(b, stored, child);
        }),
        isTrue,
      );
    },
  );

  test('setter keeps a fresh singleton list, including a null argument', () {
    for (final argument in [_null, _one]) {
      expect(
        _execute((b) {
          final value = _create(b, 'setter', positional: argument);
          return b.emit(
            CollectionLength(_get(b, value, 'positionalArguments')),
          );
        }),
        1,
      );
      expect(
        _execute((b) {
          final value = _create(b, 'setter', positional: argument);
          final stored = b.emit(
            CollectionGet(_get(b, value, 'positionalArguments'), _zero),
          );
          return b.emit(Equals(stored, argument));
        }),
        isTrue,
      );
      expect(
        _execute((b) {
          final a = _create(b, 'setter', positional: argument);
          final c = _create(b, 'setter', positional: argument);
          return _same(
            b,
            _get(b, a, 'positionalArguments'),
            _get(b, c, 'positionalArguments'),
          );
        }),
        isFalse,
      );
      expect(
        () => _execute((b) {
          final value = _create(b, 'setter', positional: argument);
          return b.emit(
            ListSet(_get(b, value, 'positionalArguments'), _zero, _one),
          );
        }),
        throwsUnsupportedError,
      );
    }
  });

  test('public getters dispatch to user implementations and overrides', () {
    for (final extendsInvocation in [false, true]) {
      final custom = ClassType(
        _library,
        'Custom',
        superclass: extendsInvocation ? CoreTypes.invocation : ValueType.object,
        interfaces: extendsInvocation ? [] : [CoreTypes.invocation],
      );
      final child = ClassType(_library, 'Child', superclass: custom);
      final values = <String, Constant>{
        'memberName': _symbol('custom'),
        'typeArguments': SequenceConstant(_types, [
          TypeConstant(ValueType.integer),
        ]),
        'positionalArguments': SequenceConstant(_positionals, [_one]),
        'namedArguments': MapConstant(_named, [(_symbol('x'), _one)]),
        'isMethod': const Constant.boolean(true),
        'isGetter': const Constant.boolean(true),
        'isSetter': const Constant.boolean(true),
        'isAccessor': const Constant.boolean(false),
      };
      final members = {
        for (final name in values.keys) name: _property(name, custom),
      };
      for (final owner in [custom, child]) {
        for (final entry in values.entries) {
          expect(
            _execute(
              (b) => _same(
                b,
                _get(b, ObjectConstant(owner, {}), entry.key),
                entry.value,
              ),
              classes: [
                IrClass(custom, [], members: members.values),
                IrClass(child, []),
              ],
              functions: [
                for (final entry in values.entries)
                  _return(members[entry.key]!, entry.value),
              ],
            ),
            isTrue,
          );
        }
      }
    }
  });

  test(
    'inherited Invocation defaults retain dynamic dispatch and short circuit',
    () {
      for (final getterValue in [false, true]) {
        final custom = ClassType(
          _library,
          'Custom',
          superclass: CoreTypes.invocation,
        );
        final child = ClassType(_library, 'Child', superclass: custom);
        final isGetter = _property('isGetter', custom);
        final isSetter = _property('isSetter', custom);
        final classes = [
          IrClass(custom, [], members: [isGetter, isSetter]),
          IrClass(child, []),
        ];
        final functions = [
          _return(isGetter, Constant.boolean(getterValue)),
          IrFunction(isSetter, [
            Block(isSetter.parameterTypes)
              ..finish(Throw(const Constant.integer(42))),
          ]),
        ];
        for (final type in [custom, child]) {
          final value = ObjectConstant(type, {});
          expect(
            _execute(
              (b) => _same(
                b,
                _get(b, value, 'typeArguments'),
                SequenceConstant(_types, const []),
              ),
              classes: classes,
              functions: functions,
            ),
            isTrue,
          );
          Object? access() => _execute(
            (b) => _get(b, value, 'isAccessor'),
            classes: classes,
            functions: functions,
          );
          if (getterValue) {
            expect(access(), isTrue);
          } else {
            expect(access, throwsA(42));
          }
        }
      }
    },
  );

  test('direct base getter calls do not redispatch an overriding getter', () {
    final custom = ClassType(
      _library,
      'Custom',
      superclass: CoreTypes.invocation,
    );
    final typeArguments = _property('typeArguments', custom);
    final customTypes = SequenceConstant(_types, [
      TypeConstant(ValueType.integer),
    ]);
    expect(
      _execute(
        (b) {
          final result = b.emit(
            DirectCall(_property('typeArguments'), [
              ObjectConstant(custom, {}),
            ]),
          );
          return _same(b, result, SequenceConstant(_types, const []));
        },
        classes: [
          IrClass(custom, [], members: [typeArguments]),
        ],
        functions: [_return(typeArguments, customTypes)],
      ),
      isTrue,
    );
    expect(
      _execute((b) {
        final value = _create(b, 'genericMethod', types: customTypes);
        final result = b.emit(DirectCall(_property('typeArguments'), [value]));
        return _same(b, result, SequenceConstant(_types, const []));
      }),
      isTrue,
    );
  });

  test('Invocation superclass initializer is a no-op', () {
    final custom = ClassType(
      _library,
      'Custom',
      superclass: CoreTypes.invocation,
    );
    final baseInitializer = FunctionTarget(
      CoreTypes.invocation.library,
      'new',
      .voidType,
      [],
      owner: CoreTypes.invocation,
      kind: .initializer,
    );
    final initializer = FunctionTarget(
      _library,
      'new',
      .voidType,
      [],
      owner: custom,
      kind: .initializer,
    );
    final body = Block(initializer.parameterTypes);
    body.emit(DirectCall(baseInitializer, [body.parameters.single]));
    body.finish(Return());
    expect(
      _execute(
        (b) => b.emit(
          TypeTest(b.emit(Construct(initializer, [])), CoreTypes.invocation),
        ),
        classes: [
          IrClass(custom, [], constructors: [initializer]),
        ],
        functions: [
          IrFunction(initializer, [body]),
        ],
      ),
      isTrue,
    );
  });

  test('type element checks precede positional traversal', () {
    final iterator = ClassType(
      _library,
      'InvalidTypesIterator',
      interfaces: [CoreTypes.iteratorOf(ValueType.typeType)],
    );
    final iterable = ClassType(
      _library,
      'InvalidTypes',
      interfaces: [CoreTypes.iterableOf(ValueType.typeType)],
    );
    final positional = ClassType(
      _library,
      'UnvisitedPositional',
      interfaces: [CoreTypes.iterableOf(_nullableObject)],
    );
    final getIterator = FunctionTarget(
      _library,
      'iterator',
      iterator,
      [],
      owner: iterable,
      kind: .getter,
    );
    final moveNext = FunctionTarget(
      _library,
      'moveNext',
      .boolean,
      [],
      owner: iterator,
      kind: .method,
    );
    final current = FunctionTarget(
      _library,
      'current',
      .dynamicType,
      [],
      owner: iterator,
      kind: .getter,
    );
    final poisonIterator = FunctionTarget(
      _library,
      'iterator',
      CoreTypes.iteratorOf(_nullableObject),
      [],
      owner: positional,
      kind: .getter,
    );
    for (final invalid in [_null, _one]) {
      expect(
        () => _execute(
          (b) => _create(
            b,
            'genericMethod',
            types: ObjectConstant(iterable, {}),
            positional: ObjectConstant(positional, {}),
          ),
          classes: [
            IrClass(iterable, [], members: [getIterator]),
            IrClass(iterator, [], members: [moveNext, current]),
            IrClass(positional, [], members: [poisonIterator]),
          ],
          functions: [
            _return(getIterator, ObjectConstant(iterator, {})),
            _return(moveNext, const Constant.boolean(true)),
            _return(current, invalid),
            IrFunction(poisonIterator, [
              Block(poisonIterator.parameterTypes)
                ..finish(Throw(const Constant.integer(42))),
            ]),
          ],
        ),
        throwsA(isA<TypeError>()),
      );
    }
  });

  test(
    'inherited defaults resolve abstract and unrelated interface selectors',
    () {
      for (final redeclaration in [false, true]) {
        final api = ClassType(
          _library,
          'Api',
          superclass: redeclaration ? CoreTypes.invocation : ValueType.object,
          isAbstract: true,
        );
        final typeArguments = FunctionTarget(
          _library,
          'typeArguments',
          _types,
          [],
          owner: api,
          kind: .getter,
          isAbstract: true,
        );
        final isAccessor = FunctionTarget(
          _library,
          'isAccessor',
          .boolean,
          [],
          owner: api,
          kind: .getter,
          isAbstract: true,
        );
        final concrete = ClassType(
          _library,
          'Concrete',
          superclass: redeclaration ? api : CoreTypes.invocation,
          interfaces: redeclaration ? [] : [api],
        );
        final isGetter = _property('isGetter', concrete);
        final isSetter = _property('isSetter', concrete);
        final classes = [
          IrClass(api, [], members: [typeArguments, isAccessor]),
          IrClass(concrete, [], members: [isGetter, isSetter]),
        ];
        final functions = [
          _return(isGetter, const Constant.boolean(false)),
          _return(isSetter, const Constant.boolean(true)),
        ];
        final value = ObjectConstant(concrete, {});
        expect(
          _execute(
            (b) => _same(
              b,
              b.emit(InstanceCall(typeArguments, value, [])),
              SequenceConstant(_types, const []),
            ),
            classes: classes,
            functions: functions,
          ),
          isTrue,
        );
        expect(
          _execute(
            (b) => b.emit(InstanceCall(isAccessor, value, [])),
            classes: classes,
            functions: functions,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'builtin defaults require the real superclass, not interface membership',
    () {
      final implementer = ClassType(
        _library,
        'Implementer',
        interfaces: [CoreTypes.invocation],
      );
      for (final name in ['typeArguments', 'isAccessor', 'memberName']) {
        expect(
          () => _execute((b) => _get(b, ObjectConstant(implementer, {}), name)),
          throwsStateError,
        );
      }
      final lookalike = ClassType(
        CoreTypes.invocation.library,
        'Invocation',
        isAbstract: true,
      );
      final custom = ClassType(
        _library,
        'Custom',
        superclass: lookalike,
        interfaces: [CoreTypes.invocation],
      );
      expect(
        () => _execute(
          (b) => b.emit(
            InstanceCall(
              _property('typeArguments', lookalike),
              ObjectConstant(custom, {}),
              [],
            ),
          ),
        ),
        throwsStateError,
      );
    },
  );
}
