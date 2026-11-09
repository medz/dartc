import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:references');
const _one = Constant.integer(1);

void main() {
  test('verified graphs seal reachable binders and nominal metadata', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType.declare(_uri, 'Pending', typeParameters: [t]);
    final nested = TypeParameterType('U')..initializeBound(owner);
    final signature = FunctionType(.voidType, [], typeParameters: [nested]);
    final target = FunctionTarget(
      _uri,
      'sealed',
      .voidType,
      [signature],
      typeParameters: [t],
    );
    final block = Block(target.parameterTypes)..finish(const Return());
    IrFunction(target, [block]);
    expect(() => t.initializeDefaultType(.integer), throwsStateError);
    expect(() => nested.initializeDefaultType(.string), throwsStateError);
    expect(owner.initializeHierarchy, throwsStateError);
    expect(() => IrFunction(target, [block]), returnsNormally);
    expect(t.defaultType, isNull);
  });

  test(
    'programs seal unused class declarations and imported parent metadata',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final parent = ClassType.declare(_uri, 'Parent', typeParameters: [t]);
      final child = ClassType(
        _uri,
        'Child',
        superclass: parent.instantiate([.integer]),
      );
      final program = IrProgram([IrClass(child, [])], []);
      expect(() => t.initializeDefaultType(.string), throwsStateError);
      expect(parent.initializeHierarchy, throwsStateError);
      expect(
        program.classes.single.type.superclass,
        parent.instantiate([.integer]),
      );
    },
  );

  test('imported callable references share one declaration identity', () {
    final imported = Uri.parse('memory:imported');
    final read = FunctionTarget(imported, 'read', .integer, []);
    IrProgram program(FunctionTarget second) {
      final block = Block();
      block.emit(DirectCall(read, []));
      block.emit(DirectCall(second, []));
      block.finish(const Return());
      return IrProgram([], [
        IrFunction(FunctionTarget(_uri, 'caller', .voidType, []), [block]),
      ]);
    }

    expect(() => program(read), returnsNormally);
    expect(
      () => program(FunctionTarget(imported, 'read', .string, [])),
      throwsArgumentError,
    );
    expect(
      () => program(FunctionTarget(imported, 'read', .integer, [])),
      throwsArgumentError,
    );
    expect(
      () => program(FunctionTarget(_uri, 'read', .string, [])),
      returnsNormally,
    );
  });

  test('external Dart implementations keep their declaration, defaults and dispatch', () {
    final owner = ClassType(_uri, 'Api');
    final method = FunctionTarget(
      _uri,
      'read',
      .integer,
      [.integer],
      owner: owner,
      kind: .method,
      optionalPositional: 1,
    );
    final ctor = FunctionTarget(
      _uri,
      'new',
      .voidType,
      [],
      owner: owner,
      kind: .initializer,
    );
    final definition = IrClass(
      owner,
      [],
      members: [method],
      constructors: [ctor],
    );
    final defaults = {0: _one};
    final external = IrExternal(method, defaults: defaults);
    defaults.clear();
    final entry = Block();
    final instance = entry.emit(Construct(ctor, []));
    entry.finish(Return(entry.emit(InstanceCall(method, instance, []))));
    final caller = IrFunction(FunctionTarget(_uri, 'use', .integer, []), [
      entry,
    ]);
    final program = IrProgram(
      [definition],
      [caller],
      externals: [IrExternal(ctor), external],
    );
    expect(program.dispatch(owner, method), same(method));
    expect(program.implementationOf(method), same(external));
    expect(external.defaults, {0: _one});
    final text = StringBuffer();
    program.writeTo(text);
    expect('$text', contains('external method memory:references::Api.read'));
    expect(() => IrExternal(method), throwsArgumentError);
    expect(
      () => IrExternal(method, defaults: {0: const Constant.string('bad')}),
      throwsArgumentError,
    );
    final body = IrFunction(method, [
      Block(method.parameterTypes)..finish(const Return(_one)),
    ], defaults: external.defaults);
    expect(
      () => IrProgram([definition], [body], externals: program.externals),
      throwsArgumentError,
    );
    expect(
      () => IrProgram([definition], [caller], externals: [external]),
      throwsArgumentError,
    );
  });

  test('type-only references, unused declarations and repeated interfaces are checked', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final face = ClassType(_uri, 'Face', typeParameters: [t]);
    final base = ClassType(
      _uri,
      'Base',
      interfaces: [
        face.instantiate([ValueType.integer]),
      ],
    );
    IrClass child(ValueType argument) => IrClass(
      ClassType(
        _uri,
        'Child',
        superclass: base,
        interfaces: [
          face.instantiate([argument]),
        ],
      ),
      [],
    );
    expect(() => IrProgram([child(.integer)], []), returnsNormally);
    expect(() => IrProgram([child(.string)], []), throwsArgumentError);
    expect(() => IrProgram([child(t)], []), throwsArgumentError);
    final owner = ClassType(_uri, 'Base');
    final body = IrFunction(FunctionTarget(_uri, 'type', .typeType, []), [
      Block()..finish(Return(TypeConstant(owner))),
    ]);
    expect(() => IrProgram([IrClass(base, [])], [body]), throwsArgumentError);
    final external = IrExternal(
      FunctionTarget(_uri, 'external', .voidType, [owner]),
    );
    expect(
      () => IrProgram([IrClass(base, [])], [], externals: [external]),
      throwsArgumentError,
    );
    final abstract = FunctionTarget(
      _uri,
      'method',
      t,
      [],
      owner: base,
      kind: .method,
      isAbstract: true,
    );
    expect(
      () => IrProgram([
        IrClass(base, [], members: [abstract]),
      ], []),
      throwsStateError,
    );
  });

  test(
    'calls and nested default tear-offs must reference the supplied body',
    () {
      FunctionTarget fn() => FunctionTarget(_uri, 'f', .integer, []);
      final original = fn(), impostor = fn();
      final definition = IrFunction(original, [
        Block()..finish(const Return(_one)),
      ]);
      final caller = FunctionTarget(_uri, 'use', .integer, [
        ValueType.object.nullable,
      ], optionalPositional: 1);
      IrFunction use(FunctionTarget call, FunctionTarget defaultTarget) {
        final b = Block(caller.parameterTypes);
        b.finish(Return(b.emit(DirectCall(call, []))));
        return IrFunction(
          caller,
          [b],
          defaults: {
            0: SequenceConstant(CoreTypes.listOf(.function), [
              FunctionConstant(defaultTarget),
            ]),
          },
        );
      }

      for (final (call, value) in [
        (impostor, original),
        (original, impostor),
      ]) {
        expect(
          () => IrProgram([], [use(call, value), definition]),
          throwsArgumentError,
        );
      }
      expect(
        () => IrProgram([], [use(original, original), definition]),
        returnsNormally,
      );
      // A batch may reference a body supplied separately.
      expect(() => IrProgram([], [use(original, original)]), returnsNormally);
    },
  );

  test(
    'an external tear-off supplies its Dart default to the implementation',
    () {
      final f = FunctionTarget(_uri, 'twice', .integer, [
        .integer,
      ], optionalPositional: 1);
      final external = IrExternal(f, defaults: {0: const Constant.integer(21)});
      final b = Block();
      b.finish(Return(b.emit(FunctionCall(FunctionConstant(f), []))));
      final caller = IrFunction(FunctionTarget(_uri, 'use', .integer, []), [b]);
      final runner = IrInterpreter(
        IrProgram([], [caller], externals: [external]),
        {(_uri, 'twice'): (x) => x * 2},
      );
      expect(runner.run(caller, []), 42);
    },
  );

  test(
    'slot ownership and complete inherited constant storage use identity',
    () {
      final base = ClassType(_uri, 'Base');
      final child = ClassType(_uri, 'Child', superclass: base);
      final field = InstanceField(base, 'x', .integer, isFinal: true);
      final fake = InstanceField(base, 'x', .integer, isFinal: true);
      final classes = [
        IrClass(base, [field]),
        IrClass(child, []),
      ];
      IrProgram read(InstanceField slot, Map<InstanceField, Constant> fields) {
        final c = ObjectConstant(child, fields);
        final b = Block();
        b.finish(Return(b.emit(LoadField(slot, c))));
        return IrProgram(classes, [
          IrFunction(FunctionTarget(_uri, 'read', .integer, []), [b]),
        ]);
      }

      expect(() => read(field, {field: _one}), returnsNormally);
      expect(() => read(fake, {field: _one}), throwsArgumentError);
      expect(() => read(field, {fake: _one}), throwsArgumentError);
      expect(() => read(field, {}), throwsArgumentError);
      final implementer = ClassType(_uri, 'ImplementsBase', interfaces: [base]);
      expect(
        () => LoadField(field, Block([implementer]).parameters.single),
        throwsArgumentError,
      );
    },
  );

  test(
    'cyclic nominal parents are rejected before they can reach dispatch',
    () {
      final a = ClassType.declare(_uri, 'A'), b = ClassType.declare(_uri, 'B');
      a.initializeHierarchy(superclass: b);
      expect(() => b.initializeHierarchy(interfaces: [a]), throwsArgumentError);
      expect(() => b.initializeHierarchy(superclass: b), throwsArgumentError);
      b.initializeHierarchy();
      final program = IrProgram([IrClass(a, []), IrClass(b, [])], []);
      expect(
        program.lookupMember(a, (
          kind: .method,
          name: 'f',
          privateLibrary: null,
        )).unmodeledBoundary,
        isNull,
      );
      expect(
        () =>
            IrProgram([IrClass(a, []), IrClass(ClassType(_uri, 'B'), [])], []),
        throwsArgumentError,
      );
      expect(
        () => IrClass(CoreTypes.listOf(.integer), []),
        throwsArgumentError,
      );
      expect(
        () => FunctionTarget(
          CoreTypes.list.library,
          'method',
          .voidType,
          [],
          owner: CoreTypes.listOf(.integer),
          kind: .method,
        ),
        throwsArgumentError,
      );
    },
  );
}
