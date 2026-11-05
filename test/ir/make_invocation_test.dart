import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _library = Uri.parse('memory:make-invocation');
const _one = Constant.integer(1);
const _nil = Constant.nullValue();
MemberSelector _selector(
  String name, [
  FunctionKind kind = .method,
  Uri? library,
]) => (name: name, kind: kind, privateLibrary: library);

Value _get(Block b, Value invocation, String name) =>
    b.emit(DynamicDispatch(invocation, _selector(name, .getter), []));
Value _same(Block b, Value a, Value c) => b.emit(
  DirectCall(
    FunctionTarget(Uri.parse('dart:core'), 'identical', .boolean, [
      ValueType.object.nullable,
      ValueType.object.nullable,
    ]),
    [a, c],
  ),
);
Value _at(Block b, Value collection, int index) => b.emit(
  DynamicDispatch(collection, _selector('[]'), [Constant.integer(index)]),
);
Object? _run(Value Function(Block) build) {
  final b = Block();
  final value = build(b);
  b.finish(Return(value));
  final f = IrFunction(FunctionTarget(_library, 'main', value.type, []), [b]);
  return FixtureRunner(IrProgram([], [f]), {}).run(f, []);
}

Value _make(Block b, [FunctionKind kind = .method]) => b.emit(
  MakeInvocation(_selector('value', kind), kind == .setter ? [_one] : []),
);

void main() {
  test('allocation snapshots operands in evaluation order', () {
    final positional = <Value>[_one];
    final named = <String, Value>{'z': _nil, 'a': _one};
    final types = <ValueType>[ValueType.string];
    final op = MakeInvocation(_selector('run'), positional, named, types);
    positional.clear();
    named.clear();
    types.clear();
    expect(op.type, CoreTypes.invocation);
    expect(op.mayThrow, isTrue);
    expect(op.inputs, [_one, _nil, _one]);
    expect(op.named.keys, ['z', 'a']);
    expect(op.typeArguments, [ValueType.string]);
    expect(() => op.positional.clear(), throwsUnsupportedError);
    expect(() => op.named.clear(), throwsUnsupportedError);
    expect(() => op.typeArguments.clear(), throwsUnsupportedError);
  });

  test(
    'invalid selectors, accessor shapes and compiler storage are rejected',
    () {
      for (final selector in [
        _selector(''),
        _selector('x', .function),
        _selector('_x'),
        _selector('x', .method, _library),
      ]) {
        expect(() => MakeInvocation(selector, []), throwsArgumentError);
      }
      for (final kind in [FunctionKind.getter, FunctionKind.setter]) {
        final selector = _selector('x', kind);
        final args = kind == .getter ? <Value>[] : <Value>[_one];
        expect(() => MakeInvocation(selector, args), returnsNormally);
        expect(
          () => MakeInvocation(selector, args, {'x': _one}),
          throwsArgumentError,
        );
        expect(
          () => MakeInvocation(selector, args, {}, [ValueType.string]),
          throwsArgumentError,
        );
        expect(
          () => MakeInvocation(selector, [...args, _one]),
          throwsArgumentError,
        );
      }
      expect(
        () => MakeInvocation(_selector('x', .setter), []),
        throwsArgumentError,
      );
      final cell = Block([CellType(ValueType.integer)]).parameters.single;
      expect(() => MakeInvocation(_selector('x'), [cell]), throwsArgumentError);
      expect(
        () => MakeInvocation(_selector('x'), [], {'x': cell}),
        throwsArgumentError,
      );
      expect(
        () => MakeInvocation(_selector('x'), [], {'': _one}),
        throwsArgumentError,
      );
      expect(
        () => MakeInvocation(_selector('x'), [], {}, [cell.type]),
        throwsArgumentError,
      );
    },
  );

  test('type templates are scoped and formatter retains private selector', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    IrFunction build(List<TypeParameterType> parameters) {
      final b = Block();
      final op = b.emit(
        MakeInvocation(
          _selector('_run', .method, _library),
          [_one],
          {'z': _one, 'a': _nil},
          [CoreTypes.listOf(t)],
        ),
      );
      b.finish(Return(op));
      return IrFunction(
        FunctionTarget(
          _library,
          'scope',
          CoreTypes.invocation,
          [],
          typeParameters: parameters,
        ),
        [b],
      );
    }

    expect(() => build([]), throwsStateError);
    final out = StringBuffer();
    build([t]).writeTo(out);
    expect(
      out.toString(),
      contains(
        'makeInvocation method memory:make-invocation::_run<List<T>>(1, z: 1, a: null)',
      ),
    );
  });

  test('runtime kinds, setter spelling and positional values', () {
    for (final kind in [
      FunctionKind.method,
      FunctionKind.getter,
      FunctionKind.setter,
    ]) {
      for (final flag in ['isMethod', 'isGetter', 'isSetter', 'isAccessor']) {
        expect(_run((b) => _get(b, _make(b, kind), flag)), switch (flag) {
          'isMethod' => kind == .method,
          'isGetter' => kind == .getter,
          'isSetter' => kind == .setter,
          _ => kind != .method,
        });
      }
      expect(
        _run((b) {
          final name = _get(b, _make(b, kind), 'memberName');
          return b.emit(
            DynamicDispatch(name, _selector('=='), [
              ObjectConstant(CoreTypes.symbolStorage, {
                CoreTypes.symbolName: Constant.string(
                  kind == .setter ? 'value=' : 'value',
                ),
                CoreTypes.symbolPrivateLibrary: _nil,
              }),
            ]),
          );
        }),
        isTrue,
      );
    }
    expect(
      _run((b) => _at(b, _get(b, _make(b, .setter), 'positionalArguments'), 0)),
      1,
    );
  });

  test('invocations are fresh and symbols canonical with private identity', () {
    for (final property in [null, 'memberName']) {
      expect(
        _run((b) {
          final a = _make(b);
          final c = _make(b);
          return _same(
            b,
            property == null ? a : _get(b, a, property),
            property == null ? c : _get(b, c, property),
          );
        }),
        property == null ? isFalse : isTrue,
      );
    }
    for (final sameLibrary in [false, true]) {
      expect(
        _run((b) {
          final a = b.emit(
            MakeInvocation(_selector('_run', .method, _library), []),
          );
          final c = b.emit(
            MakeInvocation(
              _selector(
                '_run',
                .method,
                sameLibrary ? _library : Uri.parse('memory:other'),
              ),
              [],
            ),
          );
          return b.emit(
            DynamicDispatch(_get(b, a, 'memberName'), _selector('=='), [
              _get(b, c, 'memberName'),
            ]),
          );
        }),
        sameLibrary,
      );
    }
  });

  test('typed empty lists canonicalize but named maps stay fresh', () {
    for (final property in [
      'typeArguments',
      'namedArguments',
      'positionalArguments',
    ]) {
      expect(
        _run(
          (b) => _same(
            b,
            _get(b, _make(b), property),
            _get(b, _make(b, .getter), property),
          ),
        ),
        property == 'namedArguments' ? isFalse : isTrue,
      );
    }
    expect(
      _run(
        (b) => _same(
          b,
          _get(b, _make(b), 'namedArguments'),
          _get(b, _make(b, .setter), 'namedArguments'),
        ),
      ),
      isFalse,
    );
  });

  test('named arguments retain supplied order and symbols are canonical', () {
    Value key(Block b, Value invocation, int index) {
      final map = b.emit(
        TypeCast(
          _get(b, invocation, 'namedArguments'),
          CoreTypes.mapOf(CoreTypes.symbol, ValueType.dynamicType),
        ),
      );
      final entries = b.emit(MapEntries(map));
      final iterator = b.emit(GetIterator(entries));
      for (var i = 0; i <= index; i++) {
        b.emit(IteratorMoveNext(iterator));
      }
      return b.emit(
        LoadField(CoreTypes.mapEntryKey, b.emit(IteratorCurrent(iterator))),
      );
    }

    Value make(Block b) =>
        b.emit(MakeInvocation(_selector('run'), [], {'z': _nil, 'a': _one}));
    expect(
      _run(
        (b) => b.emit(
          DynamicDispatch(key(b, make(b), 0), _selector('toString'), []),
        ),
      ),
      'Symbol("z")',
    );
    expect(
      _run((b) => _same(b, key(b, make(b), 0), key(b, make(b), 0))),
      isTrue,
    );
  });

  test('typed canonical values match literal symbols and empty lists', () {
    final name = ObjectConstant(CoreTypes.symbolStorage, {
      CoreTypes.symbolName: const Constant.string('value'),
      CoreTypes.symbolPrivateLibrary: _nil,
    });
    final constants = <String, Value>{
      'memberName': name,
      'typeArguments': SequenceConstant(
        CoreTypes.listOf(ValueType.typeType),
        [],
      ),
      'positionalArguments': SequenceConstant(
        CoreTypes.listOf(ValueType.dynamicType),
        [],
      ),
    };
    for (final entry in constants.entries) {
      expect(
        _run(
          (b) => _same(b, _get(b, _make(b, .getter), entry.key), entry.value),
        ),
        isTrue,
      );
    }
    for (final property in [
      'positionalArguments',
      'typeArguments',
      'namedArguments',
    ]) {
      expect(
        _run((b) {
          Value make() => b.emit(
            MakeInvocation(_selector('run'), [_one], {'x': _one}, [
              ValueType.string,
            ]),
          );
          return _same(b, _get(b, make(), property), _get(b, make(), property));
        }),
        isFalse,
      );
    }
  });

  test('runtime accessor empties differ from public factory empties', () {
    final getter = FunctionTarget(
      CoreTypes.invocationStorage.library,
      'getter',
      .voidType,
      [CoreTypes.symbol],
      owner: CoreTypes.invocationStorage,
      kind: .initializer,
    );
    final name = ObjectConstant(CoreTypes.symbolStorage, {
      CoreTypes.symbolName: const Constant.string('value'),
      CoreTypes.symbolPrivateLibrary: _nil,
    });
    for (final property in ['positionalArguments', 'namedArguments']) {
      expect(
        _run((b) {
          final runtime = _make(b, .getter);
          final public = b.emit(Construct(getter, [name]));
          return _same(
            b,
            _get(b, runtime, property),
            _get(b, public, property),
          );
        }),
        isFalse,
      );
    }
  });

  test('argument snapshots are immutable', () {
    for (final property in [
      'positionalArguments',
      'typeArguments',
      'namedArguments',
    ]) {
      expect(
        () => _run((b) {
          final invocation = b.emit(
            MakeInvocation(_selector('run'), [_one], {'x': _one}, [
              ValueType.string,
            ]),
          );
          return b.emit(
            DynamicDispatch(
              _get(b, invocation, property),
              _selector('clear'),
              [],
            ),
          );
        }),
        throwsUnsupportedError,
      );
    }
  });

  test('generic templates resolve before type values are captured', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final target = FunctionTarget(
      _library,
      'generic',
      CoreTypes.invocation,
      [],
      typeParameters: [t],
    );
    final body = Block();
    final invocation = body.emit(
      MakeInvocation(_selector('run'), [], {}, [CoreTypes.listOf(t)]),
    );
    body.finish(Return(invocation));
    final generic = IrFunction(target, [body]);
    final b = Block();
    final value = b.emit(
      DirectCall(target, [], typeArguments: [ValueType.string]),
    );
    final type = _at(b, _get(b, value, 'typeArguments'), 0);
    b.finish(
      Return(_same(b, type, TypeConstant(CoreTypes.listOf(ValueType.string)))),
    );
    final main = IrFunction(FunctionTarget(_library, 'main', .boolean, []), [
      b,
    ]);
    expect(
      FixtureRunner(IrProgram([], [generic, main]), {}).run(main, []),
      isTrue,
    );
  });
}
