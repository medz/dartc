import 'dart:ffi' show Int64, Uint8;
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/codegen/constant_data.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final type = ClassType(null, 'Module');
  final field = InstanceField(type, 'value', .integer);
  final declaration = IrClass(type, [field]);
  final word = NativeScalarType(Int64);

  test('module header facts admit its final encoded identity hash', () {
    final object = ModuleObject(type);
    final root = FunctionTarget(null, 'header', .integer, []);
    final entry = Block();
    final reference = entry.emit(ModuleObjectReference(object));
    entry.finish(
      Return(
        entry.emit(
          LoadObjectData(
            reference,
            const Constant.integer(ObjectHeader.identityHashOffset),
            word,
          ),
        ),
      ),
    );
    final program = IrProgram(
      [declaration],
      [
        IrFunction(root, [entry]),
      ],
    );
    final layout = _layout(program);
    final facts = ProgramFlow(program, [
      (target: root, arguments: []),
    ], memoryLayout: layout).facts;
    final bytes = ConstantData(layout, 0).moduleObjectData(object).bytes;
    final encoded = ByteData.sublistView(bytes)
        .getInt64(ObjectHeader.identityHashOffset, Endian.little);
    expect(facts.returnedBy(root).integers!.contains(encoded), isTrue);
    expect(facts.returnedBy(root).constant, isNull);
  });

  for (final isFinal in [false, true]) {
    for (final (
          name,
          replaced,
          dynamicOffset,
          nonBase,
          nativeBytes,
          unknownReference,
        )
        in const [
          ('field', false, false, false, false, false),
          ('variable offset', false, true, false, false, false),
          ('replaced field', true, false, false, false, false),
          ('replaced variable offset', true, true, false, false, false),
          ('non-base provenance', true, false, true, false, false),
          ('native bytes', true, true, false, true, false),
          ('unknown reference', true, false, false, false, true),
        ]) {
      test('raw read snapshots $name capabilities (final=$isFinal)', () {
        final type = ClassType(null, 'Child');
        final field = InstanceField(type, 'value', .integer, isFinal: isFinal);
        final declaration = IrClass(type, [field]);
        final holderType = ClassType(null, 'Holder');
        final childField = InstanceField(holderType, 'child', type);
        final child = ModuleObject(
          type,
          initialFields: {field: const Constant.integer(5)},
        );
        final holder = ModuleObject(holderType);
        final capture = FunctionTarget(null, 'capture', .voidType, [.integer]);
        final mutate = FunctionTarget(null, 'mutate', .voidType, []);
        final root = FunctionTarget(null, 'escape', .integer, [
          if (dynamicOffset) ValueType.integer,
          if (unknownReference) type,
        ]);
        final entry = Block(root.parameterTypes);
        final c = entry.emit(ModuleObjectReference(child));
        final h = entry.emit(ModuleObjectReference(holder));
        entry.emit(
          StoreField(
            childField,
            h,
            unknownReference ? entry.parameters.single : c,
          ),
        );
        final storage = nativeBytes
            ? entry.emit(NativeDataAddress(NativeData(List.filled(8, 0))))
            : null;
        if (storage != null) {
          entry.emit(
            StoreNative(storage, word, entry.emit(ReferenceAddress(c))),
          );
        }
        final empty = ClassType(null, 'Empty');
        Value? computed;
        if (nonBase) {
          final a = entry.emit(
            ReferenceAddress(
              entry.emit(ModuleObjectReference(ModuleObject(empty))),
            ),
          );
          final b = entry.emit(ReferenceAddress(h));
          // The concrete address is b, while the abstract arithmetic may
          // retain a as its base and b in the full provenance set.
          computed = entry.emit(
            IntBinary(
              .add,
              entry.emit(
                IntBinary(.add, a, entry.emit(IntBinary(.subtract, b, a))),
              ),
              const Constant.integer(ObjectHeader.fieldsOffset),
            ),
          );
        }
        final raw = entry.emit(
          storage != null
              ? LoadNative(
                  entry.emit(IntBinary(.add, storage, entry.parameters.single)),
                  word,
                )
              : computed != null
              ? LoadNative(computed, word)
              : LoadObjectData(
                  h,
                  dynamicOffset
                      ? entry.parameters.single
                      : const Constant.integer(ObjectHeader.fieldsOffset),
                  word,
                ),
        );
        if (replaced) {
          final replacement = entry.emit(
            ModuleObjectReference(
              ModuleObject(
                type,
                initialFields: {field: const Constant.integer(11)},
              ),
            ),
          );
          entry.emit(StoreField(childField, h, replacement));
          if (storage != null) {
            entry.emit(
              StoreNative(
                storage,
                word,
                entry.emit(ReferenceAddress(replacement)),
              ),
            );
          }
        }
        entry.emit(DirectCall(capture, [raw]));
        entry.emit(DirectCall(mutate, []));
        entry.finish(Return(entry.emit(LoadField(field, c))));
        final program = IrProgram(
          [
            declaration,
            if (nonBase) IrClass(empty, []),
            IrClass(holderType, [childField]),
          ],
          [
            IrFunction(root, [entry]),
          ],
          externals: [
            IrExternal(capture, effects: {}, capturesArguments: true),
            IrExternal(
              mutate,
              effects: {.writesStorage},
              capturesArguments: false,
            ),
          ],
        );
        final facts = ProgramFlow(program, [
          (
            target: root,
            arguments: [
              if (dynamicOffset) FlowValue.unknown(.integer),
              if (unknownReference) FlowValue.unknown(type),
            ],
          ),
        ], memoryLayout: _layout(program)).facts;
        // Native code can write 7 through the address retained by the earlier call.
        expect(facts.returnedBy(root).integers!.contains(7), isTrue);
      });
    }
  }

  for (final mode in ['write', 'copy', 'declared write']) {
    final copying = mode == 'copy';
    test('uncertain native $mode retains possible pointees', () {
      final childType = ClassType(null, 'Child');
      final value = InstanceField(childType, 'value', .integer);
      final child = ModuleObject(
        childType,
        initialFields: {value: const Constant.integer(5)},
      );
      final root = FunctionTarget(null, 'root', .integer, [.integer]);
      final capture = FunctionTarget(null, 'capture', .voidType, [.integer]);
      final mutate = FunctionTarget(null, 'mutate', .voidType, []);
      final write = FunctionTarget(null, 'writeRange', .voidType, [
        .integer,
        .integer,
      ]);
      final entry = Block(root.parameterTypes);
      final object = entry.emit(ModuleObjectReference(child));
      final storage = entry.emit(
        NativeDataAddress(NativeData(List.filled(16, 0))),
      );
      entry.emit(
        StoreNative(storage, word, entry.emit(ReferenceAddress(object))),
      );
      final offset = entry.emit(
        IntBinary(.add, storage, entry.parameters.single),
      );
      final destination = copying
          ? entry.emit(NativeDataAddress(NativeData(List.filled(8, 0))))
          : storage;
      entry.emit(
        mode == 'declared write'
            ? DirectCall(write, [storage, const Constant.integer(8)])
            : copying
            ? CopyNative(destination, offset, word)
            : StoreNative(
                offset,
                NativeScalarType(Uint8),
                const Constant.integer(0),
              ),
      );
      final raw = entry.emit(LoadNative(destination, word));
      // Overwriting the source later cannot revoke a pointer already read/copied.
      entry.emit(StoreNative(storage, word, const Constant.integer(0)));
      entry.emit(DirectCall(capture, [raw]));
      entry.emit(DirectCall(mutate, []));
      entry.finish(Return(entry.emit(LoadField(value, object))));
      final program = IrProgram(
        [
          IrClass(childType, [value]),
        ],
        [
          IrFunction(root, [entry]),
        ],
        externals: [
          if (mode == 'declared write')
            IrExternal(
              write,
              effects: {.writesStorage},
              memory: const .write(0, 1),
              capturesArguments: false,
            ),
          IrExternal(capture, effects: {}, capturesArguments: true),
          IrExternal(
            mutate,
            effects: {.writesStorage},
            capturesArguments: false,
          ),
        ],
      );
      final facts = ProgramFlow(program, [
        (
          target: root,
          arguments: [
            FlowValue.integerRange(
              FlowIntegerRange(0, 8, strideBits: 3, residue: 0),
            ),
          ],
        ),
      ], memoryLayout: _layout(program)).facts;
      expect(facts.returnedBy(root).integers!.contains(7), isTrue);
    });
  }

  for (final initialized in [false, true]) {
    test(
      'module fields retain explicit binding state (initialized=$initialized)',
      () {
        final object = ModuleObject(
          type,
          initialFields: {if (initialized) field: const Constant.integer(5)},
        );
        final root = FunctionTarget(null, 'read', .integer, []);
        final entry = Block();
        final reference = entry.emit(ModuleObjectReference(object));
        entry.finish(Return(entry.emit(LoadField(field, reference))));
        final facts = _flow(
          IrProgram(
            [declaration],
            [
              IrFunction(root, [entry]),
            ],
          ),
          root,
        );
        expect(_number(facts.returnedBy(root)), initialized ? 5 : null);
        expect(facts.returnedBy(root).isBottom, !initialized);
      },
    );
  }

  test('module references alias across summaries, retain writes, and stay distinct', () {
    final object = ModuleObject(
      type,
      initialFields: {field: const Constant.integer(5)},
    );
    final equal = ModuleObject(
      type,
      initialFields: {field: const Constant.integer(5)},
    );
    final read = FunctionTarget(null, 'read', .integer, []);
    final reader = Block();
    final fromReader = reader.emit(ModuleObjectReference(object));
    reader.finish(Return(reader.emit(LoadField(field, fromReader))));
    final root = FunctionTarget(null, 'write', .integer, []);
    final entry = Block();
    final first = entry.emit(ModuleObjectReference(object));
    entry.emit(StoreField(field, first, const Constant.integer(42)));
    final again = entry.emit(ModuleObjectReference(object));
    final other = entry.emit(ModuleObjectReference(equal));
    final called = entry.emit(DirectCall(read, []));
    entry.finish(
      Return(
        entry.emit(
          IntBinary(.add, called, entry.emit(LoadField(field, other))),
        ),
      ),
    );
    final program = IrProgram(
      [declaration],
      [
        IrFunction(root, [entry]),
        IrFunction(read, [reader]),
      ],
    );
    final facts = _flow(program, root);
    expect(_number(facts.returnedBy(root)), 47);
    expect(facts.valueOf(first).objects, facts.valueOf(again).objects);
    expect(facts.valueOf(first).objects, facts.valueOf(fromReader).objects);
    expect(facts.valueOf(first).objects, isNot(facts.valueOf(other).objects));
    final state = FlowState(program, memoryLayout: _layout(program));
    final identity = facts.valueOf(first).objects.single;
    expect(state.anchoredIdentities(), contains(identity));
    expect(
      () => state.mapObjects({identity: FlowObject(first, Object())}),
      throwsArgumentError,
    );
    final repeated = ProgramFlow(
      program,
      [],
      openEntries: [read, root],
      memoryLayout: _layout(program),
    ).facts;
    expect(repeated.returnedBy(read).constant, isNull);
    expect(repeated.returnedBy(read).integers!.contains(5), isTrue);
    expect(repeated.returnedBy(read).integers!.contains(42), isTrue);
  });

  test('linked root registry exposes real identities without assuming final indices', () {
    final first = ModuleObject(
      type,
      initialFields: {field: const Constant.integer(5)},
    );
    final second = ModuleObject(
      type,
      initialFields: {field: const Constant.integer(7)},
    );
    final root = FunctionTarget(null, 'roots', .integer, []);
    final entry = Block();
    final a = entry.emit(ModuleObjectReference(first));
    final b = entry.emit(ModuleObjectReference(second));
    final table = entry.emit(ModuleRootsAddress());
    final count = entry.emit(LoadNative(table, word));
    final pointer = entry.emit(
      LoadNative(
        entry.emit(
          IntBinary(.add, table, Constant.integer(ModuleRootTable.entries)),
        ),
        word,
      ),
    );
    final actual = entry.emit(ReferenceFromAddress(pointer, type));
    final loaded = entry.emit(LoadField(field, actual));
    entry.finish(Return(loaded));
    final facts = _flow(
      IrProgram(
        [declaration],
        [
          IrFunction(root, [entry]),
        ],
      ),
      root,
    );
    expect(facts.valueOf(count).constant, isNull);
    expect(facts.valueOf(count).integers!.lower, 0);
    expect(facts.valueOf(count).integers!.upper, 2);
    expect(facts.valueOf(actual).objects, {
      ...facts.valueOf(a).objects,
      ...facts.valueOf(b).objects,
    });
    expect(facts.returnedBy(root).integers!.contains(5), isTrue);
    expect(facts.returnedBy(root).integers!.contains(7), isTrue);
  });

  test('module metadata writes fail explicitly', () {
    final root = FunctionTarget(null, 'invalid', .voidType, []);
    final entry = Block();
    entry.emit(
      StoreNative(
        entry.emit(ModuleRootsAddress()),
        word,
        const Constant.integer(7),
      ),
    );
    entry.finish(const Return());
    final program = IrProgram([], [
      IrFunction(root, [entry]),
    ]);
    expect(() => _flow(program, root), throwsStateError);
  });
}

ProgramLayout _layout(IrProgram program) => ProgramLayout(
  program.classes,
  functions: program.functions,
  nativeLayout: NativeLayout(Target.host()),
);

ProgramFlowFacts _flow(IrProgram program, FunctionTarget root) => ProgramFlow(
  program,
  [(target: root, arguments: [])],
  memoryLayout: _layout(program),
).facts;

Object? _number(FlowValue value) => switch (value.constant) {
  ScalarConstant(:final value) => value,
  _ => null,
};
