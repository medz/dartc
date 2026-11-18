import 'dart:ffi' show Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final backing = ClassType(null, 'Backing');
  final field = InstanceField(
    backing,
    'payload',
    .object.nullable,
    initiallyUnbound: true,
  );
  final initializer = FunctionTarget(
    null,
    'init',
    .voidType,
    [],
    kind: .initializer,
    owner: backing,
  );
  final storage = CellStorage(backing, field, null, initializer, .reference);
  final strings = CellType(ValueType.string);
  final objects = CellType(ValueType.object.nullable);
  final stringView = storage.viewOf(strings);
  final objectView = storage.viewOf(objects);
  final cls = IrClass(
    backing,
    [field],
    constructors: [initializer],
    cellStorage: storage,
  );
  final init = IrFunction(initializer, [
    Block(initializer.parameterTypes)..finish(const Return()),
  ]);

  // Both alternatives have the same physical class and field offsets. Only a
  // proof about the objects returned by this helper distinguishes their views.
  for (final (name, second, accepted) in [
    ('matching allocations', stringView, true),
    ('different logical content', objectView, false),
    ('unannotated allocation', null, false),
  ]) {
    test('slot view at a helper return and join: $name', () {
      final make = FunctionTarget(null, 'make', backing, [.boolean]);
      final head = Block(make.parameterTypes),
          yes = Block(),
          no = Block(),
          merge = Block([backing]);
      head.finish(Branch(head.parameters.single, Jump(yes), Jump(no)));
      for (final (block, contract) in [(yes, stringView), (no, second)]) {
        final object = block.emit(
          Construct(initializer, [], storageView: contract),
        );
        block.finish(Jump(merge, [object]));
      }
      merge.finish(Return(merge.parameters.single));
      final root = FunctionTarget(null, 'root', .string, [.boolean, .string]);
      final body = Block(root.parameterTypes);
      final object = body.emit(DirectCall(make, [body.parameters.first]));
      final wide = body.emit(TypeView(object, ValueType.object));
      final typed = body.emit(UncheckedCast(wide, backing));
      final view = body.emit(CellStorageView(typed, strings, storage));
      final reference = body.emit(CellStorageReference(view, storage));
      body.emit(
        StoreField(
          field,
          reference,
          body.parameters.last,
          storageView: stringView,
        ),
      );
      final load = body.emit(
        LoadField(field, reference, storageView: stringView),
      );
      body.finish(Return(load));
      final program = IrProgram(
        [cls],
        [
          init,
          IrFunction(make, [head, yes, no, merge]),
          IrFunction(root, [body]),
        ],
      );
      ProgramFlowFacts solve() =>
          ProgramFlow(program, [], openEntries: [root]).facts;
      if (accepted) {
        final facts = solve();
        expect(facts.provesStorageView(view), isTrue);
        expect(facts.provesStorageView(load), isTrue);
        expect(facts.returnedBy(root).types, contains(ValueType.string));
      } else {
        expect(
          solve,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'origin',
              contains('Unproven storage origin'),
            ),
          ),
        );
      }
    });
  }

  test('opaque backing with the exact class grants no cell capability', () {
    final root = FunctionTarget(null, 'root', .voidType, [backing]);
    final entry = Block(root.parameterTypes);
    entry.emit(
      KeepAlive(
        entry.emit(CellStorageView(entry.parameters.single, strings, storage)),
      ),
    );
    entry.finish(const Return());
    final program = IrProgram(
      [cls],
      [
        init,
        IrFunction(root, [entry]),
      ],
    );
    expect(
      () => ProgramFlow(program, [], openEntries: [root]),
      throwsStateError,
    );
  });

  test('an ordinary wider field store cannot corrupt a logical cell', () {
    final root = FunctionTarget(null, 'root', .voidType, []);
    final entry = Block();
    final actual = entry.emit(
      Construct(initializer, [], storageView: stringView),
    );
    entry.emit(StoreField(field, actual, const Constant.integer(3)));
    entry.finish(const Return());
    expect(
      () => IrProgram(
        [cls],
        [
          init,
          IrFunction(root, [entry]),
        ],
      ),
      throwsArgumentError,
    );
  });

  for (final scenario in ['overlap', 'unused', 'rebound', 'disjoint']) {
    test('actual raw write through a helper alias: $scenario', () {
      final scratch = InstanceField(backing, 'scratch', .integer);
      final owner = IrClass(
        backing,
        [field, scratch],
        constructors: [initializer],
        cellStorage: storage,
      );
      final mutate = FunctionTarget(null, 'mutate', .voidType, [.integer]);
      final writer = Block(mutate.parameterTypes);
      writer.emit(
        StoreNative(
          writer.parameters.first,
          NativeScalarType(Int64),
          const Constant.integer(3),
        ),
      );
      writer.finish(const Return());
      final root = FunctionTarget(null, 'root', .string, [.string]);
      final entry = Block(root.parameterTypes);
      final object = entry.emit(
        Construct(initializer, [], storageView: stringView),
      );
      void write() => entry.emit(
        StoreField(
          field,
          object,
          entry.parameters.single,
          storageView: stringView,
        ),
      );
      write();
      final ptr = entry.emit(ReferenceAddress(object));
      final index = scenario == 'disjoint' ? 1 : 0;
      final address = entry.emit(
        IntBinary(
          .add,
          ptr,
          Constant.integer(
            ObjectHeader.fieldsOffset + index * ObjectHeader.alignment,
          ),
        ),
      );
      entry.emit(DirectCall(mutate, [address]));
      if (scenario == 'rebound') write();
      entry.finish(
        Return(
          scenario == 'unused'
              ? entry.parameters.single
              : entry.emit(LoadField(field, object, storageView: stringView)),
        ),
      );
      final p = IrProgram(
        [owner],
        [
          init,
          IrFunction(mutate, [writer]),
          IrFunction(root, [entry]),
        ],
      );
      void solve() => ProgramFlow(
        p,
        [],
        openEntries: [root],
        memoryLayout: ProgramLayout(
          p.classes,
          nativeLayout: NativeLayout(Target.host()),
        ),
      );
      if (scenario == 'overlap') {
        expect(solve, throwsStateError);
      } else {
        expect(solve, returnsNormally);
      }
    });
  }

  test(
    'the cell declaration must certify every field in a producer contract',
    () {
      final root = FunctionTarget(null, 'root', backing, []);
      final entry = Block();
      final fake = StorageView(backing, strings, {field: ValueType.integer});
      entry.finish(
        Return(entry.emit(Construct(initializer, [], storageView: fake))),
      );
      expect(
        () => IrProgram(
          [cls],
          [
            init,
            IrFunction(root, [entry]),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('raw copy checks the source view as well as the fresh destination', () {
    final root = FunctionTarget(null, 'root', .voidType, []);
    final entry = Block();
    final actual = entry.emit(
      Construct(initializer, [], storageView: stringView),
    );
    final source = entry.emit(
      Construct(initializer, [], storageView: objectView),
    );
    entry.emit(
      InitializeStorageField(field, actual, source, storageView: stringView),
    );
    entry.finish(const Return());
    final program = IrProgram(
      [cls],
      [
        init,
        IrFunction(root, [entry]),
      ],
    );
    expect(
      () => ProgramFlow(program, [], openEntries: [root]),
      throwsStateError,
    );
  });
  test('rewrapping arbitrary raw bits cannot mint an invariant slot', () {
    final root = FunctionTarget(null, 'root', .string, []);
    final entry = Block();
    final raw = entry.emit(
      AllocatedObject(
        const Constant.integer(8),
        backing,
        const Constant.integer(0),
      ),
    );
    entry.finish(
      Return(entry.emit(LoadField(field, raw, storageView: stringView))),
    );
    final p = IrProgram(
      [cls],
      [
        init,
        IrFunction(root, [entry]),
      ],
    );
    expect(() => ProgramFlow(p, [], openEntries: [root]), throwsStateError);
  });

  for (final scenario in [
    'normal',
    'wrong target',
    'wrong descriptor',
    'throw',
  ]) {
    test('physical allocator capability: $scenario', () {
      final allocator = FunctionTarget(
        null,
        'allocate',
        .integer,
        List.filled(5, ValueType.integer),
      );
      final fake = FunctionTarget(
        null,
        'other',
        .integer,
        List.filled(5, ValueType.integer),
      );
      IrFunction implementation(FunctionTarget target, {bool fail = false}) {
        final body = Block(target.parameterTypes);
        if (fail) {
          body.finish(Throw(const Constant.integer(-37)));
        } else {
          body.finish(const Return(Constant.integer(4096)));
        }
        return IrFunction(target, [body]);
      }

      final sibling = ClassType(null, 'Other');
      final via = FunctionTarget(null, 'create', backing, [.integer]);
      final create = Block(via.parameterTypes);
      final zero = const Constant.integer(0);
      final allocation = create.emit(
        ManagedStorageAllocation(
          scenario == 'wrong target' ? fake : allocator,
          stringView,
          [
            zero,
            create.parameters.single,
            CallFrameValue.stackPointer,
            CallFrameValue.returnAddress,
            zero,
          ],
        ),
      );
      create.finish(Return(allocation));
      final root = FunctionTarget(null, 'writeRead', .string, [.string]);
      final head = Block(root.parameterTypes);
      final desc = head.emit(
        ObjectDescriptorAddress(
          scenario == 'wrong descriptor' ? sibling : backing,
        ),
      );
      final object = head.emit(DirectCall(via, [desc]));
      head.emit(
        StoreField(
          field,
          object,
          head.parameters.single,
          storageView: stringView,
        ),
      );
      final read = head.emit(LoadField(field, object, storageView: stringView));
      head.finish(Return(read));
      final p = IrProgram(
        [cls, IrClass(sibling, [])],
        [
          init,
          implementation(allocator, fail: scenario == 'throw'),
          implementation(fake),
          IrFunction(via, [create]),
          IrFunction(root, [head]),
        ],
      );
      ProgramFlowFacts solve() => ProgramFlow(
        p,
        [],
        openEntries: [root],
        managedAllocator: allocator,
      ).facts;
      if (scenario == 'wrong target' || scenario == 'wrong descriptor') {
        expect(solve, throwsStateError);
      } else {
        final facts = solve();
        expect(facts.executionTargetsOf(allocation), {allocator});
        expect(facts.provesStorageView(allocation), isTrue);
        expect(facts.reachesOperation(read), scenario == 'normal');
        if (scenario == 'normal') expect(facts.provesStorageView(read), isTrue);
      }
    });
  }
}
