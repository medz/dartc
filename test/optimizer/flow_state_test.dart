import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:flow-state');
final _activation = Object();
const _one = Constant.integer(1);
const _two = Constant.integer(2);

void main() {
  test('a write before the first read replaces a lazy initializer', () {
    final type = FunctionType(.integer, []);
    final dead = FunctionTarget(_uri, 'dead', type, []);
    final target = FunctionTarget(_uri, 'answer', .integer, []);
    final value = FunctionConstant(target);
    final global = GlobalVariable(_uri, 'saved', type, initializer: dead);
    final entry = Block();
    final write = entry.emit(StoreGlobal(global, value));
    final read = entry.emit(LoadGlobal(global));
    entry.finish(Return(entry.emit(FunctionCall(read, []))));
    final main = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
    ]);
    final answer = IrFunction(target, [Block()..finish(const Return(_two))]);
    final program = IrProgram(
      [],
      [
        main,
        answer,
        _body(dead, Throw(const Constant.string('unreachable initializer'))),
      ],
      globals: [global],
    );
    final state = FlowState(program);
    final stored = _step(state, write);
    expect(stored.effects, {Effect.writesStorage});
    final after = stored.normal!;
    expect(_step(after, read).effects, {Effect.readsStorage});
    expect(
      _step(after, read).value.constant?.structuralKey,
      value.structuralKey,
    );
    expect(IrInterpreter(program, {}).run(main, []), 2);
    var calls = 0;
    _step(
      state,
      read,
      invoke: (target, args, input) {
        expect(target, same(dead));
        calls++;
        return _normal(.constant(value), input);
      },
    );
    expect(calls, 1, reason: 'the predecessor snapshot remains unbound');
  });

  test('bound null is distinct from an uninitialized late final slot', () {
    final global = GlobalVariable(
      _uri,
      'once',
      ValueType.object.nullable,
      isLate: true,
      isFinal: true,
    );
    final state = FlowState(IrProgram([], [], globals: [global]));
    final read = LoadGlobal(global);
    expect(_step(state, read).normal, isNull);
    final write = StoreGlobal(global, const Constant.nullValue());
    final bound = _step(state, write).normal!;
    expect(
      _step(bound, read).value.constant?.structuralKey,
      const Constant.nullValue().structuralKey,
    );
    final again = _step(bound, write);
    expect(again.normal, isNull);
    expect(again.exceptional, isNotNull);
    final merged = state.copy()..join(bound);
    final uncertain = _step(merged, read);
    expect(uncertain.normal, isNotNull);
    expect(uncertain.exceptional, isNotNull);
  });

  test(
    'recursive final initialization preserves the inner binding on failure',
    () {
      final initializer = FunctionTarget(_uri, 'initialize', .integer, []);
      final global = GlobalVariable(
        _uri,
        'recursive',
        .integer,
        isFinal: true,
        initializer: initializer,
      );
      final state = FlowState(
        IrProgram(
          [],
          [_body(initializer, const Return(_one))],
          globals: [global],
        ),
      );
      final read = LoadGlobal(global);
      final result = _step(
        state,
        read,
        invoke: (target, args, input) {
          final inner = _step(
            input,
            read,
            invoke: (_, _, nested) => _normal(.constant(_one), nested),
          );
          return _normal(.constant(_two), inner.normal!);
        },
      );
      expect(result.normal, isNull);
      expect(
        _step(result.exceptional!, read).value.constant?.structuralKey,
        _one.structuralKey,
      );
    },
  );

  test(
    'throwing initialization keeps completed writes and retries unbound slots',
    () {
      final initializer = FunctionTarget(_uri, 'throws', .integer, []);
      final global = GlobalVariable(
        _uri,
        'lazy',
        .integer,
        initializer: initializer,
      );
      final progress = GlobalVariable(
        _uri,
        'progress',
        ValueType.integer.nullable,
      );
      final state = FlowState(
        IrProgram(
          [],
          [_body(initializer, const Return(_one))],
          globals: [global, progress],
        ),
      );
      final failed = _step(
        state,
        LoadGlobal(global),
        invoke: (_, _, input) {
          final changed = _step(input, StoreGlobal(progress, _one)).normal!;
          return FlowResult(
            value: const .bottom(),
            normal: null,
            exceptional: changed,
            exception: FlowValue.constant(
              const Constant.string('initializer failure'),
            ),
          );
        },
      );
      expect(failed.normal, isNull);
      expect(
        failed.exception.constant?.structuralKey,
        const Constant.string('initializer failure').structuralKey,
      );
      expect(
        _step(
          failed.exceptional!,
          LoadGlobal(progress),
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
      final retry = _step(
        failed.exceptional!,
        LoadGlobal(global),
        invoke: (_, _, input) => _normal(.constant(_two), input),
      );
      expect(retry.value.constant?.structuralKey, _two.structuralKey);
      expect(
        _step(
          retry.normal!,
          LoadGlobal(progress),
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
    },
  );

  test(
    'aliases share writes while copied loop cells keep their own binding',
    () {
      final type = CellType(.integer);
      final create = NewCell(type, _one);
      final original = _step(FlowState(IrProgram([], [])), create);
      final copy = CopyCell(create);
      final copied = _step(original.normal!, copy, operands: [original.value]);
      final changed = _step(
        copied.normal!,
        WriteCell(create, _two),
        operands: [original.value, .constant(_two)],
      );
      expect(
        _step(
          changed.normal!,
          ReadCell(create),
          operands: [original.value],
        ).value.constant?.structuralKey,
        _two.structuralKey,
      );
      expect(
        _step(
          changed.normal!,
          ReadCell(copy),
          operands: [copied.value],
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
    },
  );

  test('alternative aliases update only one cell on each executable path', () {
    final targets = [
      for (final name in ['left', 'right', 'replacement'])
        FunctionTarget(_uri, name, .integer, []),
    ];
    final values = targets.map(FunctionConstant.new).toList();
    final type = CellType(values.first.type);
    final left = NewCell(type, values[0]);
    final right = NewCell(type, values[1]);
    final first = _step(FlowState(IrProgram([], [])), left);
    final second = _step(first.normal!, right);
    final changed = _step(
      second.normal!,
      WriteCell(left, values[2]),
      operands: [first.value.join(second.value), .constant(values[2])],
    );
    expect(
      _step(
        changed.normal!,
        ReadCell(left),
        operands: [first.value],
      ).value.constants.whereType<FunctionConstant>().map((f) => f.target),
      unorderedEquals([targets[0], targets[2]]),
    );
    expect(
      _step(
        changed.normal!,
        ReadCell(right),
        operands: [second.value],
      ).value.constants.whereType<FunctionConstant>().map((f) => f.target),
      unorderedEquals([targets[1], targets[2]]),
    );
  });

  test(
    'repeated allocations cannot erase earlier instances at the same site',
    () {
      final create = NewCell(CellType(.integer), _one);
      final initial = _step(
        FlowState(IrProgram([], [])),
        create,
        operands: null,
        repeated: true,
      );
      final changed = _step(
        initial.normal!,
        WriteCell(create, _two),
        operands: [initial.value, .constant(_two)],
      );
      final read = _step(
        changed.normal!,
        ReadCell(create),
        operands: [initial.value],
      );
      expect(read.value.constant, isNull);
      expect(read.value.unknownTypes, contains(ValueType.integer));
      final repeated = _step(initial.normal!, create);
      final again = _step(
        repeated.normal!,
        WriteCell(create, _two),
        operands: [repeated.value, .constant(_two)],
      );
      expect(
        _step(
          again.normal!,
          ReadCell(create),
          operands: [repeated.value],
        ).value.constant,
        isNull,
      );
    },
  );

  test(
    'callable escape preserves captures until their storage address is exposed',
    () {
      final cell = NewCell(CellType(.integer), _one);
      final allocated = _step(FlowState(IrProgram([], [])), cell);
      final target = FunctionTarget(
        _uri,
        'closure',
        .integer,
        [],
        kind: .closure,
        enclosing: FunctionTarget(_uri, 'enclosing', .voidType, []),
        sourceOffset: 0,
        captures: [cell.type],
      );
      final closure = MakeClosure(target, [cell]);
      final captured = _step(
        allocated.normal!,
        closure,
        operands: [allocated.value],
      );
      final state = captured.normal!;
      final escaped = state.escape([captured.value]);
      expect(escaped.objects, contains(allocated.value.objects.single));
      expect(state.capturesOf(captured.value.objects.single), [
        allocated.value,
      ]);
      expect(
        state.exposedValues.objects,
        isNot(contains(allocated.value.objects.single)),
      );
      state.invalidate([state.exposedValues]);
      expect(
        _step(
          state,
          ReadCell(cell),
          operands: [allocated.value],
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
      final pointer = FlowValue.unknown(.integer)
          .withReferences([captured.value]);
      state.escape([pointer]);
      expect(
        state.exposedValues.objects,
        contains(allocated.value.objects.single),
      );
      state.invalidate([state.exposedValues]);
      expect(
        _step(
          state,
          ReadCell(cell),
          operands: [allocated.value],
        ).value.constant,
        isNull,
      );
      final rewritten = _step(
        state,
        WriteCell(cell, _two),
        operands: [allocated.value, .constant(_two)],
      );
      expect(
        _step(
          rewritten.normal!,
          ReadCell(cell),
          operands: [allocated.value],
        ).value.constant?.structuralKey,
        _two.structuralKey,
      );
      expect(
        _step(
          allocated.normal!,
          ReadCell(cell),
          operands: [allocated.value],
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
    },
  );

  test(
    'generic field writes check the actual receiver type before changing state',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final box = ClassType(_uri, 'Box', typeParameters: [t]);
      final field = InstanceField(box, 'value', t);
      final constructor = FunctionTarget(
        _uri,
        '',
        .voidType,
        [],
        owner: box,
        kind: .initializer,
      );
      final create = Construct(
        constructor,
        [],
        instantiatedType: box.instantiate([.integer]),
      );
      final entry = Block(constructor.parameterTypes);
      entry.finish(const Return());
      final program = IrProgram(
        [
          IrClass(box, [field], constructors: [constructor]),
        ],
        [
          IrFunction(constructor, [entry]),
        ],
      );
      final allocated = _step(
        FlowState(program),
        create,
        invoke: (_, args, input) =>
            _normal(.constant(const Constant.nullValue()), input),
      );
      final view = TypeView(create, box.instantiate([ValueType.object]));
      final assigned = _step(
        allocated.normal!,
        StoreField(field, view, _one),
        operands: [allocated.value, .constant(_one)],
      );
      final rejected = _step(
        assigned.normal!,
        StoreField(field, view, const Constant.string('wrong')),
        operands: [allocated.value, .constant(const Constant.string('wrong'))],
      );
      expect(rejected.normal, isNull);
      expect(
        _step(
          rejected.exceptional!,
          LoadField(field, create),
          operands: [allocated.value],
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
    },
  );

  test(
    'weak fields admit clearing without claiming that collection must occur',
    () {
      final holder = ClassType(_uri, 'WeakHolder');
      final field = InstanceField(holder, 'target', ValueType.object.nullable);
      final constructor = FunctionTarget(
        _uri,
        '',
        .voidType,
        [],
        owner: holder,
        kind: .initializer,
      );
      final create = Construct(constructor, []);
      final program = IrProgram(
        [
          IrClass(
            holder,
            [field],
            constructors: [constructor],
            weakFields: [field],
          ),
        ],
        [_body(constructor, const Return())],
      );
      final allocated = _step(
        FlowState(program),
        create,
        invoke: (_, _, input) =>
            _normal(.constant(const Constant.nullValue()), input),
      );
      final written = _step(
        allocated.normal!,
        StoreField(field, create, _one),
        operands: [allocated.value, .constant(_one)],
      );
      expect(
        written.normal!.boundValueOf(LoadField(field, create), [
          allocated.value,
        ]),
        isNull,
      );
      final read = _step(
        written.normal!,
        LoadField(field, create),
        operands: [allocated.value],
      );
      expect(
        read.value.constants.map((c) => c.structuralKey),
        unorderedEquals([
          _one.structuralKey,
          const Constant.nullValue().structuralKey,
        ]),
      );
    },
  );

  test('unknown aliases retain lazy initialization commits on both exits', () {
    final holder = ClassType(_uri, 'LazyHolder');
    final initializer = FunctionTarget(
      _uri,
      'initialize',
      .integer,
      [],
      owner: holder,
      kind: .fieldInitializer,
    );
    final field = InstanceField(
      holder,
      'value',
      .integer,
      isLate: true,
      isFinal: true,
      initializer: initializer,
    );
    final constructor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [],
      owner: holder,
      kind: .initializer,
    );
    final progress = GlobalVariable(
      _uri,
      'progress',
      ValueType.integer.nullable,
    );
    final program = IrProgram(
      [
        IrClass(holder, [field], constructors: [constructor]),
      ],
      [
        _body(constructor, const Return()),
        _body(initializer, const Return(_one)),
      ],
      globals: [progress],
    );
    final create = Construct(constructor, []);
    final allocated = _step(
      FlowState(program),
      create,
      invoke: (_, _, input) =>
          _normal(.constant(const Constant.nullValue()), input),
    );
    final read = LoadField(field, create);
    final uncertain = _step(
      allocated.normal!,
      read,
      operands: [.unknown(holder)],
      invoke: (_, _, input) {
        final written = _step(input, StoreGlobal(progress, _one));
        return _normal(.constant(_one), written.normal!);
      },
    );
    final later = _step(
      uncertain.normal!,
      read,
      operands: [allocated.value],
      invoke: (_, _, input) =>
          FlowResult(value: const .bottom(), normal: null, exceptional: input),
    );
    expect(
      later.normal,
      isNotNull,
      reason: 'the first read may have initialized this same object',
    );
    expect(later.value.constant?.structuralKey, _one.structuralKey);
    expect(
      _step(
        uncertain.exceptional!,
        LoadGlobal(progress),
      ).value.constants.map((c) => c.structuralKey),
      contains(_one.structuralKey),
      reason: 'a failing final bind does not roll back initializer writes',
    );
  });

  test(
    'structural keys normalize restored globals and survive later mutation',
    () {
      final global = GlobalVariable(_uri, 'key', ValueType.integer.nullable);
      final initial = FlowState(IrProgram([], [], globals: [global]));
      final written = _step(initial, StoreGlobal(global, _one)).normal!;
      final restored = _step(
        written,
        StoreGlobal(global, const Constant.nullValue()),
      ).normal!;
      expect(restored, initial);
      expect(restored.hashCode, initial.hashCode);
      final snapshot = initial.structuralKey;
      final pristine = initial.copy();
      expect(initial.join(written), isTrue);
      expect(snapshot, pristine.structuralKey);
      expect(initial.structuralKey, isNot(snapshot));
      expect(initial.join(written), isFalse);
    },
  );

  test('projection keeps globals, escapes and transitive captures', () {
    final type = CellType(.integer);
    final enclosing = FunctionTarget(_uri, 'scope', .voidType, []);
    final closureTarget = FunctionTarget(
      _uri,
      'capture',
      .integer,
      [],
      kind: .closure,
      enclosing: enclosing,
      sourceOffset: 1,
      captures: [type],
    );
    final global = GlobalVariable(
      _uri,
      'callback',
      closureTarget.signature.nullable,
    );
    final capturedCell = NewCell(type, _one);
    final escapedCell = NewCell(type, _two);
    final hiddenCell = NewCell(type, const Constant.integer(99));
    final a = _step(
      FlowState(IrProgram([], [], globals: [global])),
      capturedCell,
    );
    final b = _step(a.normal!, escapedCell);
    final c = _step(b.normal!, hiddenCell);
    final closure = MakeClosure(closureTarget, [capturedCell]);
    final d = _step(c.normal!, closure, operands: [a.value]);
    final stored = _step(
      d.normal!,
      StoreGlobal(global, closure),
      operands: [d.value],
    ).normal!..escape([b.value]);
    final projected = stored.project([]);
    expect(projected.containsObject(a.value.objects.single), isTrue);
    expect(projected.containsObject(b.value.objects.single), isTrue);
    expect(projected.containsObject(c.value.objects.single), isFalse);
    expect(stored.containsObject(c.value.objects.single), isTrue);
    expect(
      _step(
        projected,
        ReadCell(capturedCell),
        operands: [a.value],
      ).value.constant?.structuralKey,
      _one.structuralKey,
    );
    expect(
      _step(
        projected,
        ReadCell(escapedCell),
        operands: [b.value],
      ).value.constant?.structuralKey,
      _two.structuralKey,
    );
    expect(
      _step(
        projected,
        ReadCell(hiddenCell),
        operands: [c.value],
      ).value.constant,
      isNull,
    );
    expect(
      _step(
        stored,
        ReadCell(hiddenCell),
        operands: [c.value],
      ).value.constant?.structuralKey,
      const Constant.integer(99).structuralKey,
    );
  });

  test(
    'summary deltas preserve private caller storage and rename fresh objects',
    () {
      final global = GlobalVariable(
        _uri,
        'progress',
        ValueType.integer.nullable,
      );
      final program = IrProgram([], [], globals: [global]);
      final sharedCell = NewCell(CellType(.integer), _one);
      final privateCell = NewCell(CellType(.integer), _two);
      final a = _step(FlowState(program), sharedCell);
      final b = _step(a.normal!, privateCell);
      final caller = b.normal!;
      final before = caller.project([a.value]);
      final written = _step(
        before,
        WriteCell(sharedCell, const Constant.integer(7)),
        operands: [a.value, .constant(const Constant.integer(7))],
      );
      final globalWrite = _step(written.normal!, StoreGlobal(global, _one));
      final freshCell = NewCell(CellType(.integer), const Constant.integer(9));
      final allocated = _step(globalWrite.normal!, freshCell);
      final after = allocated.normal!..escape([allocated.value]);
      final original = allocated.value.objects.single;
      final renamed = FlowObject(original.site, Object(), type: original.type);
      FlowObject mapObject(FlowObject value) =>
          value == original ? renamed : value;
      FlowValue mapValue(FlowValue value) => value.mapObjects(mapObject);
      final applied = caller.applySummary(
        before,
        after,
        mapObject: mapObject,
        mapValue: mapValue,
      );
      expect(
        _step(
          applied,
          ReadCell(sharedCell),
          operands: [a.value],
        ).value.constant?.structuralKey,
        const Constant.integer(7).structuralKey,
      );
      expect(
        _step(
          applied,
          ReadCell(privateCell),
          operands: [b.value],
        ).value.constant?.structuralKey,
        _two.structuralKey,
      );
      expect(
        _step(
          applied,
          ReadCell(freshCell),
          operands: [.object(renamed)],
        ).value.constant?.structuralKey,
        const Constant.integer(9).structuralKey,
      );
      expect(applied.escapedValues.objects, contains(renamed));
      expect(applied.escapedValues.objects, isNot(contains(original)));
      expect(
        _step(applied, LoadGlobal(global)).value.constant?.structuralKey,
        _one.structuralKey,
      );
      expect(
        _step(
          caller,
          ReadCell(sharedCell),
          operands: [a.value],
        ).value.constant?.structuralKey,
        _one.structuralKey,
      );
      expect(
        _step(caller, LoadGlobal(global)).value.constant?.structuralKey,
        const Constant.nullValue().structuralKey,
      );
    },
  );

  test('address provenance keeps referenced storage without changing address types', () {
    final cell = NewCell(CellType(.integer), _one);
    final allocated = _step(FlowState(IrProgram([], [])), cell);
    final address = FlowValue.unknown(.integer)
        .withReferences([allocated.value]);
    expect(address.types, [ValueType.integer]);
    final projected = allocated.normal!.project([address]);
    expect(
      _step(
        projected,
        ReadCell(cell),
        operands: [allocated.value],
      ).value.constant?.structuralKey,
      _one.structuralKey,
    );
    expect(
      projected.escape([address]).objects,
      contains(allocated.value.objects.single),
    );
    projected.invalidate([address]);
    expect(
      _step(
        projected,
        ReadCell(cell),
        operands: [allocated.value],
      ).value.constant,
      isNull,
    );
    expect(
      _step(
        allocated.normal!,
        ReadCell(cell),
        operands: [allocated.value],
      ).value.constant?.structuralKey,
      _one.structuralKey,
    );
  });

  test(
    'bound reads distinguish available values from lazy and opaque storage',
    () {
      final global = GlobalVariable(_uri, 'pending', .integer, isLate: true);
      final state = FlowState(IrProgram([], [], globals: [global]));
      final cell = NewCell(
        CellType(ValueType.object.nullable),
        const Constant.nullValue(),
      );
      final allocated = _step(state, cell);
      final read = ReadCell(cell);
      expect(
        allocated.normal!
            .boundValueOf(read, [allocated.value])!
            .constant
            ?.structuralKey,
        const Constant.nullValue().structuralKey,
      );
      expect(allocated.normal!.boundValueOf(LoadGlobal(global), []), isNull);
      expect(
        allocated.normal!.boundValueOf(read, [FlowValue.unknown(cell.type)]),
        isNull,
      );
      final bound = _step(allocated.normal!, StoreGlobal(global, _one)).normal!;
      expect(
        bound.boundValueOf(LoadGlobal(global), [])!.constant?.structuralKey,
        _one.structuralKey,
      );
      expect(() => bound.boundValueOf(read, []), throwsArgumentError);
    },
  );

  test('a boundary retains independently exposed values after their owner is overwritten', () {
    final type = ClassType(_uri, 'Reachable');
    final constructor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [],
      owner: type,
      kind: .initializer,
    );
    final oldObject = Construct(constructor, []),
        newObject = Construct(constructor, []);
    final program = IrProgram(
      [
        IrClass(type, [], constructors: [constructor]),
      ],
      [_body(constructor, const Return())],
    );
    FlowResult initialize(
      FunctionTarget _,
      List<FlowValue> _,
      FlowState state,
    ) => _normal(.constant(const Constant.nullValue()), state);
    final old = _step(FlowState(program), oldObject, invoke: initialize);
    final replacement = _step(old.normal!, newObject, invoke: initialize);
    final owner = NewCell(CellType(type), oldObject);
    final allocated = _step(replacement.normal!, owner, operands: [old.value]);
    final boundary = allocated.normal!..escape([allocated.value]);
    final changed = _step(
      boundary,
      WriteCell(owner, newObject),
      operands: [allocated.value, replacement.value],
    ).normal!;
    expect(changed.exposedValues.objects, contains(old.value.objects.single));
    expect(
      changed.exposedValues.objects,
      contains(replacement.value.objects.single),
    );
    final current = _step(
      changed,
      ReadCell(owner),
      operands: [allocated.value],
    ).value;
    expect(current.objects, [replacement.value.objects.single]);
  });

  test('storage snapshots reject a different semantic graph', () {
    expect(
      () => FlowState(IrProgram([], [])).join(FlowState(IrProgram([], []))),
      throwsArgumentError,
    );
  });
}

FlowResult _step(
  FlowState state,
  Instruction instruction, {
  List<FlowValue>? operands,
  bool repeated = false,
  FlowInvoke? invoke,
  FlowCall? call,
}) => state.transfer(
  instruction,
  operands ??
      instruction.inputs.map((v) => FlowValue.constant(v as Constant)).toList(),
  allocate: (site) => FlowObject(site, _activation),
  repeated: repeated,
  invoke:
      invoke ?? (_, _, _) => throw StateError('Unexpected initializer call'),
  call: call ?? (_, _, _) => throw StateError('Unexpected closure call'),
)!;

FlowResult _normal(FlowValue value, FlowState state) =>
    FlowResult(value: value, normal: state, exceptional: null);

IrFunction _body(FunctionTarget target, Terminator exit) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(exit)]);
