import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../lowering/fixture_runner.dart';

final _library = Uri.parse('memory:private-selectors');
final _foreign = Uri.parse('memory:foreign');

IrFunction _body(FunctionTarget target, int value) {
  final block = Block(target.parameterTypes)
    ..finish(Return(Constant.integer(value)));
  return IrFunction(target, [block]);
}

Object? _run(
  Value Function(Block) build, {
  List<IrClass> classes = const [],
  List<IrFunction> bodies = const [],
}) {
  final block = Block();
  final value = build(block);
  block.finish(Return(value));
  final function = IrFunction(
    FunctionTarget(_library, 'main', value.type, []),
    [block],
  );
  return FixtureRunner(
    IrProgram(classes, [function, ...bodies]),
    {},
  ).run(function, []);
}

void main() {
  test('private provenance is limited to virtual private selectors', () {
    final owner = ClassType(_library, 'C');
    for (final kind in FunctionKind.values) {
      if (kind.isVirtual) continue;
      expect(
        () => FunctionTarget(
          _library,
          '_f',
          kind == .factory ? owner : ValueType.voidType,
          [],
          owner: owner,
          kind: kind,
          privateSelectorLibrary: _foreign,
        ),
        throwsArgumentError,
      );
    }
    for (final kind in [
      FunctionKind.method,
      FunctionKind.getter,
      FunctionKind.setter,
    ]) {
      final parameters = kind == .setter ? [ValueType.integer] : <ValueType>[];
      expect(
        () => FunctionTarget(
          _library,
          'f',
          .voidType,
          parameters,
          owner: owner,
          kind: kind,
          privateSelectorLibrary: _foreign,
        ),
        throwsArgumentError,
      );
      final target = FunctionTarget(
        _library,
        '_f',
        .voidType,
        parameters,
        owner: owner,
        kind: kind,
        privateSelectorLibrary: _foreign,
      );
      expect(target.library, _library);
      expect(target.owner, owner);
      expect(target.selector.privateLibrary, _foreign);
    }
    expect(
      () => FunctionTarget(
        _foreign,
        '_f',
        .integer,
        [],
        owner: owner,
        kind: .method,
        privateSelectorLibrary: _library,
      ),
      throwsArgumentError,
    );
  });

  test('two foreign and own selectors retain separate bodies and dispatch', () {
    final owner = ClassType(_library, 'C');
    final targets = [
      for (final provenance in [null, _foreign, Uri.parse('memory:other')])
        FunctionTarget(
          _library,
          '_f',
          .integer,
          [],
          owner: owner,
          kind: .method,
          privateSelectorLibrary: provenance,
        ),
    ];
    final definition = IrClass(owner, [], members: targets);
    final bodies = [
      for (final (i, target) in targets.indexed) _body(target, i),
    ];
    final program = IrProgram([definition], bodies);
    for (final (i, target) in targets.indexed) {
      expect(program.dispatch(owner, target), same(target));
      expect(program.lookupMember(owner, target.selector).target, same(target));
      expect(
        _run(
          (b) => b.emit(
            DynamicDispatch(ObjectConstant(owner, {}), target.selector, []),
          ),
          classes: [definition],
          bodies: bodies,
        ),
        i,
      );
      expect(
        _run(
          (b) => b.emit(InstanceCall(target, ObjectConstant(owner, {}), [])),
          classes: [definition],
          bodies: bodies,
        ),
        i,
      );
    }
    expect(
      () => IrProgram([definition], [...bodies, bodies[1]]),
      throwsArgumentError,
    );
    final duplicate = FunctionTarget(
      _library,
      '_f',
      .integer,
      [],
      owner: owner,
      kind: .method,
      privateSelectorLibrary: _foreign,
    );
    expect(
      () => IrClass(owner, [], members: [...targets, duplicate]),
      throwsArgumentError,
    );
    final output = StringBuffer();
    program.writeTo(output);
    expect(
      output.toString(),
      contains('memory:private-selectors::C._f [private memory:foreign]'),
    );
    expect(
      output.toString(),
      contains('memory:private-selectors::C._f [private memory:other]'),
    );
    final ownOutput = StringBuffer();
    bodies.first.writeTo(ownOutput);
    expect(ownOutput.toString(), isNot(contains('[private')));
    final explicitOwn = FunctionTarget(
      _library,
      '_f',
      .integer,
      [],
      owner: owner,
      kind: .method,
      privateSelectorLibrary: _library,
    );
    final explicitOutput = StringBuffer();
    _body(explicitOwn, 0).writeTo(explicitOutput);
    expect(explicitOutput.toString(), ownOutput.toString());
  });

  final objectNoSuchMethod = FunctionTarget(
    ValueType.object.library,
    'noSuchMethod',
    .dynamicType,
    [CoreTypes.invocation],
    owner: ValueType.object,
    kind: .method,
  );
  const missing = (
    kind: FunctionKind.method,
    name: 'missing',
    privateLibrary: null,
  );

  test('virtual Object.noSuchMethod falls back only after proven absence', () {
    final owner = ClassType(_library, 'C');
    Value call(Block b, ClassType type) => b.emit(
      InstanceCall(objectNoSuchMethod, ObjectConstant(type, {}), [
        b.emit(MakeInvocation(missing, [])),
      ]),
    );
    expect(
      () => _run((b) => call(b, owner), classes: [IrClass(owner, [])]),
      throwsA(isA<NoSuchMethodError>()),
    );
    final imported = ClassType(_foreign, 'Imported');
    final child = ClassType(_library, 'Child', superclass: imported);
    expect(
      () => _run((b) => call(b, child), classes: [IrClass(child, [])]),
      throwsStateError,
    );
    expect(
      () => _run(
        (b) => call(b, owner),
        classes: [
          IrClass(
            owner,
            [],
            unsupportedForwarders: [objectNoSuchMethod.selector],
          ),
        ],
      ),
      throwsUnsupportedError,
    );
    final override = FunctionTarget(
      _library,
      'noSuchMethod',
      .integer,
      [CoreTypes.invocation],
      owner: owner,
      kind: .method,
    );
    expect(
      _run(
        (b) => call(b, owner),
        classes: [
          IrClass(owner, [], members: [override]),
        ],
        bodies: [_body(override, 42)],
      ),
      42,
    );
  });

  final factory = FunctionTarget(
    ValueType.noSuchMethodError.library,
    'withInvocation',
    ValueType.noSuchMethodError,
    [ValueType.object.nullable, CoreTypes.invocation],
    owner: ValueType.noSuchMethodError,
    kind: .factory,
  );

  test(
    'error factory returns fresh errors without reading guest Invocation',
    () {
      // An unmodeled Invocation implementation has no readable getters. Merely
      // constructing the error must not try to resolve any of them.
      final invocationType = ClassType(
        _library,
        'LazyInvocation',
        interfaces: [CoreTypes.invocation],
      );
      final invocation = ObjectConstant(invocationType, {});
      Value create(Block b) =>
          b.emit(DirectCall(factory, [const Constant.nullValue(), invocation]));
      expect(_run(create), isA<NoSuchMethodError>());
      final identical = FunctionTarget(
        Uri.parse('dart:core'),
        'identical',
        .boolean,
        [ValueType.object.nullable, ValueType.object.nullable],
      );
      expect(
        _run((b) => b.emit(DirectCall(identical, [create(b), create(b)]))),
        false,
      );
      expect(_run((b) => b.emit(TypeTest(create(b), ValueType.error))), true);
    },
  );
}
