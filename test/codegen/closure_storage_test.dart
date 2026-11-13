import 'package:dartc/layout.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:closure-storage');
  IrFunction body(FunctionTarget target) => IrFunction(target, [
    Block(target.parameterTypes)..finish(const Return(Constant.integer(0))),
  ]);

  test('open closure dispatch excludes incompatible result types', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final outer = FunctionTarget(
      uri,
      'outer',
      .integer,
      [],
      typeParameters: [t],
    );
    final targets = [
      for (final (index, result) in [
        ValueType.integer,
        ValueType.voidType,
        ValueType.floating,
      ].indexed)
        FunctionTarget(
          uri,
          'closure$index',
          result,
          [t],
          kind: .closure,
          enclosing: outer,
          sourceOffset: index,
        ),
    ];
    final storage = ClosureStorage([
      body(outer),
      for (final target in targets)
        IrFunction(target, [
          Block(target.parameterTypes)..finish(switch (target.returnType) {
            ValueType.voidType => const Return(),
            ValueType.floating => const Return(Constant.floating(1.5)),
            _ => const Return(Constant.integer(7)),
          }),
        ]),
    ]);
    for (final argument in [ValueType.integer, t]) {
      expect(
        storage
            .targetsFor(FunctionType(.integer, [argument]))
            .map((shape) => shape.target),
        [targets.first],
      );
    }
  });

  test(
    'static values share a carrier without allocation or wrapper bodies',
    () {
      final target = FunctionTarget(uri, 'plain', .integer, []);
      final first = FunctionConstant(target), second = FunctionConstant(target);
      final use = FunctionTarget(uri, 'use', first.type, []);
      final storage = ClosureStorage([
        body(target),
        IrFunction(use, [Block()..finish(Return(first))]),
        IrFunction(FunctionTarget(uri, 'again', second.type, []), [
          Block()..finish(Return(second)),
        ]),
      ]);
      expect(storage.constants, hasLength(1));
      expect(storage.constants[first.structuralKey]!.target, same(target));
      expect(storage.constants[first.structuralKey]!.initializer, isNull);
      expect(storage.functions, isEmpty);
      expect(
        () => ClosureStorage([
          IrFunction(use, [Block()..finish(Return(first))]),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'carriers retain capture order and outer lexical types, not own binders',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final u = TypeParameterType('U')
        ..initializeBound(ValueType.object.nullable);
      final v = TypeParameterType('V')
        ..initializeBound(ValueType.object.nullable);
      final owner = ClassType(uri, 'Owner', typeParameters: [t]);
      final outer = FunctionTarget(
        uri,
        'outer',
        .integer,
        [],
        kind: .method,
        owner: owner,
        typeParameters: [u],
      );
      final closure = FunctionTarget(
        uri,
        'inner',
        .integer,
        [],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 1,
        typeParameters: [v],
        captures: [CellType(.integer), t, .floating],
      );
      final storage = ClosureStorage([body(outer), body(closure)]);
      final shape = storage.closures[closure]!;
      expect(shape.parameters, [t, u]);
      expect(shape.captures.map((f) => f.type), [
        ValueType.object.nullable,
        ValueType.object.nullable,
        ValueType.floating,
      ]);
      expect(shape.initializer!.signature.parameters, [
        ValueType.integer,
        ValueType.object.nullable,
        ValueType.object.nullable,
        ValueType.floating,
        TypeMetadata.type,
        TypeMetadata.type,
      ]);
      final program = IrProgram([
        ...storage.classes,
        ...TypeValues().classes,
      ], storage.functions);
      expect(program.functions, hasLength(2));
      final layouts = ProgramLayout(program.classes);
      final fields = layouts.storageOf(shape.type);
      expect(fields.fields.first, same(storage.tag));
      expect(fields.layout.referenceOffsets, [
        ObjectHeader.typeOffset,
        ObjectHeader.fieldsOffset + 8,
        ObjectHeader.fieldsOffset + 16,
        ObjectHeader.fieldsOffset + 32,
        ObjectHeader.fieldsOffset + 40,
      ]);
      expect(storage.cell(CellType(.integer)).value.type, ValueType.integer);
    },
  );

  test(
    'cell shapes are collected from operations and stay fixed after layout',
    () {
      final target = FunctionTarget(uri, 'locals', .integer, []);
      final entry = Block();
      entry.emit(NewCell(CellType(.integer), const Constant.integer(1)));
      entry.emit(
        NewCell(CellType(.object.nullable), const Constant.nullValue()),
      );
      entry.emit(NewCell(CellType(.floating), const Constant.floating(1.5)));
      entry.finish(const Return(Constant.integer(0)));
      final storage = ClosureStorage([
        IrFunction(target, [entry]),
      ]);
      expect(storage.closures, isEmpty);
      expect(storage.classes, hasLength(3));
      expect(storage.cell(CellType(.floating)).value.type, ValueType.floating);
      expect(
        storage.cell(CellType(.object.nullable)).value.type,
        ValueType.object.nullable,
      );
      expect(
        storage.cell(CellType(.integer)),
        same(storage.cell(CellType(.integer))),
      );
      expect(() => storage.cell(CellType(.boolean)), throwsStateError);
      IrProgram(storage.classes, storage.functions);
    },
  );

  test('bound methods capture the receiver and owner types once', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final u = TypeParameterType('U')
      ..initializeBound(ValueType.object.nullable);
    final owner = ClassType(uri, 'Owner', typeParameters: [t]);
    final method = FunctionTarget(
      uri,
      'apply',
      .integer,
      [t],
      kind: .method,
      owner: owner,
      typeParameters: [u],
      covariantParameters: [0],
    );
    final storage = ClosureStorage([body(method)], boundMethods: [method]);
    final shape = storage.methods[method]!;
    expect(shape.target, same(method));
    expect(shape.captures.single.type, ValueType.object.nullable);
    expect(shape.parameters, [t]);
    expect(shape.typeArguments, [u]);
    expect(shape.signature, method.reifiedSignature);
    expect(shape.initializer!.signature.parameters, [
      ValueType.integer,
      ValueType.object.nullable,
      TypeMetadata.type,
    ]);
    IrProgram([...storage.classes, ...TypeValues().classes], storage.functions);

    final receiver = Block([
      owner.instantiate([.integer]),
    ]);
    final bound = receiver.emit(
      BindMethod(method, receiver.parameters.single, direct: true),
    );
    receiver.finish(Return(bound));
    final caller = IrFunction(
      FunctionTarget(
        uri,
        'bound',
        bound.type,
        receiver.parameters.map((p) => p.type),
      ),
      [receiver],
    );
    expect(caller.methodTearOffs, {
      (receiver: receiver.parameters.single.type, method: method, direct: true),
    });
    expect(() => caller.methodTearOffs.clear(), throwsUnsupportedError);
  });

  test('runtime specializations share the generic body and preserve semantic identity', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final generic = FunctionTarget(
      uri,
      'identity',
      t,
      [t],
      typeParameters: [t],
    );
    final implementation = Block(generic.parameterTypes);
    implementation.finish(Return(implementation.parameters.single));
    final value = FunctionConstant(generic);
    final fixed = FunctionConstant(generic, typeArguments: [.integer]);
    final apply = Block();
    final applied = apply.emit(InstantiateFunction(value, [.integer]));
    apply.finish(Return(applied));
    final storage = ClosureStorage([
      IrFunction(generic, [implementation]),
      IrFunction(FunctionTarget(uri, 'apply', applied.type, []), [apply]),
      IrFunction(FunctionTarget(uri, 'fixed', fixed.type, []), [
        Block()..finish(Return(fixed)),
      ]),
    ]);
    final original = storage.constants[value.structuralKey]!;
    final specialized = storage.specializations[original]!;
    expect(storage.specializations, hasLength(1));
    expect(specialized.target, same(generic));
    expect(specialized.instantiation!.generic, same(original));
    expect(specialized.captures, isEmpty);
    expect(specialized.environment, isEmpty);
    expect(
      specialized.identity,
      storage.constants[fixed.structuralKey]!.identity,
    );
    expect(specialized.tag, isNot(storage.constants[fixed.structuralKey]!.tag));
    expect(
      storage.targetsFor(fixed.type as FunctionType),
      contains(specialized),
    );
    IrProgram([...storage.classes, ...TypeValues().classes], storage.functions);
  });
}
