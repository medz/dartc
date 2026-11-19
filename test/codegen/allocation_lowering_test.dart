import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/target.dart';
import 'package:dartc/src/codegen/cell_initialization.dart';
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
      final program = IrProgram(
        [...impl.storage.classes, ...TypeValues().classes],
        [...source.functions, ...impl.storage.functions, generator],
      );
      final target = generator.target;
      final lowered = AllocationLowering(heapRuntime).lower(program, [target]);
      final out = lowered.implementationOf(target) as IrFunction;
      final header = out.blocks
          .expand((block) => block.instructions)
          .whereType<StoreObjectReference>()
          .single;
      Value descriptor = header.value;
      while (descriptor is TypeView || descriptor is UncheckedCast) {
        descriptor = (descriptor as Instruction).inputs.single;
      }
      expect((descriptor as ReifyType).template, local.signature);
    },
  );
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
