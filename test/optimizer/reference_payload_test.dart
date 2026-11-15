import 'dart:ffi' show Uint8, Int64;

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _type = ClassType(null, 'References');
final _class = IrClass(_type, [], referencePayload: true);
final _program = IrProgram([_class], []);
final _layout = _Layout();
final _activation = Object();
final _owner = ObjectConstant(_type, {});
const _start = ObjectHeader.fieldsOffset;
const _offset = Constant.integer(_start);
final _callback = FunctionTarget(null, 'callback', .integer, [.integer]);
final _function = FlowValue.constant(FunctionConstant(_callback));

void main() {
  test('rebound SSA definitions do not alias earlier payload contents', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final value = FlowValue.integerRange(FlowIntegerRange(3, 9))
        .withSource(Block([.integer]).parameters.single, _activation);
    final before = _store(allocation.state, allocation.value, value);
    final after = before.copy()..retainSources((_) => false);
    expect(_load(before, allocation.value), value);
    expect(_load(after, allocation.value), value.withSources(const []));
  });

  test('reference payload loop joins widen stored ranges without losing slot bounds', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final before = _store(
      allocation.state,
      allocation.value,
      FlowValue.integerRange(FlowIntegerRange(3, 5)),
    );
    final after = _store(
      before,
      allocation.value,
      FlowValue.integerRange(FlowIntegerRange(3, 9)),
    );
    final union = before.copy()..join(after);
    final widened = before.copy()..join(after, widen: true);
    expect(_load(union, allocation.value).integers, FlowIntegerRange(3, 9));
    expect(
      _load(widened, allocation.value).integers,
      FlowIntegerRange(3, FlowIntegerRange.maximum),
    );
    expect(widened.join(after, widen: true), isFalse);
    expect(
      _load(widened, allocation.value, offset: _start + 8).constant,
      isNull,
    );
  });

  test('immutable payload reads preserve functions, objects and owner alternatives', () {
    final child = ObjectConstant(
      _type,
      {},
      payload: [const Constant.integer(37)],
    );
    final data = ObjectConstant(
      _type,
      {},
      payload: [FunctionConstant(_callback), child, const Constant.nullValue()],
    );
    final owner = FlowValue.constant(data);
    final state = FlowState(_program, memoryLayout: _layout);
    expect(_load(state, owner), _function);
    expect(_load(state, owner, offset: _start + 8).constant, same(child));
    expect(
      _load(state, owner, offset: _start + 16).constant?.structuralKey,
      const Constant.nullValue().structuralKey,
    );
    final other = ObjectConstant(_type, {}, payload: [child]);
    final alternatives = _load(state, owner.join(FlowValue.constant(other)));
    expect(
      alternatives.constants.map((value) => value.structuralKey),
      unorderedEquals([
        FunctionConstant(_callback).structuralKey,
        child.structuralKey,
      ]),
    );
    for (final offset in [_start - 8, _start + 1, _start + 24]) {
      expect(_load(state, owner, offset: offset).constant, isNull);
    }
    expect(_load(FlowState(_program), owner).constant, isNull);
    final unknown = _step(state, LoadObjectReference(data, _offset), [
      owner,
      FlowValue.unknown(.integer),
    ]).value;
    expect(unknown.constant, isNull);
    expect(
      state
          .reachableValues([unknown.references])
          .constants
          .map((value) => value.structuralKey),
      contains(FunctionConstant(_callback).structuralKey),
    );
    state.escape([owner]);
    expect(
      state.escapedValues.constants.map((value) => value.structuralKey),
      contains(const Constant.integer(37).structuralKey),
    );
    state.invalidate([owner]);
    expect(_load(state, owner), _function);
  });

  test('bounded reference reads require proven alignment and join all possible slots', () {
    final data = ObjectConstant(
      _type,
      {},
      payload: [
        const Constant.integer(7),
        const Constant.integer(9),
        const Constant.integer(7),
      ],
    );
    final owner = FlowValue.constant(data);
    final state = FlowState(_program, memoryLayout: _layout);
    FlowValue read(
      FlowState state,
      FlowValue owner,
      FlowIntegerRange offsets,
    ) => _step(state, LoadObjectReference(data, _offset), [
      owner,
      FlowValue.integerRange(offsets),
    ]).value;
    expect(
      read(
        state,
        owner,
        FlowIntegerRange(_start, _start + 16, zeroBits: 3),
      ).integers,
      FlowIntegerRange(7, 9),
    );
    for (final offsets in [
      FlowIntegerRange(_start, _start + 16),
      FlowIntegerRange(_start - 8, _start + 16, zeroBits: 3),
      FlowIntegerRange(_start, _start + 24, zeroBits: 3),
    ]) {
      expect(read(state, owner, offsets).integers, isNull);
    }
    final offsets = FlowIntegerRange(_start, _start + 16, zeroBits: 3);
    final allocation = _allocate(state, 24);
    var filled = allocation.state;
    for (var offset = _start; offset <= _start + 16; offset += 8) {
      filled = _store(filled, allocation.value, _integer(7), offset: offset);
    }
    expect(read(filled, allocation.value, offsets), _integer(7));
    final partial = _step(
      filled,
      StoreObjectData(_owner, _offset, NativeScalarType(Uint8), _offset),
      [allocation.value, _integer(_start + 9), _integer(0)],
    ).normal!;
    expect(read(partial, allocation.value, offsets).constant, isNull);
    expect(read(filled, allocation.value, offsets), _integer(7));
    final untraced = _allocate(
      FlowState(_program, memoryLayout: _Layout(traced: false)),
      24,
    );
    expect(read(untraced.state, untraced.value, offsets).constant, isNull);
  });

  test(
    'sparse aligned reference reads retain interior values in large payloads',
    () {
      const length = 1 << 30;
      final a = _allocate(FlowState(_program, memoryLayout: _layout), length);
      final offsets = FlowValue.integerRange(
        FlowIntegerRange(_start, _start + length - 8, zeroBits: 3),
      );
      final middle = _store(
        a.state,
        a.value,
        _function,
        offset: _start + length ~/ 2,
      );
      final value = _step(middle, LoadObjectReference(_owner, _offset), [
        a.value,
        offsets,
      ]).value;
      expect(value.unknownTypes, isEmpty);
      expect(
        value.constants.map((value) => value.structuralKey),
        unorderedEquals([
          const Constant.nullValue().structuralKey,
          FunctionConstant(_callback).structuralKey,
        ]),
      );
    },
  );

  test(
    'constant reference bytes retain language values through raw copies',
    () {
      final data = ObjectConstant(
        _type,
        {},
        payload: [FunctionConstant(_callback)],
      );
      final allocation = _allocate(
        FlowState(_program, memoryLayout: _layout),
        8,
      );
      final address = FlowValue.address(FlowAddress(data, _start));
      final raw = _step(
        allocation.state,
        LoadNative(const Constant.integer(0), NativeScalarType(Int64)),
        [address],
      ).value;
      expect(raw.constant, isNull);
      expect(raw.types, [ValueType.integer]);
      expect(
        raw.references.constants.map((value) => value.structuralKey),
        contains(FunctionConstant(_callback).structuralKey),
      );
      final copied = _step(
        allocation.state,
        CopyNative(
          const Constant.integer(0),
          const Constant.integer(0),
          NativeScalarType(Int64),
        ),
        [_address(allocation.value, _start), address],
      );
      expect(_load(copied.normal!, allocation.value), _function);
    },
  );

  test(
    'ordinary IR executes immutable and newly allocated reference payloads',
    () {
      final source = ObjectConstant(
        _type,
        {},
        payload: [const Constant.integer(37)],
      );
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final root = FunctionTarget(
        null,
        'copyReference',
        ValueType.object.nullable,
        [],
        typeParameters: [t],
      );
      final block = Block();
      final value = block.emit(LoadObjectReference(source, _offset));
      final allocation = block.emit(
        NewPayload(_type, const Constant.integer(8)),
      );
      block.emit(StoreObjectReference(allocation, _offset, value));
      block.finish(
        Return(block.emit(LoadObjectReference(allocation, _offset))),
      );
      final body = IrFunction(root, [block]);
      final program = IrProgram([_class], [body]);
      for (final type in [ValueType.integer, ValueType.string]) {
        expect(IrInterpreter(program, {}).run(body, [], {t: type}), 37);
      }
      final facts = ProgramFlow(program, [
        (target: root, arguments: <FlowValue>[]),
      ], memoryLayout: _layout).facts;
      expect(
        facts.returnedBy(root).constant?.structuralKey,
        const Constant.integer(37).structuralKey,
      );
    },
  );

  test(
    'new payload has null reference slots only within its declared bounds',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      expect(
        _load(a.state, a.value).constant,
        isA<ScalarConstant>().having((value) => value.value, 'value', isNull),
      );
      for (final offset in [_start - 8, _start + 1, _start + 16]) {
        expect(_load(a.state, a.value, offset: offset).constant, isNull);
      }
      final noLayout = _allocate(FlowState(_program), 16);
      expect(_load(noLayout.state, noLayout.value).constant, isNull);
      final untraced = _allocate(
        FlowState(_program, memoryLayout: _Layout(traced: false)),
        16,
      );
      expect(_load(untraced.state, untraced.value).constant, isNull);
      final unknown = _step(
        a.state,
        NewPayload(_type, const Constant.integer(0)),
        [.unknown(.integer)],
      );
      expect(_load(unknown.normal!, unknown.value).constant, isNull);
      expect(unknown.exceptional, isNotNull);
    },
  );

  test('reference writes keep language values and raw overlap invalidates their slots', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final saved = _store(a.state, a.value, _function);
    final both = _store(saved, a.value, _integer(19), offset: _start + 8);
    expect(_load(both, a.value), _function);
    expect(_load(both, a.value, offset: _start + 8), _integer(19));
    final raw = _step(
      both,
      LoadObjectData(_owner, _offset, NativeScalarType(Int64)),
      [a.value, _integer(_start)],
    ).value;
    expect(raw.constant, isNull);
    expect(raw.types, [ValueType.integer]);
    expect(
      raw.references.constants,
      contains(
        isA<FunctionConstant>().having(
          (value) => value.target,
          'target',
          _callback,
        ),
      ),
    );
    final partial = _step(
      both,
      StoreObjectData(
        _owner,
        const Constant.integer(_start + 1),
        NativeScalarType(Uint8),
        const Constant.integer(0),
      ),
      [a.value, _integer(_start + 1), _integer(0)],
    ).normal!;
    expect(_load(partial, a.value).constant, isNull);
    expect(_load(partial, a.value, offset: _start + 8), _integer(19));
    final cleared = _step(
      partial,
      StoreObjectData(
        _owner,
        _offset,
        NativeScalarType(Int64),
        const Constant.integer(0),
      ),
      [a.value, _integer(_start), _integer(0)],
    ).normal!;
    expect(
      _load(cleared, a.value).constant,
      isA<ScalarConstant>().having((value) => value.value, 'value', isNull),
    );
    final replaced = _store(both, a.value, _integer(23));
    expect(_load(replaced, a.value), _integer(23));
    expect(
      replaced.reachableValues([a.value]).constants,
      isNot(
        contains(
          isA<FunctionConstant>().having(
            (value) => value.target,
            'target',
            _callback,
          ),
        ),
      ),
    );
    expect(_load(saved, a.value), _function);
  });

  test('joins and ambiguous writes preserve alternatives without assigning one value to every object', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final b = _allocate(a.state, 8);
    final saved = _store(b.state, a.value, _function);
    final joined = saved.copy()..join(b.state);
    final value = _load(joined, a.value);
    expect(
      value.constants,
      containsAll([
        const Constant.nullValue(),
        isA<FunctionConstant>().having(
          (value) => value.target,
          'target',
          _callback,
        ),
      ]),
    );
    expect(value.unknownTypes, isEmpty);
    final aliases = _store(b.state, a.value.join(b.value), _function);
    for (final owner in [a.value, b.value]) {
      expect(
        _load(aliases, owner).constants,
        containsAll([
          const Constant.nullValue(),
          isA<FunctionConstant>().having(
            (value) => value.target,
            'target',
            _callback,
          ),
        ]),
      );
    }
    final repeated = _allocate(b.state, 8, repeated: true);
    expect(
      _load(
        _store(repeated.state, repeated.value, _function),
        repeated.value,
      ).constants,
      contains(const Constant.nullValue()),
    );
  });

  test('copies, call summaries and escaped payloads retain actual objects and functions', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final input = a.state.project([a.value]);
    final b = _allocate(input, 8);
    final child = _store(b.state, b.value, _function);
    final saved = _store(child, a.value, b.value);
    final copied = _step(
      saved,
      CopyNative(
        const Constant.integer(0),
        const Constant.integer(0),
        NativeArrayType(NativeScalarType(Uint8), 8),
      ),
      [_address(a.value, _start + 8), _address(a.value, _start)],
    ).normal!;
    expect(_load(copied, a.value, offset: _start + 8).objects, b.value.objects);
    final projected = copied.project([a.value]);
    expect(projected.containsObject(b.value.objects.single), isTrue);
    expect(
      projected.reachableValues([a.value]).constants,
      contains(
        isA<FunctionConstant>().having(
          (value) => value.target,
          'target',
          _callback,
        ),
      ),
    );
    final remapped = FlowObject(b.value.objects.single.site, Object());
    FlowObject map(FlowObject object) =>
        object == b.value.objects.single ? remapped : object;
    final returned = a.state.applySummary(
      input,
      copied,
      mapObject: map,
      mapValue: (value) => value.mapObjects(map),
    );
    expect(_load(returned, a.value).objects, [remapped]);
    expect(_load(returned, FlowValue.object(remapped)), _function);
    final external = copied.copy()..invalidate([a.value]);
    expect(_load(external, a.value).constant, isNull);
    expect(
      external.reachableValues([a.value]).objects,
      contains(b.value.objects.single),
    );
    final escaped = copied.copy()..escape([a.value]);
    final overwritten = _store(
      _store(escaped, a.value, .constant(const Constant.nullValue())),
      a.value,
      .constant(const Constant.nullValue()),
      offset: _start + 8,
    );
    expect(overwritten.escapedValues.objects, contains(b.value.objects.single));
    expect(
      overwritten.escapedValues.constants,
      contains(
        isA<FunctionConstant>().having(
          (value) => value.target,
          'target',
          _callback,
        ),
      ),
    );
    final unknown = _step(
      copied,
      StoreObjectReference(_owner, _offset, const Constant.nullValue()),
      [a.value, .unknown(.integer), _function],
    ).normal!;
    expect(_load(unknown, b.value).constant, isNull);
    expect(
      unknown.escapedValues.constants,
      contains(
        isA<FunctionConstant>().having(
          (value) => value.target,
          'target',
          _callback,
        ),
      ),
    );
  });

  test('raw and reference writes cannot leave stale ordinary field facts', () {
    final type = ClassType(null, 'Holder');
    final field = InstanceField(type, 'value', .object.nullable);
    final constructor = FunctionTarget(
      null,
      '',
      .voidType,
      [],
      owner: type,
      kind: .initializer,
    );
    final program = IrProgram(
      [
        IrClass(type, [field], constructors: [constructor]),
      ],
      [
        IrFunction(constructor, [
          Block(constructor.parameterTypes)..finish(const Return()),
        ]),
      ],
    );
    final create = Construct(constructor, []);
    final state = FlowState(program, memoryLayout: _layout).construct(
      FlowObject(create, _activation),
      constructor,
      const [],
      repeated: false,
      invoke: (_, _, state) => FlowResult(
        value: .constant(const Constant.nullValue()),
        normal: state,
      ),
    );
    final written = _step(
      state.normal!,
      StoreField(field, create, const Constant.integer(19)),
      [state.value, _integer(19)],
    ).normal!;
    final read = LoadField(field, create);
    expect(written.boundValueOf(read, [state.value]), _integer(19));
    for (final operation in <Instruction>[
      StoreObjectData(
        create,
        _offset,
        NativeScalarType(Int64),
        const Constant.integer(0),
      ),
      StoreObjectReference(create, _offset, const Constant.nullValue()),
    ]) {
      final overwritten = _step(written, operation, [
        state.value,
        _integer(_start),
        operation is StoreObjectData
            ? _integer(0)
            : .constant(const Constant.nullValue()),
      ]).normal!;
      expect(overwritten.boundValueOf(read, [state.value])!.constant, isNull);
    }
  });

  test('the solver follows a callback overwritten through a helper and removes its unused payload', () {
    final unused = FunctionTarget(null, 'unused', .integer, [.integer]);
    final callback = Block(_callback.parameterTypes);
    callback.finish(
      Return(
        callback.emit(
          IntBinary(
            .add,
            callback.parameters.single,
            const Constant.integer(1),
          ),
        ),
      ),
    );
    final replace = FunctionTarget(null, 'replace', .voidType, [
      _type,
      _callback.signature,
    ]);
    final body = Block(replace.parameterTypes);
    body.emit(
      StoreObjectReference(body.parameters[0], _offset, body.parameters[1]),
    );
    body.finish(const Return());
    final root = FunctionTarget(null, 'run', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    final owner = entry.emit(NewPayload(_type, const Constant.integer(8)));
    entry.emit(StoreObjectReference(owner, _offset, FunctionConstant(unused)));
    entry.emit(DirectCall(replace, [owner, FunctionConstant(_callback)]));
    final loaded = entry.emit(
      UncheckedCast(
        entry.emit(LoadObjectReference(owner, _offset)),
        _callback.signature,
      ),
    );
    final call = entry.emit(FunctionCall(loaded, [entry.parameters.single]));
    entry.finish(Return(call));
    var program = IrProgram(
      [_class],
      [
        IrFunction(root, [entry]),
        IrFunction(replace, [body]),
        IrFunction(_callback, [callback]),
        IrFunction(unused, [
          Block(unused.parameterTypes)
            ..finish(const Return(Constant.integer(99))),
        ]),
      ],
    );
    final entries = [
      (target: root, arguments: [FlowValue.unknown(.integer)]),
    ];
    ProgramFlowFacts analyze() =>
        ProgramFlow(program, entries, memoryLayout: _layout).facts;
    final facts = analyze();
    expect(facts.targetsOf(call), [_callback]);
    expect(facts.definitions, isNot(contains(unused)));
    program = const ProgramSimplification().run(facts);
    program = const ProgramStorageElimination().run(analyze());
    program = const ProgramSimplification().run(analyze());
    final remaining = analyze();
    expect(
      _operations(program, remaining).where(
        (op) =>
            op is NewPayload ||
            op is LoadObjectReference ||
            op is StoreObjectReference,
      ),
      isEmpty,
    );
    final function = program.implementationOf(root) as IrFunction;
    for (final input in [-4, 0, 41]) {
      expect(IrInterpreter(program, {}).run(function, [input]), input + 1);
    }
  });

  test('opaque closure storage keeps its captured references without assuming a payload class', () {
    final outer = FunctionTarget(null, 'scope', .voidType, []);
    final target = FunctionTarget(
      null,
      'closure',
      .integer,
      [],
      kind: .closure,
      enclosing: outer,
      sourceOffset: 1,
      captures: [_type],
    );
    final captured = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final operation = MakeClosure(target, [_owner]);
    final closure = FlowObject(operation, _activation);
    final state = captured.state.copy()
      ..retain(closure, [captured.value], repeated: false);
    final value = _load(state, FlowValue.object(closure));
    expect(value.constant, isNull);
    expect(value.references.objects, contains(captured.value.objects.single));
  });

  test('an escaping return preserves its initialized reference payload', () {
    final root = FunctionTarget(null, 'expose', _type, [.object.nullable]);
    final block = Block(root.parameterTypes);
    final owner = block.emit(NewPayload(_type, const Constant.integer(8)));
    block.emit(StoreObjectReference(owner, _offset, block.parameters.single));
    block.finish(Return(owner));
    final program = IrProgram(
      [_class],
      [
        IrFunction(root, [block]),
      ],
    );
    final optimized =
        ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramStorageElimination(),
        ]).run(
          program,
          [
            (target: root, arguments: [FlowValue.unknown(.object.nullable)]),
          ],
          escapingReturns: [root],
          memoryLayoutFor: (_) => _Layout(),
        );
    expect(
      _operations(
        optimized.program,
        optimized,
      ).whereType<StoreObjectReference>(),
      hasLength(1),
    );
    expect(optimized.returnedBy(root).objects, hasLength(1));
  });

  test('unknown inputs crossing branches become SSA values instead of reference slots', () {
    final root = FunctionTarget(null, 'choose', .object.nullable, [
      .boolean,
      .object.nullable,
      .object.nullable,
    ]);
    final entry = Block(root.parameterTypes),
        left = Block(),
        right = Block(),
        join = Block([ValueType.integer]);
    final owner = entry.emit(NewPayload(_type, const Constant.integer(16)));
    entry.finish(Branch(entry.parameters[0], Jump(left), Jump(right)));
    left.emit(StoreObjectReference(owner, _offset, entry.parameters[1]));
    left.finish(Jump(join, [_offset]));
    right.emit(
      StoreObjectReference(
        owner,
        const Constant.integer(_start + 8),
        entry.parameters[2],
      ),
    );
    right.finish(Jump(join, [const Constant.integer(_start + 8)]));
    join.finish(
      Return(join.emit(LoadObjectReference(owner, join.parameters.single))),
    );
    var program = IrProgram(
      [_class],
      [
        IrFunction(root, [entry, left, right, join]),
      ],
    );
    final entries = [
      (
        target: root,
        arguments: root.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ];
    ProgramFlowFacts analyze() =>
        ProgramFlow(program, entries, memoryLayout: _layout).facts;
    program = const ProgramStoragePromotion().run(analyze());
    program = const ProgramStorageElimination().run(analyze());
    program = const ProgramSimplification().run(analyze());
    expect(
      _operations(program, analyze()).where(
        (op) =>
            op is NewPayload ||
            op is LoadObjectReference ||
            op is StoreObjectReference,
      ),
      isEmpty,
    );
    final function = program.implementationOf(root) as IrFunction;
    for (final first in [false, true]) {
      expect(
        IrInterpreter(program, {}).run(function, [first, 'left', 'right']),
        first ? 'left' : 'right',
      );
    }
  });
}

Iterable<Instruction> _operations(IrProgram program, ProgramFlowFacts facts) =>
    program.functions
        .where((body) => facts.definitions.contains(body.target))
        .expand((body) => body.blocks)
        .expand(
          (block) => [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        );

final class _Layout({final bool traced = true}) implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));
  @override
  ObjectLayout objectLayout(ClassType type) =>
      ObjectLayout([], tracesPayload: traced);
}

({FlowState state, FlowValue value}) _allocate(
  FlowState state,
  int bytes, {
  bool repeated = false,
}) {
  final result = _step(state, NewPayload(_type, Constant.integer(bytes)), [
    _integer(bytes),
  ], repeated: repeated);
  return (state: result.normal!, value: result.value);
}

FlowValue _integer(int value) => FlowValue.constant(Constant.integer(value));
FlowValue _address(FlowValue owner, int offset) =>
    FlowValue.address(FlowAddress(owner.objects.single, offset));
FlowValue _load(FlowState state, FlowValue owner, {int offset = _start}) =>
    _step(state, LoadObjectReference(_owner, Constant.integer(offset)), [
      owner,
      _integer(offset),
    ]).value;
FlowState _store(
  FlowState state,
  FlowValue owner,
  FlowValue value, {
  int offset = _start,
}) => _step(
  state,
  StoreObjectReference(
    _owner,
    Constant.integer(offset),
    const Constant.nullValue(),
  ),
  [owner, _integer(offset), value],
).normal!;
FlowResult _step(
  FlowState state,
  Instruction operation,
  List<FlowValue> operands, {
  bool repeated = false,
}) => state.transfer(
  operation,
  operands,
  allocate: (site) => FlowObject(site, _activation),
  repeated: repeated,
  invoke: (_, _, _) => throw StateError('Unexpected call'),
  call: (_, _, _) => throw StateError('Unexpected closure'),
)!;
