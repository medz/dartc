import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
import 'package:dartc/src/codegen/closure_storage.dart';
import 'package:dartc/src/codegen/type_values.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final uri = Uri.parse('memory:allocation-lowering');

  test(
    'actual createClosure leaves lexical T in the allocated function header',
    () {
      final t = TypeParameterType('T')..initializeBound(.object.nullable);
      final outer = FunctionTarget(
        uri,
        'outer',
        .voidType,
        [],
        typeParameters: [t],
      );
      final local = FunctionTarget(
        uri,
        'local',
        t,
        [t],
        kind: .closure,
        enclosing: outer,
        sourceOffset: 12,
      );
      final cb = Block(local.parameterTypes);
      cb.finish(Return(cb.parameters.last));
      final source = IrProgram([], [
        IrFunction(outer, [Block()..finish(const Return())]),
        IrFunction(local, [cb]),
      ]);
      final impl = CallableImplementations()..extend(source);
      final generator = impl.closureConstruction(local);
      final closure = _instructions(generator).whereType<Construct>().single;
      final shape = closure.callableStorage!;
      final program = IrProgram(
        [...impl.storage.classes, ...TypeValues().classes],
        [...source.functions, ...impl.storage.functions, generator],
      );
      final target = generator.target;
      final lowered = AllocationLowering(heapRuntime).lower(program, [target]);
      final out = lowered.implementationOf(target) as IrFunction;
      final type = _sourceValue(_descriptorHeader(out, shape)) as ReifyType;
      expect(type.template, local.signature);
      expect(type.template.freeTypeParameters, contains(same(t)));
      expect(target.typeParameters, contains(same(t)));
      final init = _instructions(out).whereType<InitializeObject>().single;
      final environment = _sourceValue(init.inputs.last) as ReifyType;
      expect(environment.template, same(t));
    },
  );
  test('genuine descriptors preserve their operand and share the physical header writer', () {
    final outer = FunctionTarget(uri, 'outer', .voidType, []);
    final local = FunctionTarget(
      uri,
      'local',
      .integer,
      [.integer],
      kind: .closure,
      enclosing: outer,
      sourceOffset: 12,
    );
    final code = Block(local.parameterTypes);
    code.finish(Return(code.parameters.last));
    final storage = ClosureStorage([]);
    final shape = storage.ensureClosure(local).storage;
    final functions = <IrFunction>[];
    final roots = <FunctionTarget>[];
    final cases = [
      'constant',
      'lexical',
      'known',
      'wide',
      'direct runtime type',
    ];
    for (final form in cases) {
      final target = FunctionTarget(uri, form, local.signature, [
        TypeMetadata.type,
        local.signature,
      ]);
      roots.add(target);
      final entry = Block(target.parameterTypes);
      final Value descriptor = switch (form) {
        'constant' => TypeConstant(local.signature),
        'lexical' => entry.emit(ReifyType(local.signature)),
        'known' => entry.parameters.first,
        'wide' => entry.emit(
          TypeView(
            entry.emit(TypeView(entry.parameters.first, .typeType)),
            ValueType.object.nullable,
          ),
        ),
        _ => entry.emit(ObjectRuntimeType(entry.parameters.last, direct: true)),
      };
      final operation = entry.emit(
        Construct.callable(
          shape,
          [entry.emit(FunctionEntryTableAddress(local))],
          local.signature,
          descriptor,
        ),
      );
      entry.finish(Return(operation));
      functions.add(IrFunction(target, [entry]));
    }
    final program = IrProgram(
      [...storage.classes, ...TypeValues().classes],
      [
        IrFunction(outer, [Block()..finish(const Return())]),
        IrFunction(local, [code]),
        ...storage.functions,
        ...functions,
      ],
    );
    final lowered = AllocationLowering(heapRuntime).lower(program, roots);
    final templates = <FunctionTarget>{};
    for (final (i, target) in roots.indexed) {
      final out = lowered.implementationOf(target) as IrFunction;
      final descriptor = _sourceValue(_descriptorHeader(out, shape));
      final header = _instructions(out).whereType<StoreObjectReference>().single;
      templates.add(out.originOf(header).source.owner);
      switch (cases[i]) {
        case 'constant':
          expect((descriptor as TypeConstant).representedType, local.signature);
        case 'lexical':
          expect((descriptor as ReifyType).template, local.signature);
        case 'known' || 'wide':
          expect(descriptor, same(out.entry.parameters.first));
        default:
          expect(
            (descriptor as ObjectRuntimeType).operand,
            same(out.entry.parameters.last),
          );
      }
    }
    expect(templates, hasLength(1));
  });
  test('a user Type implementation does not qualify as a descriptor', () {
    final custom = ClassType(
      uri,
      'UserType',
      interfaces: [ValueType.typeType],
    );
    final outer = FunctionTarget(uri, 'scope', .voidType, []);
    final local = FunctionTarget(
      uri,
      'local',
      .voidType,
      [],
      kind: .closure,
      enclosing: outer,
      sourceOffset: 12,
    );
    final shape = ClosureStorage([]).ensureClosure(local).storage;
    final block = Block([custom, .typeType, .object]);
    for (final value in [
      block.parameters[0],
      block.parameters[1],
      TypeView(block.parameters[0], .typeType),
      TypeView(block.parameters[0], ValueType.object.nullable),
      ObjectRuntimeType(block.parameters.last),
    ]) {
      expect(value.isTypeDescriptor, isFalse);
      expect(
        () => Construct.callable(
          shape,
          [FunctionEntryTableAddress(local)],
          local.signature,
          value,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'cell construction and copy use the common zeroed allocation contract',
    () {
      for (final type in <ValueType>[.integer, .object.nullable]) {
        final root = FunctionTarget(uri, 'cellAllocation', type, [type]);
        final entry = Block(root.parameterTypes);
        final original = entry.emit(NewCell(CellType(type), null));
        final copied = entry.emit(CopyCell(original));
        entry.emit(WriteCell(copied, entry.parameters.single));
        entry.finish(Return(entry.emit(ReadCell(copied))));
        final program = CellLowering().bind().normalize(
          IrProgram([], [
            IrFunction(root, [entry]),
          ]),
        );
        final storage = program.classes
            .map((c) => c.cellStorage)
            .nonNulls
            .single;
        expect(storage.fields, [storage.value]);
        expect(storage.bound, isNull);
        final lowered = AllocationLowering(heapRuntime).lower(program, [root]);
        cellInitializationRequirements(lowered);
        final body = lowered.implementationOf(root)! as IrFunction;
        final operations = [
          for (final block in body.blocks) ...[
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        ];
        expect(operations.whereType<Construct>(), isEmpty);
        final objects = operations.whereType<ManagedStorageAllocation>().toList();
        expect(objects, hasLength(2));
        for (final object in objects) {
          expect(object.allocator, same(heapRuntime.allocate));
          expect(object.storageView, storage.viewOf(CellType(type)));
          expect((object.inputs[1] as ObjectDescriptorAddress).declaration,
              same(storage.type));
        }
        final copy = operations.whereType<InitializeStorageField>().single;
        expect(copy.field, same(storage.value));
        expect(copy.destination, objects.last);
        expect(copy.source, isA<CellStorageReference>());
        final layout = ProgramLayout(
          program.classes,
          executionShapes: program.executionShapes,
          nativeLayout: NativeLayout(const Target(.linux, .arm64)),
        );
        final stored = layout.storageOf(storage.type);
        expect(stored.layout.size, ObjectHeader.fieldsOffset + 8);
        expect(stored.layout.referenceOffsets, [
          ObjectHeader.typeOffset,
          if (type == ValueType.object.nullable)
            layout.fieldOffset(storage.value),
        ]);
        expect(CellLowering().bind().normalize(lowered), same(lowered));
      }
    },
  );

  test('expanded allocation retains final-field initialization proof', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final owner = ClassType(uri, 'Fresh', typeParameters: [t]);
    final instance = owner.instantiate([ValueType.integer]);
    final field = InstanceField(owner, 'value', t, isFinal: true);
    final root = FunctionTarget(uri, 'initializeFresh', instance, [
      ValueType.integer,
    ]);
    final entry = Block(root.parameterTypes);
    final fresh = entry.emit(NewPayload(instance, const Constant.integer(0)));
    entry.emit(StoreField(field, fresh, entry.parameters.single));
    entry.finish(Return(fresh));
    final original = IrProgram(
      [
        IrClass(owner, [field]),
      ],
      [
        IrFunction(root, [entry]),
      ],
    );
    final lowered = AllocationLowering(heapRuntime).lower(original, [root]);
    final body = lowered.implementationOf(root) as IrFunction;
    final store = body.entry.instructions.whereType<StoreField>().single;
    expect(store.receiver, isA<AllocatedObject>());
    expect(store.value, body.entry.parameters.single);
  });

  test('typed construction preserves values, lexical types and handlers', () {
    final t = TypeParameterType('T')..initializeBound(.floating);
    final owner = ClassType(uri, 'Holder', typeParameters: [t]);
    final field = InstanceField(owner, 'value', t);
    final initializer = FunctionTarget(
      uri,
      'new',
      .voidType,
      [t],
      owner: owner,
      kind: .initializer,
    );
    final initialize = Block(initializer.parameterTypes);
    initialize.emit(
      StoreField(
        field,
        initialize.parameters.first,
        initialize.parameters.last,
      ),
    );
    initialize.finish(const Return());
    final instance = owner.instantiate([.floating]);
    final root = FunctionTarget(uri, 'entry', instance.nullable, [.floating]);
    final entry = Block(root.parameterTypes);
    final success = Block([instance]), failed = Block();
    final construct = Construct(
      initializer,
      entry.parameters,
      instantiatedType: instance,
    );
    entry.finish(
      Invoke(
        construct,
        onReturn: Jump(success, [construct]),
        onThrow: Jump(failed),
      ),
    );
    success.finish(Return(success.parameters.single));
    failed.finish(const Return(Constant.nullValue()));
    final uncalled = FunctionTarget(uri, 'uncalled', instance, [.floating]);
    final other = Block(uncalled.parameterTypes);
    other.finish(
      Return(
        other.emit(
          Construct(initializer, other.parameters, instantiatedType: instance),
        ),
      ),
    );
    final original = IrProgram(
      [
        ...heapRuntime.program.classes,
        IrClass(owner, [field], constructors: [initializer]),
      ],
      [
        ...heapRuntime.program.functions,
        IrFunction(initializer, [initialize]),
        IrFunction(root, [entry, success, failed]),
        IrFunction(uncalled, [other]),
      ],
      globals: heapRuntime.program.globals,
      externals: heapRuntime.program.externals,
    );
    final lowered = AllocationLowering(heapRuntime).lower(original, [root]);
    final source = lowered.implementationOf(root) as IrFunction;
    final operations = [
      for (final block in source.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    ];
    expect(operations.whereType<Construct>(), isEmpty);
    expect(lowered.functions.length, original.functions.length);
    final allocation = operations.whereType<DirectCall>().singleWhere(
      (call) => call.target == heapRuntime.allocate,
    );
    expect(allocation.inputs, hasLength(5));
    expect(allocation.inputs[1], isA<ObjectDescriptorAddress>());
    expect(allocation.inputs[2], CallFrameValue.stackPointer);
    expect(allocation.inputs[3], CallFrameValue.returnAddress);
    final initialization = operations.whereType<InitializeObject>().single;
    expect(initialization.initializer, initializer);
    expect(initialization.inputs.last, source.entry.parameters.single);
    for (final block in source.blocks) {
      if (block.end case Invoke(:final onThrow)) {
        expect(onThrow.target.end, isA<Return>());
        expect((onThrow.target.end as Return).value, isA<Constant>());
      }
    }
    expect(
      lowered.implementationOf(uncalled),
      same(original.implementationOf(uncalled)),
    );
  });

  test(
    'payload length enters the actual allocator and fresh storage proof',
    () {
      final owner = ClassType(uri, 'Payload');
      final root = FunctionTarget(uri, 'payload', owner, [.integer]);
      final entry = Block(root.parameterTypes);
      entry.finish(
        Return(entry.emit(NewPayload(owner, entry.parameters.single))),
      );
      final original = IrProgram(
        [...heapRuntime.program.classes, IrClass(owner, [])],
        [
          ...heapRuntime.program.functions,
          IrFunction(root, [entry]),
        ],
        globals: heapRuntime.program.globals,
        externals: heapRuntime.program.externals,
      );
      final lowered = AllocationLowering(heapRuntime).lower(original, [root]);
      final source = lowered.implementationOf(root) as IrFunction;
      final allocated = source.entry.instructions
          .whereType<AllocatedObject>()
          .single;
      final allocator = source.entry.instructions
          .whereType<DirectCall>()
          .singleWhere((call) => call.target == heapRuntime.allocate);
      expect(allocator.inputs.last, source.entry.parameters.single);
      expect(allocated.payloadBytes, source.entry.parameters.single);
      expect(allocated.type, owner);
      expect(
        AllocationLowering(heapRuntime).lower(lowered, [root]),
        same(lowered),
      );
    },
  );
}

Iterable<Instruction> _instructions(IrFunction body) sync* {
  for (final block in body.blocks) {
    yield* block.instructions;
    if (block.end case Invoke(:final operation)) yield operation;
  }
}

Value _descriptorHeader(IrFunction function, CallableStorage storage) {
  final header = _instructions(function).whereType<StoreObjectReference>().single;
  expect((header.byteOffset as ScalarConstant).value, ObjectHeader.typeOffset);
  final allocation = _instructions(function).whereType<AllocatedObject>().single;
  expect(header.object, same(allocation));
  expect(allocation.callableStorage, same(storage));
  final init = _instructions(function).whereType<InitializeObject>().single;
  expect(init.initializer, same(storage.initializer));
  expect(init.receiver, same(allocation));
  return header.value;
}

Value _sourceValue(Value value) {
  while (value is TypeView || value is UncheckedCast) {
    value = (value as Instruction).inputs.single;
  }
  return value;
}
