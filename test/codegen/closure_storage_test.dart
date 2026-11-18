import 'package:dartc/target.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/cell_lowering.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:dartc/src/codegen/type_implementations.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final uri = Uri.parse('memory:closure-storage');
  IrFunction body(FunctionTarget target) => IrFunction(target, [
    Block(target.parameterTypes)..finish(const Return(Constant.integer(0))),
  ]);

  test(
    'stored closures of unrelated signatures do not generate dispatch bodies',
    () {
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
      expect(storage.closures.keys, containsAll(targets));
      expect(storage.implementations.functions, isEmpty);
      expect(storage.implementations.shapes, isEmpty);
    },
  );

  test(
    'static values share a carrier without allocation or wrapper bodies',
    () {
      final target = FunctionTarget(uri, 'plain', .integer, []);
      final unreferenced = FunctionTarget(uri, 'unreferenced', .integer, []);
      final first = FunctionConstant(target), second = FunctionConstant(target);
      final use = FunctionTarget(uri, 'use', first.type, []);
      final storage = ClosureStorage([
        body(target),
        body(unreferenced),
        IrFunction(use, [Block()..finish(Return(first))]),
        IrFunction(FunctionTarget(uri, 'again', second.type, []), [
          Block()..finish(Return(second)),
        ]),
      ]);
      expect(storage.constants, hasLength(1));
      expect(storage.constants[first.structuralKey]!.target, same(target));
      expect(storage.constants[first.structuralKey]!.initializer, isNull);
      expect(storage.functions, isEmpty);
      expect(storage.constants.values.map((shape) => shape.target), [target]);
      final identityOnly = ClosureStorage([
        IrFunction(use, [Block()..finish(Return(first))]),
      ]);
      expect(identityOnly.constants[first.structuralKey]!.target, same(target));
      expect(identityOnly.implementations.functions, isEmpty);
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
      expect(program.functions, hasLength(1));
      final layouts = ProgramLayout(
        program.classes,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
      );
      final fields = layouts.storageOf(shape.type);
      expect(fields.fields.first, same(storage.entryTable));
      expect(fields.layout.referenceOffsets, [
        ObjectHeader.typeOffset,
        ObjectHeader.fieldsOffset + 8,
        ObjectHeader.fieldsOffset + 24,
        ObjectHeader.fieldsOffset + 32,
        ObjectHeader.fieldsOffset + 40,
        ObjectHeader.fieldsOffset + 48,
        ObjectHeader.fieldsOffset + 64,
        ObjectHeader.fieldsOffset + 72,
      ]);
    },
  );

  test(
    'cell layouts are persistent declarations independent of callable storage',
    () {
      final target = FunctionTarget(uri, 'locals', .integer, []);
      final entry = Block();
      entry.emit(NewCell(CellType(.integer), const Constant.integer(1)));
      entry.emit(
        NewCell(CellType(.object.nullable), const Constant.nullValue()),
      );
      entry.emit(NewCell(CellType(.floating), const Constant.floating(1.5)));
      entry.finish(const Return(Constant.integer(0)));
      final input = IrProgram([], [
        IrFunction(target, [entry]),
      ]);
      final program = CellLowering().bind().normalize(input);
      final storage = ClosureStorage(
        program.functions,
        storageDeclarations: program.classes,
      );
      expect(storage.closures, isEmpty);
      expect(storage.classes, isEmpty);
      final layouts = ProgramLayout(
        program.classes,
        nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        executionShapes: program.executionShapes,
      );
      expect(program.classes, hasLength(3));
      for (final type in [
        ValueType.integer,
        ValueType.object.nullable,
        ValueType.floating,
      ]) {
        final cell = CellType(type);
        final shape = layouts.cellStorageOf(cell);
        expect(shape.fields, [shape.value]);
        expect(shape.bound, isNull);
        expect(shape.value.initiallyUnbound, isTrue);
        expect(layouts.slotShape(shape.value), cell.slotShape);
        expect(
          layouts.storageOf(shape.type).layout.size,
          ObjectHeader.fieldsOffset + 8,
        );
        expect(layouts.cellStorageOf(cell), same(shape));
      }
      expect(() => layouts.cellStorageOf(CellType(.boolean)), throwsStateError);
      expect(CellLowering().bind().normalize(program), same(program));
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

  test(
    'all instantiated function declarations use one traced wrapper layout',
    () {
      final storage = ClosureStorage([]);
      final first = storage.instantiated;
      final second = storage.instantiated;
      expect(second, same(first));
      expect(first.source, isNull);
      expect(first.declarationIdentity, isNull);
      expect(first.captures, isEmpty);
      expect(first.parameters, isEmpty);
      expect(first.origin!.type, ValueType.function);
      expect(first.arguments, same(FunctionStorage.arguments));
      expect(
        storage.classes.where((c) => c.callableStorage?.origin != null),
        hasLength(1),
      );
      expect(storage.implementations.functions, isEmpty);
      IrProgram([
        ...storage.classes,
        ...TypeValues().classes,
      ], storage.functions);
    },
  );

  test('instantiation wrappers retain the original closure identity anchor', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final outer = FunctionTarget(uri, 'outerIdentity', .integer, []);
    final closure = FunctionTarget(
      uri,
      'genericClosure',
      t,
      [t],
      typeParameters: [t],
      kind: .closure,
      enclosing: outer,
      sourceOffset: 9,
      captures: [.integer],
    );
    // Keep the declared source body valid independently from the storage probe.
    final closureEntry = Block(closure.parameterTypes);
    closureEntry.finish(Return(closureEntry.parameters.last));
    final make = Block();
    final function = make.emit(
      MakeClosure(closure, [const Constant.integer(42)]),
    );
    make.emit(InstantiateFunction(function, [.integer]));
    make.finish(const Return(Constant.integer(0)));
    final storage = ClosureStorage([
      IrFunction(outer, [make]),
      IrFunction(closure, [closureEntry]),
    ]);
    final originalShape = storage.closures[closure]!;
    final wrapper = storage.instantiated;
    final typeImplementations = TypeImplementations();
    final values = typeImplementations.values;
    final types = values.argumentConstants([.integer]);
    final root = FunctionTarget(uri, 'identityProbe', .integer, []);
    final entry = Block();
    Value original() => entry.emit(
      Construct.callable(
        originalShape.storage,
        [
          entry.emit(FunctionEntryTableAddress(closure)),
          const Constant.integer(42),
        ],
        closure.signature,
        TypeConstant(closure.signature),
      ),
    );
    final first = original(), other = original();
    Value applied() => entry.emit(
      Construct.callable(
        wrapper,
        [first, types],
        closure.signature.instantiate([.integer]),
        TypeConstant(closure.signature.instantiate([.integer])),
      ),
    );
    final a = applied(), b = applied();
    Value field(InstanceField field, Value object) =>
        entry.emit(LoadField(field, entry.emit(CallableReference(object))));
    final checks = [
      entry.emit(Identical(field(storage.environment, first), first)),
      entry.emit(Identical(field(storage.environment, a), first)),
      entry.emit(Identical(field(storage.environment, b), first)),
      entry.emit(Identical(field(storage.identityAnchor, first), first)),
      entry.emit(Identical(field(storage.identityAnchor, a), first)),
      entry.emit(Identical(field(storage.identityAnchor, b), first)),
      entry.emit(
        Equals(field(storage.identity, a), field(storage.identity, first)),
      ),
      entry.emit(Identical(field(storage.identityArguments, a), types)),
    ];
    final distinct = entry.emit(
      Identical(field(storage.identityAnchor, other), first),
    );
    final failed = Block()..finish(const Return(Constant.integer(0)));
    final blocks = [entry, failed];
    var current = entry;
    for (final check in checks) {
      final next = Block();
      current.finish(Branch(check, Jump(next), Jump(failed)));
      blocks.add(next);
      current = next;
    }
    final done = Block()..finish(const Return(Constant.integer(42)));
    current.finish(Branch(distinct, Jump(failed), Jump(done)));
    blocks.add(done);
    final probe = IrFunction(root, blocks);
    final program = IrProgram(
      [...storage.classes, ...values.classes],
      [
        ...storage.functions,
        IrFunction(outer, [make]),
        IrFunction(closure, [closureEntry]),
        probe,
      ],
    );
    final layout = ProgramLayout(
      program.classes,
      nativeLayout: NativeLayout(Target.host()),
      typeImplementations: typeImplementations,
    );
    expect(IrInterpreter(program, {}, typeLayout: layout).run(probe, []), 42);
  });
}
