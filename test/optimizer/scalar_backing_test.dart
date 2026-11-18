import 'dart:ffi' show Int64, Uint8;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart' show FlowSource;
import 'package:dartc/src/optimizer/flow_memory.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _word = NativeScalarType(Int64);
final _layout = _Layout();
final _program = IrProgram([IrClass(ValueType.integer, [])], []);
const _offset = Constant.integer(ObjectHeader.fieldsOffset);
const _zero = Constant.integer(0);

void main() {
  test(
    'high-level scalar conversions expose allocation and current payload facts',
    () {
      for (final constant in <Constant>[
        const Constant.integer(42),
        const Constant.boolean(true),
        const Constant.floating(-0.0),
      ]) {
        final root = FunctionTarget(null, 'convert', constant.type, []);
        final b = Block();
        final materialized = b.emit(MaterializeValue(constant));
        final projected = b.emit(
          ProjectValue(materialized, ExecutionShapes.forType(constant.type)),
        );
        b.finish(Return(projected));
        final program = IrProgram(
          [IrClass(constant.type as ClassType, [])],
          [
            IrFunction(root, [b]),
          ],
        );
        final facts = ProgramFlow(program, [
          (target: root, arguments: <FlowValue>[]),
        ], memoryLayout: _layout).facts;
        expect(
          facts.returnedBy(root).constant?.structuralKey,
          constant.structuralKey,
        );
        expect(facts.valueOf(materialized).managedBackings, hasLength(1));
        expect(facts.valueOf(projected).managedBackings, isEmpty);
        expect(facts.effectsOf(materialized), contains(Effect.allocates));
        expect(facts.exitsOf(materialized).exceptional, isTrue);
        expect(facts.hasUnknownCall(materialized), isFalse);
      }
    },
  );

  test('high-level projection consumes current bytes before implementation lowering', () {
    final root = FunctionTarget(null, 'convert', .integer, []);
    final b = Block();
    final value = b.emit(MaterializeValue(const Constant.integer(42)));
    final address = b.emit(ReferenceAddress(value));
    final payload = b.emit(IntBinary(.add, address, _offset));
    b.emit(StoreNative(payload, _word, const Constant.integer(9)));
    b.finish(Return(b.emit(ProjectValue(value, ExecutionShape.word))));
    final program = IrProgram(
      [IrClass(ValueType.integer, [])],
      [
        IrFunction(root, [b]),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(facts.returnedBy(root)), 9);
    final rewritten = const ProgramStorageElimination().run(facts);
    final solved = ProgramFlow(rewritten, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(solved.returnedBy(root)), 9);
  });

  test('high-level materialization failure preserves its lexical state before commit', () {
    final slot = GlobalVariable(
      Uri.parse('memory:scalar'),
      'slot',
      ValueType.integer.nullable,
    );
    final root = FunctionTarget(null, 'convert', ValueType.integer.nullable, [
      .integer,
    ]);
    final b = Block(root.parameterTypes),
        success = Block([.integer]),
        caught = Block();
    b.emit(StoreGlobal(slot, const Constant.integer(1)));
    final materialized = MaterializeValue(b.parameters.single);
    b.finish(
      Invoke(
        materialized,
        onReturn: Jump(success, [materialized]),
        onThrow: Jump(caught),
      ),
    );
    success.emit(StoreGlobal(slot, success.parameters.single));
    success.finish(Return(success.emit(LoadGlobal(slot))));
    final caughtValue = caught.emit(LoadGlobal(slot));
    caught.finish(Return(caughtValue));
    final program = IrProgram(
      [IrClass(ValueType.integer, [])],
      [
        IrFunction(
          root,
          [b, success, caught],
          execution: FunctionExecution({
            success.parameters.single: ExecutionShape.reference,
          }),
        ),
      ],
      globals: [slot],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: [FlowValue.unknown(.integer)]),
    ], memoryLayout: _layout).facts;
    expect(facts.exitsOf(materialized).normal, isTrue);
    expect(facts.exitsOf(materialized).exceptional, isTrue);
    expect(_number(facts.valueOf(caughtValue)), 1);
    expect(facts.hasUnknownCall(materialized), isFalse);
  });

  test(
    'scalar facts retain a backing without an object or raw alternative',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
      final input = FlowValue.integerRange(FlowIntegerRange(40, 44))
          .withManagedBackings([a.object]);
      expect(input.integers, FlowIntegerRange(40, 44));
      expect(input.types, [ValueType.integer]);
      expect(input.objects, isEmpty);
      expect(input.references.isBottom, isTrue);
      final narrowed = input.restrictIntegers(FlowIntegerRange(42, 42));
      expect(_number(narrowed), 42);
      expect(narrowed.managedBackings, {a.object});
      expect(narrowed.check(.number).value.managedBackings, {a.object});
      final replacement = FlowObject(a.object.site, Object());
      expect(narrowed.mapObjects((_) => replacement).managedBackings, {
        replacement,
      });
      expect(narrowed.rebindConstants((value) => value).managedBackings, {
        a.object,
      });
      expect(
        FlowValue.unknown(.integer).withReferences([input]).references.objects,
        isEmpty,
      );
    },
  );

  test('mixed scalar and object paths retain each actual carrier', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
    final owner = ClassType(null, 'ObjectCarrier');
    final object = FlowObject(NewPayload(owner, _zero), Object());
    final mixed = _integer(42)
        .withManagedBackings([a.object])
        .join(FlowValue.object(object));
    expect(mixed.carrierReferences.objects, containsAll([a.object, object]));
    final floating = FlowObject(
      AllocatedObject(const Constant.integer(8192), ValueType.floating, _zero),
      Object(),
    );
    final numbers = _integer(42)
        .withManagedBackings([a.object])
        .join(
          FlowValue.constant(const Constant.floating(9.5))
              .withManagedBackings([floating]),
        );
    final checked = numbers.check(.integer, runtimeTypes: true);
    expect(checked.mayFail, isTrue);
    expect(checked.value.managedBackings, {a.object});
    expect(_number(checked.value), 42);
  });

  test('joining an unknown carrier keeps that path during projection', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
    final known = _integer(42).withManagedBackings([a.object]);
    final joined = known.join(FlowValue.unknown(.integer));
    expect(joined.managedBackings, {a.object});
    expect(joined.hasUnknownBacking, isTrue);
    expect(_read(a.state, joined).constant, isNull);
    final other = _allocate(a.state, 43);
    final finite = known.join(_integer(43).withManagedBackings([other.object]));
    expect(finite.hasUnknownBacking, isFalse);
    expect(_read(other.state, finite).integers, FlowIntegerRange(42, 43));
  });

  test(
    'call projection and renaming retain the payload and no raw authority',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
      final value = _integer(42).withManagedBackings([a.object]);
      final projected = a.state.project(
        [value],
        access: (
          fields: <InstanceField>{},
          globals: <GlobalVariable>{},
          data: <NativeData>{},
          modules: <ModuleObject>{},
          context: false,
          cells: false,
          memory: false,
          writes: false,
          exposed: false,
          rawWrites: false,
        ),
      );
      expect(projected.containsObject(a.object), isTrue);
      expect(_number(_read(projected, value)), 42);
      final formal = FlowObject(a.object.site, Object());
      final mapped = projected.mapObjects({a.object: formal});
      final input = value.mapObjects((_) => formal);
      expect(_number(_read(mapped, input)), 42);
      expect(mapped.reachableValues([input]).objects, contains(formal));
      expect(mapped.exposedFrom([input]).objects, isEmpty);
    },
  );

  test('unknown Dart access cannot mutate a private scalar carrier', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
    final value = FlowValue.unknown(.integer).withManagedBackings([a.object]);
    final exposed = a.state.copy()..escape([value]);
    expect(exposed.escapedValues.objects, contains(a.object));
    expect(exposed.exposedValues.objects, isEmpty);
    exposed.invalidate([value]);
    expect(_number(_read(exposed, value)), 42);
    // An actual raw address grants access independently of the scalar value.
    exposed.invalidate([FlowValue.address(FlowAddress(a.object, 0))]);
    expect(_read(exposed, value).constant, isNull);
  });

  test('projection reads current bytes after an actual raw write', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
    final value = _integer(42).withManagedBackings([a.object]);
    final written = _step(
      a.state,
      StoreObjectData(a.object.site, _offset, _word, const Constant.integer(9)),
      [
        FlowValue.object(a.object),
        _integer(ObjectHeader.fieldsOffset),
        _integer(9),
      ],
    ).normal!;
    expect(_number(value), 42);
    expect(_number(_read(written, value)), 9);
    final baseline = a.state.project([value]).copy(resetWrites: true);
    final output = written.project([value]);
    final applied = a.state.applySummary(
      baseline,
      output,
      mapObject: (value) => value,
      mapValue: (value) => value,
    );
    expect(_number(_read(applied, value)), 9);
  });

  test(
    'traced slots preserve values and raw reads reveal the actual carrier',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
      final value = _integer(42).withManagedBackings([a.object]);
      final memory = FlowMemory(0, 8).writeReference(0, value);
      final read = memory.readReference(0)!;
      expect(_number(read), 42);
      expect(read.managedBackings, {a.object});
      expect(read.references.isBottom, isTrue);
      final raw = memory.read(0, _word, _layout.nativeLayout);
      expect(raw.constant, isNull);
      expect(raw.references.objects, {a.object});
      final partial = memory
          .write(3, NativeScalarType(Uint8), _integer(0), _layout.nativeLayout)
          .read(0, _word, _layout.nativeLayout);
      expect(partial.references.objects, {a.object});
    },
  );

  test(
    'unknown reference entries retain possible carriers without raw access',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
      final unknown = FlowValue.unknown(.integer)
          .withManagedBackings(const [], unknown: true);
      expect(a.state.project([unknown]).containsObject(a.object), isTrue);
      expect(a.state.exposedFrom([unknown]).objects, isEmpty);
      final target = FunctionTarget(null, 'externalInput', .integer, [
        .integer,
      ]);
      final entry = Block(target.parameterTypes);
      entry.finish(Return(entry.parameters.single));
      final program = IrProgram(
        [],
        [
          IrFunction(target, [entry]),
        ],
        executionShapes: ExecutionShapes(
          entries: {
            target: ExecutionSignature([
              ExecutionShape.reference,
            ], ExecutionShape.reference),
          },
        ),
      );
      final facts = ProgramFlow(
        program,
        [],
        openEntries: [target],
        memoryLayout: _layout,
      ).facts;
      expect(facts.returnedBy(target).hasUnknownBacking, isTrue);
      expect(facts.returnedBy(target).objects, isEmpty);
      expect(facts.returnedBy(target).references.isBottom, isTrue);
    },
  );

  test(
    'raw unknown carrier snapshots retain provenance through fact operations',
    () {
      final otherType = ClassType(null, 'Unrelated');
      final program = IrProgram([
        IrClass(ValueType.integer, []),
        IrClass(otherType, []),
      ], []);
      final a = _allocate(FlowState(program, memoryLayout: _layout), 42);
      final other = _step(a.state, NewPayload(otherType, _zero), [_integer(0)]);
      final state = other.normal!;
      final word = FlowValue.unknown(.integer);
      final semantic = word.withManagedBackings(const [], unknown: true);
      expect(a.state.exposedFrom([word]).objects, isEmpty);
      expect(a.state.exposedFrom([semantic]).objects, isEmpty);
      final memory = FlowMemory(0, 8).writeReference(0, semantic);
      final raw = memory.read(0, _word, _layout.nativeLayout);
      final source = FlowSource(
        Block([ValueType.integer]).parameters.single,
        Object(),
      );
      for (final value in [
        raw,
        memory.read(1, _word, _layout.nativeLayout),
        memory.readRange(FlowIntegerRange(0, 1), _word, _layout.nativeLayout),
        raw.withSources([source]),
        raw.asExternal(),
        raw.check(.integer).value,
        raw.join(_integer(0)),
        raw.restrictIntegers(FlowIntegerRange(0, 100)),
        raw.mapObjects((object) => object),
        raw.rebindConstants((constant) => constant),
      ]) {
        expect(value.references.rawBackingTypes, contains(ValueType.integer));
        expect(state.project([value]).containsObject(a.object), isTrue);
        expect(
          state.project([value]).containsObject(other.value.objects.single),
          isFalse,
        );
        final invalidated = state.copy()..invalidate([value]);
        expect(
          _read(
            invalidated,
            _integer(42).withManagedBackings([a.object]),
          ).constant,
          isNull,
        );
      }
      final boolean = FlowValue.unknown(.boolean)
          .withManagedBackings(const [], unknown: true);
      final unrelated = FlowMemory(
        0,
        8,
      ).writeReference(0, boolean).read(0, _word, _layout.nativeLayout);
      expect(a.state.project([unrelated]).containsObject(a.object), isFalse);
    },
  );

  test('stored and bound reads use the current scalar carrier payload', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 42);
    final value = _integer(42).withManagedBackings([a.object]);
    final cell = NewCell(CellType(.object), const Constant.integer(42));
    final stored = _step(a.state, cell, [value]);
    final changed = _step(
      stored.normal!,
      StoreObjectData(a.object.site, _offset, _word, const Constant.integer(9)),
      [
        FlowValue.object(a.object),
        _integer(ObjectHeader.fieldsOffset),
        _integer(9),
      ],
    ).normal!;
    final read = ReadCell(cell);
    expect(_number(changed.boundValueOf(read, [stored.value])!), 9);
    expect(_number(_step(changed, read, [stored.value]).value), 9);
  });

  test('num-view arithmetic keeps its residual payload observation', () {
    final root = FunctionTarget(null, 'arithmetic', .number, []);
    final b = Block();
    final object = b.emit(
      AllocatedObject(const Constant.integer(4096), ValueType.integer, _zero),
    );
    b.emit(StoreObjectData(object, _offset, _word, const Constant.integer(42)));
    final value = b.emit(MaterializedValue(const Constant.integer(42), object));
    final address = b.emit(ReferenceAddress(value));
    final payload = b.emit(IntBinary(.add, address, _offset));
    b.emit(StoreNative(payload, _word, const Constant.integer(9)));
    final number = b.emit(TypeView(value, ValueType.number));
    b.finish(
      Return(b.emit(NumericBinary(.add, number, const Constant.integer(1)))),
    );
    final program = IrProgram(
      [IrClass(ValueType.integer, [])],
      [
        IrFunction(root, [b]),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(facts.returnedBy(root)), 10);
    final rewritten = const ProgramStorageElimination().run(facts);
    final solved = ProgramFlow(rewritten, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(solved.returnedBy(root)), 10);
  });

  test('object views compare current scalar bytes after raw mutation', () {
    for (final identity in [false, true]) {
      final root = FunctionTarget(null, 'compare', .boolean, []);
      final b = Block();
      final object = b.emit(
        AllocatedObject(const Constant.integer(4096), ValueType.integer, _zero),
      );
      b.emit(
        StoreObjectData(object, _offset, _word, const Constant.integer(42)),
      );
      final value = b.emit(
        MaterializedValue(const Constant.integer(42), object),
      );
      final address = b.emit(ReferenceAddress(value));
      final payload = b.emit(IntBinary(.add, address, _offset));
      b.emit(StoreNative(payload, _word, const Constant.integer(9)));
      final view = b.emit(TypeView(value, ValueType.object));
      final other = b.emit(
        TypeView(const Constant.integer(9), ValueType.object),
      );
      b.finish(
        Return(b.emit(identity ? Identical(view, other) : Equals(view, other))),
      );
      final program = IrProgram(
        [IrClass(ValueType.integer, [])],
        [
          IrFunction(root, [b]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(
        _number(facts.returnedBy(root)),
        isTrue,
        reason:
            "identity=$identity view=${facts.valueOf(view).constant} backings=${facts.valueOf(view).managedBackings.length} unknown=${facts.valueOf(view).hasUnknownBacking} return=${facts.returnedBy(root).unknownTypes}",
      );
      expect(_number(facts.valueOf(view)), 9);
      expect(facts.valueOf(value).constant, isNull);
      final eliminated = const ProgramStorageElimination().run(facts);
      final eliminatedFacts = ProgramFlow(eliminated, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(_number(eliminatedFacts.returnedBy(root)), isTrue);
      final rewritten = const ProgramSimplification().run(facts);
      final solved = ProgramFlow(rewritten, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(_number(solved.returnedBy(root)), isTrue);
      final afterObservation = const ProgramStorageElimination().run(solved);
      expect(
        afterObservation.functions
            .expand((body) => body.blocks)
            .expand((block) => block.instructions)
            .where(
              (operation) =>
                  operation is StoreNative || operation is StoreObjectData,
            ),
        isEmpty,
        reason: 'Reference transport alone does not demand scalar bytes.',
      );
    }
  });

  test(
    'a raw address roundtrip restores the carrier after payload mutation',
    () {
      final root = FunctionTarget(null, 'roundtrip', .integer, []);
      final b = Block();
      final object = b.emit(
        AllocatedObject(const Constant.integer(4096), ValueType.integer, _zero),
      );
      b.emit(
        StoreObjectData(object, _offset, _word, const Constant.integer(42)),
      );
      final value = b.emit(
        MaterializedValue(const Constant.integer(42), object),
      );
      final address = b.emit(ReferenceAddress(value));
      final payload = b.emit(IntBinary(.add, address, _offset));
      b.emit(StoreNative(payload, _word, const Constant.integer(9)));
      final restored = b.emit(ReferenceFromAddress(address, ValueType.integer));
      final projected = b.emit(LoadObjectData(restored, _offset, _word));
      b.finish(Return(projected));
      final program = IrProgram(
        [IrClass(ValueType.integer, [])],
        [
          IrFunction(root, [b]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(_number(facts.returnedBy(root)), 9);
      expect(facts.valueOf(restored).objects, isEmpty);
      expect(
        facts.valueOf(restored).managedBackings,
        facts.valueOf(value).managedBackings,
      );
      expect(facts.valueOf(restored).constant, isNull);
    },
  );

  test('actual materialized value survives a call and payload projection', () {
    final helper = FunctionTarget(null, 'identity', .integer, [.integer]);
    final h = Block(helper.parameterTypes);
    // Build the real body without an assumed source-language Object upcast.
    h.finish(Return(h.parameters.single));
    final root = FunctionTarget(null, 'root', .integer, []);
    final b = Block();
    final object = b.emit(
      AllocatedObject(const Constant.integer(4096), ValueType.integer, _zero),
    );
    b.emit(StoreObjectData(object, _offset, _word, const Constant.integer(42)));
    final value = b.emit(MaterializedValue(const Constant.integer(42), object));
    final call = b.emit(DirectCall(helper, [value]));
    final projected = b.emit(LoadObjectData(call, _offset, _word));
    b.finish(Return(projected));
    final program = IrProgram(
      [IrClass(ValueType.integer, [])],
      [
        IrFunction(helper, [h]),
        IrFunction(root, [b]),
      ],
      executionShapes: ExecutionShapes(
        entries: {
          helper: ExecutionSignature([
            ExecutionShape.reference,
          ], ExecutionShape.reference),
        },
      ),
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(facts.returnedBy(root)), 42);
    expect(facts.valueOf(value).objects, isEmpty);
    expect(facts.valueOf(value).managedBackings, hasLength(1));
    expect(
      facts.valueOf(call).managedBackings,
      facts.valueOf(value).managedBackings,
    );
    expect(facts.valueOf(projected).references.isBottom, isTrue);
    final eliminated = const ProgramStorageElimination().run(facts);
    final solved = ProgramFlow(eliminated, [
      (target: root, arguments: <FlowValue>[]),
    ], memoryLayout: _layout).facts;
    expect(_number(solved.returnedBy(root)), 42);
    expect(eliminated.executionShapes, same(program.executionShapes));
  });
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([.word]);
}

({FlowState state, FlowObject object}) _allocate(FlowState state, int payload) {
  final op = AllocatedObject(
    const Constant.integer(4096),
    ValueType.integer,
    _zero,
  );
  final allocated = _step(state, op, [_integer(4096), _integer(0)]);
  final object = allocated.value.objects.single;
  final stored = _step(
    allocated.normal!,
    StoreObjectData(op, _offset, _word, Constant.integer(payload)),
    [allocated.value, _integer(ObjectHeader.fieldsOffset), _integer(payload)],
  );
  return (state: stored.normal!, object: object);
}

FlowValue _integer(int value) => FlowValue.constant(Constant.integer(value));
Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;
FlowValue _read(FlowState state, FlowValue value) => _step(
  state,
  LoadObjectData(Block([ValueType.integer]).parameters.single, _offset, _word),
  [value, _integer(ObjectHeader.fieldsOffset)],
).value;
FlowResult _step(FlowState state, Instruction op, List<FlowValue> operands) =>
    state.transfer(
      op,
      operands,
      allocate: (site) => FlowObject(site, Object()),
      repeated: false,
      invoke: (_, _, _) => throw StateError('unexpected call'),
      call: (_, _, _) => throw StateError('unexpected call'),
    )!;
