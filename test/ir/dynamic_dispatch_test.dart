import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final _library = Uri.parse('memory:dynamic');
const _receiver = Constant.nullValue();
const _one = Constant.integer(1);

MemberSelector _selector(
  String name, {
  FunctionKind kind = .method,
  Uri? privateLibrary,
}) => (kind: kind, name: name, privateLibrary: privateLibrary);

IrFunction _body(FunctionTarget target) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(Return(_one))]);

FunctionTarget _member(
  ClassType owner, {
  String name = 'run',
  FunctionKind kind = .method,
  bool isAbstract = false,
  List<ValueType> parameters = const [],
}) => FunctionTarget(
  owner.library,
  name,
  ValueType.integer,
  parameters,
  owner: owner,
  kind: kind,
  isAbstract: isAbstract,
);

void main() {
  test('dynamic dispatch preserves unconverted operands and source order', () {
    final positional = <Value>[_one];
    final named = <String, Value>{'z': const Constant.string('z'), 'a': _one};
    final types = <ValueType>[ValueType.string];
    final op = DynamicDispatch(
      _receiver,
      _selector('run'),
      positional,
      named,
      types,
    );
    positional.clear();
    named.clear();
    types.clear();
    expect(op.type, ValueType.dynamicType);
    expect(op.mayThrow, isTrue);
    expect(op.inputs.toList(), [
      _receiver,
      _one,
      const Constant.string('z'),
      _one,
    ]);
    expect(op.named.keys, ['z', 'a']);
    expect(op.typeArguments, [ValueType.string]);
    expect(() => op.positional.clear(), throwsUnsupportedError);
    expect(() => op.named.clear(), throwsUnsupportedError);
    expect(() => op.typeArguments.clear(), throwsUnsupportedError);
    // No resolved target exists: nonsensical runtime shapes are still valid IR.
    expect(
      () => DynamicDispatch(
        _one,
        _selector('anything'),
        [_receiver, _one],
        {'unknown': _one},
        [ValueType.integer, ValueType.string],
      ),
      returnsNormally,
    );
  });

  test('selectors require virtual operations and exact private identity', () {
    for (final selector in [
      _selector(''),
      _selector('run', kind: .function),
      _selector('run', kind: .staticGetter),
      _selector('_run'),
      _selector('run', privateLibrary: _library),
    ]) {
      expect(
        () => DynamicDispatch(_receiver, selector, []),
        throwsArgumentError,
      );
      expect(
        () => IrClass(
          ClassType(_library, 'C'),
          [],
          unsupportedForwarders: [selector],
        ),
        throwsArgumentError,
      );
      expect(
        () => IrProgram([], []).lookupMember(ValueType.object, selector),
        throwsArgumentError,
      );
    }
    expect(
      () => DynamicDispatch(
        _receiver,
        _selector('_run', privateLibrary: _library),
        [],
      ),
      returnsNormally,
    );
    expect(
      () => DynamicDispatch(_receiver, _selector('run'), [], {'': _one}),
      throwsArgumentError,
    );
  });

  test('accessors require their fixed nongeneric argument shapes', () {
    final getter = _selector('value', kind: .getter);
    final setter = _selector('value', kind: .setter);
    expect(() => DynamicDispatch(_receiver, getter, []), returnsNormally);
    expect(() => DynamicDispatch(_receiver, setter, [_one]), returnsNormally);
    for (final selector in [getter, setter]) {
      final args = selector.kind == .getter ? <Value>[] : <Value>[_one];
      expect(
        () => DynamicDispatch(_receiver, selector, args, {'x': _one}),
        throwsArgumentError,
      );
      expect(
        () =>
            DynamicDispatch(_receiver, selector, args, {}, [ValueType.integer]),
        throwsArgumentError,
      );
      expect(
        () => DynamicDispatch(_receiver, selector, [...args, _one]),
        throwsArgumentError,
      );
    }
    expect(() => DynamicDispatch(_receiver, setter, []), throwsArgumentError);
  });

  test('compiler storage is rejected in every operand and type position', () {
    final cell = Block([CellType(ValueType.integer)]).parameters.single;
    final method = _selector('run');
    expect(() => DynamicDispatch(cell, method, []), throwsArgumentError);
    expect(
      () => DynamicDispatch(_receiver, method, [cell]),
      throwsArgumentError,
    );
    expect(
      () => DynamicDispatch(_receiver, method, [], {'x': cell}),
      throwsArgumentError,
    );
    expect(
      () => DynamicDispatch(_receiver, method, [], {}, [cell.type]),
      throwsArgumentError,
    );
  });

  test(
    'formatting retains operation, private library, types and named order',
    () {
      final block = Block();
      block.emit(
        DynamicDispatch(
          _receiver,
          _selector('_run', privateLibrary: _library),
          [_one],
          {'z': _one, 'a': _receiver},
          [ValueType.string],
        ),
      );
      block.emit(
        DynamicDispatch(_receiver, _selector('value', kind: .getter), []),
      );
      final result = block.emit(
        DynamicDispatch(_receiver, _selector('value', kind: .setter), [_one]),
      );
      block.finish(Return(result));
      final output = StringBuffer();
      IrFunction(
        FunctionTarget(_library, 'format', ValueType.dynamicType, []),
        [block],
      ).writeTo(output);
      expect(
        output.toString(),
        contains(
          'dynamicDispatch null method memory:dynamic::_run<String>(1, z: 1, a: null)',
        ),
      );
      expect(
        output.toString(),
        contains('dynamicDispatch null getter value()'),
      );
      expect(
        output.toString(),
        contains('dynamicDispatch null setter value(1)'),
      );
    },
  );

  test('type argument templates must belong to the lexical scope', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    IrFunction build(List<TypeParameterType> parameters) {
      final block = Block();
      final op = block.emit(
        DynamicDispatch(_receiver, _selector('run'), [], {}, [
          CoreTypes.listOf(t),
        ]),
      );
      block.finish(Return(op));
      return IrFunction(
        FunctionTarget(
          _library,
          'scope',
          ValueType.dynamicType,
          [],
          typeParameters: parameters,
        ),
        [block],
      );
    }

    expect(() => build([]), throwsStateError);
    expect(() => build([t]), returnsNormally);
  });

  test('lookup skips abstract redeclarations and ignores interface bodies', () {
    final base = ClassType(_library, 'Base');
    final child = ClassType(_library, 'Child', superclass: base);
    final face = ClassType(_library, 'Face');
    final onlyInterface = ClassType(
      _library,
      'OnlyInterface',
      interfaces: [face],
    );
    final implemented = _member(base);
    final abstract = _member(child, isAbstract: true);
    final interfaceMember = _member(face);
    final program = IrProgram(
      [
        IrClass(base, [], members: [implemented]),
        IrClass(child, [], members: [abstract]),
        IrClass(face, [], members: [interfaceMember]),
        IrClass(onlyInterface, []),
      ],
      [_body(implemented), _body(interfaceMember)],
    );
    expect(
      program.lookupMember(child, implemented.selector).target,
      same(implemented),
    );
    expect(program.dispatch(child, implemented), same(implemented));
    expect(program.lookupMember(onlyInterface, implemented.selector), (
      target: null,
      unmodeledBoundary: null,
      unsupportedForwarder: false,
    ));
  });

  test('first real implementation wins regardless of its call shape', () {
    final base = ClassType(_library, 'Base');
    final child = ClassType(_library, 'Child', superclass: base);
    final noArgs = _member(base);
    final oneArg = _member(child, parameters: [ValueType.string]);
    final program = IrProgram(
      [
        IrClass(base, [], members: [noArgs]),
        IrClass(child, [], members: [oneArg]),
      ],
      [_body(noArgs), _body(oneArg)],
    );
    expect(program.lookupMember(child, noArgs.selector).target, same(oneArg));
    expect(
      () => DynamicDispatch(_receiver, noArgs.selector, []),
      returnsNormally,
    );
  });

  test(
    'lookup keeps method/accessor and private-library identities distinct',
    () {
      final base = ClassType(_library, 'Base');
      final child = ClassType(
        Uri.parse('memory:other'),
        'Child',
        superclass: base,
      );
      final basePrivate = _member(base, name: '_run');
      final childPrivate = _member(child, name: '_run');
      final getter = _member(child, name: '_run', kind: .getter);
      final program = IrProgram(
        [
          IrClass(base, [], members: [basePrivate]),
          IrClass(child, [], members: [childPrivate, getter]),
        ],
        [_body(basePrivate), _body(childPrivate), _body(getter)],
      );
      expect(
        program.lookupMember(child, basePrivate.selector).target,
        same(basePrivate),
      );
      expect(
        program.lookupMember(child, childPrivate.selector).target,
        same(childPrivate),
      );
      expect(program.lookupMember(child, getter.selector).target, same(getter));
    },
  );

  test('absence at Object differs from unmodeled imported boundaries', () {
    final imported = ClassType(
      Uri.parse('package:external/a.dart'),
      'Imported',
    );
    final child = ClassType(_library, 'Child', superclass: imported);
    final local = ClassType(_library, 'Local');
    final program = IrProgram([IrClass(child, []), IrClass(local, [])], []);
    final selector = _selector('run');
    expect(program.lookupMember(local, selector), (
      target: null,
      unmodeledBoundary: null,
      unsupportedForwarder: false,
    ));
    expect(program.lookupMember(child, selector), (
      target: null,
      unmodeledBoundary: imported,
      unsupportedForwarder: false,
    ));
    expect(
      program.lookupMember(imported, selector).unmodeledBoundary,
      imported,
    );
    final incomplete = ClassType.declare(_library, 'Incomplete');
    expect(
      IrProgram([
        IrClass(incomplete, []),
      ], []).lookupMember(incomplete, selector).unmodeledBoundary,
      incomplete,
    );
  });

  test(
    'a supplied Object implementation is searched before terminal absence',
    () {
      final member = _member(ValueType.object);
      final program = IrProgram(
        [
          IrClass(ValueType.object, [], members: [member]),
        ],
        [_body(member)],
      );
      expect(
        program.lookupMember(ValueType.object, member.selector).target,
        same(member),
      );
      expect(
        program
            .lookupMember(ValueType.object, _selector('absent'))
            .unmodeledBoundary,
        isNull,
      );
    },
  );

  test(
    'forwarder guards accumulate but do not replace concrete implementations',
    () {
      final base = ClassType(_library, 'Base');
      final child = ClassType(_library, 'Child', superclass: base);
      final real = _member(base);
      final missing = _selector('missing');
      final guards = <MemberSelector>[real.selector, missing];
      final definition = IrClass(child, [], unsupportedForwarders: guards);
      guards.clear();
      final program = IrProgram(
        [
          IrClass(base, [], members: [real]),
          definition,
        ],
        [_body(real)],
      );
      expect(
        () => definition.unsupportedForwarders.clear(),
        throwsUnsupportedError,
      );
      expect(program.lookupMember(child, real.selector), (
        target: real,
        unmodeledBoundary: null,
        unsupportedForwarder: true,
      ));
      expect(program.lookupMember(child, missing), (
        target: null,
        unmodeledBoundary: null,
        unsupportedForwarder: true,
      ));
      expect(
        program
            .lookupMember(child, _selector('unguarded'))
            .unsupportedForwarder,
        isFalse,
      );
    },
  );

  test('unary and binary minus have distinct runtime selectors', () {
    final type = ClassType(_library, 'Number');
    final unary = _member(type, name: '-');
    final binary = _member(type, name: '-', parameters: [type]);
    expect(unary.name, '-');
    expect(binary.name, '-');
    expect(unary.selector, _selector('unary-'));
    expect(binary.selector, _selector('-'));
    final program = IrProgram(
      [
        IrClass(type, [], members: [unary, binary]),
      ],
      [_body(unary), _body(binary)],
    );
    expect(program.lookupMember(type, _selector('unary-')).target, same(unary));
    expect(program.lookupMember(type, _selector('-')).target, same(binary));
    expect(program.dispatch(type, unary), same(unary));
    expect(program.dispatch(type, binary), same(binary));
  });

  test('NoSuchMethodError is a distinct subtype of Error', () {
    expect(ValueType.noSuchMethodError.dartName, 'NoSuchMethodError');
    expect(ValueType.noSuchMethodError.library, Uri.parse('dart:core'));
    expect(ValueType.error.accepts(ValueType.noSuchMethodError), isTrue);
    expect(ValueType.typeError.accepts(ValueType.noSuchMethodError), isFalse);
  });
}
