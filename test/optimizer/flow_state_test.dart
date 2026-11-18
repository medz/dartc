import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart'
    show FlowRegion, FlowSource, FlowAddress;
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:flow-state');
final _activation = Object();
const _one = Constant.integer(1);
const _two = Constant.integer(2);

void main() {
  for (final raw in [false, true]) {
    test(
      'program-state invalidation preserves typed and raw global capabilities ($raw)',
      () {
        final box = ClassType(_uri, 'RawGlobalTarget');
        final field = InstanceField(box, 'value', .integer, isFinal: true);
        final global = GlobalVariable(
          _uri,
          'reference',
          raw ? .integer.nullable : box.nullable,
        );
        final program = IrProgram(
          [
            IrClass(box, [field]),
          ],
          [],
          globals: [global],
        );
        final create = NewPayload(box, const Constant.integer(0));
        final allocated = _step(FlowState(program), create);
        final initialized = _step(
          allocated.normal!,
          StoreField(field, create, _one),
          operands: [allocated.value, FlowValue.constant(_one)],
        );
        final object = allocated.value.objects.single;
        final stored = _step(
          initialized.normal!,
          StoreGlobal(global, raw ? const Constant.integer(0) : create),
          operands: [
            raw ? FlowValue.address(FlowAddress(object, 0)) : allocated.value,
          ],
        );
        final changed = stored.normal!.copy()..invalidate([], globals: true);
        expect(
          changed.storedValue(object, field).constant,
          raw ? isNull : _one,
        );
        expect(stored.normal!.storedValue(object, field).constant, _one);
      },
    );
  }

  test('projected alias dependencies do not claim an external observation', () {
    final box = ClassType(_uri, 'AliasDependency');
    final field = InstanceField(box, 'value', .integer);
    final global = GlobalVariable(_uri, 'alias', box.nullable);
    final program = IrProgram(
      [
        IrClass(box, [field]),
      ],
      [],
      globals: [global],
    );
    final create = NewPayload(box, const Constant.integer(0));
    final created = _step(FlowState(program), create);
    final initialized = _step(
      created.normal!,
      StoreField(field, create, _one),
      operands: [created.value, FlowValue.constant(_one)],
    );
    final stored = _step(
      initialized.normal!,
      StoreGlobal(global, create),
      operands: [created.value],
    );
    final external = FlowValue.unknown(box, external: true);
    final object = created.value.objects.single;
    final access = (
      fields: {field},
      globals: <GlobalVariable>{},
      data: <NativeData>{},
      modules: <ModuleObject>{},
      context: false,
      cells: false,
      memory: false,
      writes: true,
      exposed: false,
      rawWrites: false,
    );
    final projected = stored.normal!
        .project([external], access: access)
        .project([external], access: access);
    expect(projected.containsObject(object), isTrue);
    expect(projected.exposedValues.objects, isEmpty);
    expect(projected.escapedValues.objects, isEmpty);
    final write = _step(
      projected,
      StoreField(field, create, _two),
      operands: [external, FlowValue.constant(_two)],
    );
    expect(
      write.normal!.storedValue(object, field).integers!.contains(2),
      isTrue,
    );
    expect(write.normal!.exposedValues.objects, isEmpty);
  });

  test('external origins preserve actual escape and raw alias frontiers', () {
    final box = ClassType(_uri, 'ExternalBox');
    final field = InstanceField(box, 'value', .integer);
    final program = IrProgram([
      IrClass(box, [field]),
    ], []);
    final create = NewPayload(box, const Constant.integer(0));
    final created = _step(FlowState(program), create);
    final initialized = _step(
      created.normal!,
      StoreField(field, create, _one),
      operands: [created.value, FlowValue.constant(_one)],
    );
    final state = initialized.normal!;
    final external = FlowValue.unknown(box, external: true);
    final unrestricted = FlowValue.unknown(box);
    final object = created.value.objects.single;
    expect(state.reachableValues([external]).objects, isEmpty);
    final privateWrite = _step(
      state,
      StoreField(field, create, _two),
      operands: [external, FlowValue.constant(_two)],
    );
    expect(privateWrite.normal!.storedValue(object, field).constant, _one);
    // Untagged raw snapshots remain capable of naming an existing allocation.
    final raw = FlowValue.unknown(.integer).withReferences([unrestricted]);
    expect(state.exposedFrom([raw, external]).objects, contains(object));
    expect(state.exposedFrom([external, raw]).objects, contains(object));
    final exposed = state.copy()..escape([created.value]);
    expect(exposed.reachableValues([external]).objects, contains(object));
    final before = exposed.project([external]).copy(resetWrites: true);
    final write = _step(
      before,
      StoreField(field, create, _two),
      operands: [external, FlowValue.constant(_two)],
    );
    final applied = exposed.applySummary(
      before,
      write.normal!,
      mapObject: (object) => object,
      mapValue: (value) => value,
    );
    expect(applied.storedValue(object, field).integers!.contains(2), isTrue);
    expect(state.storedValue(object, field).constant, _one);
  });

  test('unknown alias traversal preserves typed and raw closure frontiers', () {
    final cell = NewCell(CellType(.integer), _one);
    final allocated = _step(FlowState(IrProgram([], [])), cell);
    final target = FunctionTarget(
      _uri,
      'capturing',
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
    final unknown = FlowValue.unknown(closure.type);
    final raw = FlowValue.unknown(.integer).withReferences([unknown]);
    final cellObject = allocated.value.objects.single;
    expect(
      state.exposedFrom([unknown]).objects,
      containsAll(captured.value.objects),
    );
    expect(state.exposedFrom([unknown]).objects, isNot(contains(cellObject)));
    for (final roots in [
      [raw, unknown, unknown],
      [unknown, unknown, raw],
    ]) {
      expect(state.exposedFrom(roots).objects, contains(cellObject));
    }

    // A later traversal sees objects added since an earlier query.
    final anotherCell = NewCell(CellType(.integer), _two);
    final another = _step(state, anotherCell);
    final anotherClosure = _step(
      another.normal!,
      MakeClosure(target, [anotherCell]),
      operands: [another.value],
    );
    final reachable = anotherClosure.normal!.exposedFrom([raw, unknown]);
    expect(
      reachable.objects,
      containsAll([
        cellObject,
        another.value.objects.single,
        ...captured.value.objects,
        ...anotherClosure.value.objects,
      ]),
    );
    expect(
      state.exposedFrom([raw]).objects,
      isNot(contains(another.value.objects.single)),
    );
  });

  test('unknown writes preserve possible late final cell initialization in summaries', () {
    final program = IrProgram([], []);
    for (final bound in [false, true]) {
      final cell = NewCell(
        CellType(.integer, isLate: true, isFinal: true),
        bound ? _one : null,
      );
      final created = _step(FlowState(program), cell);
      final caller = created.normal!;
      final input = caller.copy(resetWrites: true);
      final output = input.copy()..invalidate([created.value]);
      final applied = caller.applySummary(
        input,
        output,
        mapObject: (value) => value,
        mapValue: (value) => value,
      );
      final read = _step(applied, ReadCell(cell), operands: [created.value]);
      expect(read.normal, isNotNull);
      expect(read.value.isBottom, isFalse);
      if (bound) expect(read.value.constant?.structuralKey, _one.structuralKey);
      if (!bound) expect(read.exceptional, isNotNull);
    }
  });

  test('unknown writes preserve possible late final global initialization in summaries', () {
    final global = GlobalVariable(
      _uri,
      'lateFinal',
      .integer,
      isLate: true,
      isFinal: true,
    );
    final program = IrProgram([], [], globals: [global]);
    for (final bound in [false, true]) {
      var caller = FlowState(program);
      if (bound) caller = _step(caller, StoreGlobal(global, _one)).normal!;
      final input = caller.copy(resetWrites: true);
      final output = input.copy()..invalidate([], globals: true);
      final applied = caller.applySummary(
        input,
        output,
        mapObject: (value) => value,
        mapValue: (value) => value,
      );
      final read = _step(applied, LoadGlobal(global));
      expect(read.normal, isNotNull);
      expect(read.value.isBottom, isFalse);
      if (bound) expect(read.value.constant?.structuralKey, _one.structuralKey);
      if (!bound) expect(read.exceptional, isNotNull);
    }
  });

  for (final repeated in [false, true]) {
    test(
      'read equality applies only to one cell and expires on write ($repeated)',
      () {
        final initial = FlowState(IrProgram([], []));
        final cell = NewCell(CellType(.integer), _one);
        final allocated = _step(
          initial,
          cell,
          operands: [FlowValue.unknown(.integer)],
          repeated: repeated,
        );
        final read = ReadCell(cell);
        final source = FlowSource(read, _activation);
        final snapshot = allocated.normal!.copy();
        final state = allocated.normal!
          ..rememberRead(read, [allocated.value], source);
        expect(
          state.boundValueOf(read, [allocated.value])!.sources.contains(source),
          !repeated,
        );
        expect(
          snapshot.boundValueOf(read, [allocated.value])!.sources,
          isEmpty,
        );
        state.refineIntegers({source: FlowIntegerRange(0, 3)});
        expect(
          state.boundValueOf(read, [allocated.value])!.integers,
          repeated ? FlowIntegerRange.full : FlowIntegerRange(0, 3),
        );
        final written = _step(
          state,
          WriteCell(cell, const Constant.integer(-1)),
          operands: [
            allocated.value,
            FlowValue.constant(const Constant.integer(-1)),
          ],
        ).normal!;
        expect(written.boundValueOf(read, [allocated.value])!.sources, isEmpty);
        if (!repeated) {
          expect(
            written.boundValueOf(read, [allocated.value])!.integers,
            FlowIntegerRange(-1, -1),
          );
        }
        final other = _step(snapshot, NewCell(CellType(.integer), _two));
        final ambiguous = allocated.value.join(other.value);
        other.normal!.rememberRead(read, [ambiguous], source);
        expect(
          other.normal!.boundValueOf(read, [allocated.value])!.sources,
          isEmpty,
        );
      },
    );
  }

  test('rebinding forgets stored SSA equalities without changing snapshots or values', () {
    final parameter = Block([.integer]).parameters.single;
    final otherActivation = Object();
    final value = FlowValue.integerRange(FlowIntegerRange(3, 9))
        .withSource(parameter, _activation)
        .withSource(parameter, otherActivation);
    final forgotten = value.sources.singleWhere(
      (source) => identical(source.activation, _activation),
    );
    final expected = value.withSources(
      value.sources.where((source) => source != forgotten),
    );
    final box = ClassType(_uri, 'Stored');
    final field = InstanceField(box, 'value', ValueType.integer.nullable);
    final initializer = FunctionTarget(
      _uri,
      '',
      .voidType,
      [],
      owner: box,
      kind: .initializer,
    );
    final global = GlobalVariable(_uri, 'saved', ValueType.integer.nullable);
    final initial = FlowState(
      IrProgram(
        [
          IrClass(box, [field], constructors: [initializer]),
        ],
        [_body(initializer, const Return())],
        globals: [global],
      ),
    );
    final create = Construct(initializer, []);
    final object = _step(
      initial,
      create,
      invoke: (_, _, state) => _normal(const FlowValue.bottom(), state),
    );
    var stored = _step(
      object.normal!,
      StoreField(field, create, _one),
      operands: [object.value, value],
    ).normal!;
    final cell = NewCell(CellType(.integer), _one);
    final captured = _step(stored, cell, operands: [value]);
    stored = _step(
      captured.normal!,
      StoreGlobal(global, _one),
      operands: [value],
    ).normal!;
    final enclosing = FunctionTarget(_uri, 'scope', .voidType, []);
    final closureTarget = FunctionTarget(
      _uri,
      'capture',
      .integer,
      [],
      kind: .closure,
      enclosing: enclosing,
      sourceOffset: 1,
      captures: [.integer],
    );
    final closure = _step(
      stored,
      MakeClosure(closureTarget, [_one]),
      operands: [value],
    );
    stored = closure.normal!..escape([value]);
    final snapshot = stored.copy();
    stored.retainSources((source) => source != forgotten);
    List<FlowValue> values(FlowState state) => [
      _step(state, LoadGlobal(global)).value,
      _step(state, LoadField(field, create), operands: [object.value]).value,
      _step(state, ReadCell(cell), operands: [captured.value]).value,
      state.capturesOf(closure.value.objects.single)!.single,
      state.escapedValues,
    ];
    expect(values(snapshot), everyElement(value));
    expect(values(stored), everyElement(expected));
    final key = stored.structuralKey;
    stored.retainSources((source) => source != forgotten);
    expect(stored.structuralKey, key);
  });

  test('numeric storage joins preserve branch bounds and widen only expanding loop bounds', () {
    final global = GlobalVariable(_uri, 'number', ValueType.integer.nullable);
    final initial = FlowState(IrProgram([], [], globals: [global]));
    final cell = NewCell(CellType(.integer), const Constant.integer(0));
    final allocated = _step(initial, cell);
    final before = _step(
      allocated.normal!,
      StoreGlobal(global, const Constant.integer(0)),
    ).normal!;
    for (final delta in [-1, 1]) {
      final incoming = _step(
        before,
        WriteCell(cell, Constant.integer(delta)),
        operands: [
          allocated.value,
          FlowValue.constant(Constant.integer(delta)),
        ],
      ).normal!;
      final after = _step(
        incoming,
        StoreGlobal(global, Constant.integer(delta)),
      ).normal!;
      final union = before.copy()..join(after);
      final widened = before.copy()..join(after, widen: true);
      final expected = delta < 0
          ? FlowIntegerRange(FlowIntegerRange.minimum, 0)
          : FlowIntegerRange(0, FlowIntegerRange.maximum);
      for (final (read, operands) in [
        (ReadCell(cell), [allocated.value]),
        (LoadGlobal(global), <FlowValue>[]),
      ]) {
        expect(
          _step(union, read, operands: operands).value.integers,
          FlowIntegerRange(delta < 0 ? delta : 0, delta > 0 ? delta : 0),
        );
        expect(
          _step(widened, read, operands: operands).value.integers,
          expected,
        );
      }
      expect(widened.join(after, widen: true), isFalse);
    }
  });

  test('unknown storage reads keep the activated generic result type', () {
    final t = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final box = ClassType(_uri, 'Box', typeParameters: [t]);
    final field = InstanceField(box, 'value', t);
    final block = Block([box, CellType(t)]);
    final state = FlowState(
      IrProgram([
        IrClass(box, [field]),
      ], []),
    );
    for (final (read, receiver) in [
      (LoadField(field, block.parameters[0]), box.instantiate([.integer])),
      (ReadCell(block.parameters[1]), CellType(.integer)),
    ]) {
      expect(read.type, t);
      final result = _step(
        state,
        read,
        operands: [FlowValue.unknown(receiver)],
        resultType: .integer,
      );
      expect(result.value.unknownTypes, {ValueType.integer});
      expect(result.normal, isNotNull);
    }
  });

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
    expect(_step(state, read).exception.unknownTypes, {ValueType.error});
    final write = StoreGlobal(global, const Constant.nullValue());
    final bound = _step(state, write).normal!;
    expect(
      _step(bound, read).value.constant?.structuralKey,
      const Constant.nullValue().structuralKey,
    );
    final again = _step(bound, write);
    expect(again.normal, isNull);
    expect(again.exceptional, isNotNull);
    expect(again.exception.unknownTypes, {ValueType.error});
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

  test('incoming identity survives without facts about its contents', () {
    final type = ClassType(_uri, 'Opaque');
    final saved = GlobalVariable(_uri, 'saved', type, isLate: true);
    final source = NewPayload(type, const Constant.integer(0));
    final object = FlowObject(source, _activation);
    final state = _step(
      FlowState(IrProgram([IrClass(type, [])], [], globals: [saved])),
      StoreGlobal(saved, source),
      operands: [FlowValue.object(object)],
    ).normal!.project([]);
    expect(state.containsObject(object), isFalse);
    expect(state.allocationIdentities(const []), {object});
    final address = FlowObject(
      DirectCall(FunctionTarget(null, 'map', .integer, []), []),
      _activation,
    );
    expect(
      state.allocationIdentities([
        FlowValue.address(FlowAddress(FlowRegion(address), 0)),
      ]),
      {object, address},
    );
    expect(_step(state, LoadGlobal(saved)).value.objects, {object});
  });

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

  test('a read-only summary retains the current caller value and its new read equality', () {
    final cell = NewCell(CellType(.integer), _one);
    final allocated = _step(FlowState(IrProgram([], [])), cell);
    final receiver = allocated.value;
    final caller = allocated.normal!;
    final other = _step(
      caller,
      WriteCell(cell, _two),
      operands: [receiver, .constant(_two)],
    ).normal!;
    final summarized = (caller.copy()..join(other)).copy(resetWrites: true);
    final entry = summarized.copy();
    final read = ReadCell(cell);
    final source = FlowSource(read, _activation);
    summarized.rememberRead(read, [receiver], source);
    final result = caller.applySummary(
      entry,
      summarized,
      mapObject: (object) => object,
      mapValue: (value) => value,
    );
    final retained = result.boundValueOf(read, [receiver])!;
    expect(retained.constant?.structuralKey, _one.structuralKey);
    expect(retained.sources, contains(source));
    expect(caller.boundValueOf(read, [receiver])!.sources, isEmpty);
  });

  test('input renaming is bijective and preserves global and native-context capabilities', () {
    final box = ClassType(_uri, 'Anchor');
    final cell = NewPayload(box, const Constant.integer(0));
    final global = GlobalVariable(_uri, 'anchor', cell.type, isLate: true);
    final program = IrProgram([IrClass(box, [])], [], globals: [global]);
    final initial = _step(FlowState(program), cell);
    final object = initial.value.objects.single;
    final renamed = FlowObject(object.site, Object(), type: object.type);
    final private = initial.normal!.mapObjects({object: renamed});
    expect(private.containsObject(renamed), isTrue);
    expect(private.containsObject(object), isFalse);
    final second = _step(
      initial.normal!,
      NewPayload(box, const Constant.integer(0)),
    );
    expect(
      () => second.normal!.mapObjects({
        object: renamed,
        second.value.objects.single: renamed,
      }),
      throwsArgumentError,
    );
    final anchored = _step(
      initial.normal!,
      StoreGlobal(global, cell),
      operands: [initial.value],
    ).normal!;
    expect(() => anchored.mapObjects({object: renamed}), throwsArgumentError);
    final native = initial.normal!.copy(
      nativeContext: FlowValue.address(FlowAddress(object, 0)),
    );
    expect(() => native.mapObjects({object: renamed}), throwsArgumentError);
  });

  test('projection removes write owners outside the observable state', () {
    final before = FlowState(IrProgram([], []));
    final private = _step(before, NewCell(CellType(.integer), _one));
    final after = private.normal!.project([]);
    final mapped = <FlowObject>[];
    final applied = before.applySummary(
      before,
      after,
      mapObject: (object) {
        mapped.add(object);
        return object;
      },
      mapValue: (value) => value,
    );
    expect(mapped, isEmpty);
    expect(applied.containsObject(private.value.objects.single), isFalse);
  });

  test('summary writes survive equal joined entry and exit values', () {
    final global = GlobalVariable(_uri, 'swapped', .integer, isLate: true);
    final program = IrProgram([], [], globals: [global]);
    final cell = NewCell(CellType(.integer), _one);
    final allocated = _step(FlowState(program), cell);
    final receiver = allocated.value;
    FlowState assign(FlowState state, Constant value) => _step(
      _step(state, StoreGlobal(global, value)).normal!,
      WriteCell(cell, value),
      operands: [receiver, .constant(value)],
    ).normal!;
    final first = assign(allocated.normal!, _one).copy(resetWrites: true);
    final second = assign(first, _two).copy(resetWrites: true);
    final before = first.copy()..join(second);
    // These are the two executions of swapping 1 and 2, not a no-op transfer.
    final after = assign(first, _two)..join(assign(second, _one));
    expect(after.structuralKey, before.structuralKey);
    final applied = first.applySummary(
      before,
      after,
      mapObject: (object) => object,
      mapValue: (value) => value,
    );
    for (final (read, operands) in [
      (LoadGlobal(global), <FlowValue>[]),
      (ReadCell(cell), [receiver]),
    ]) {
      final value = _step(applied, read, operands: operands).value;
      expect(value.integers, FlowIntegerRange(1, 2));
      expect(value.constant, isNull);
    }
    // A containing summary must retain the write as well.
    final relayed = first.applySummary(
      first,
      applied,
      mapObject: (object) => object,
      mapValue: (value) => value,
    );
    expect(
      _step(relayed, LoadGlobal(global)).value.integers,
      FlowIntegerRange(1, 2),
    );
  });

  test('summary entry pairs preserve slots admitted by a later caller', () {
    final box = ClassType(_uri, 'Paired');
    final written = InstanceField(box, 'written', ValueType.integer.nullable);
    final private = InstanceField(box, 'private', ValueType.integer.nullable);
    final program = IrProgram([
      IrClass(box, [written, private]),
    ], []);
    final allocation = NewPayload(box, const Constant.integer(0));
    final created = _step(FlowState(program), allocation);
    final caller = _step(
      created.normal!,
      StoreField(private, allocation, _two),
      operands: [created.value, .constant(_two)],
    ).normal!;
    final before = caller
        .project(
          [created.value],
          access: (
            fields: {written},
            globals: {},
            cells: false,
            memory: false,
            writes: true,
            exposed: false,
            rawWrites: false,
            data: {},
            modules: {},
            context: false,
          ),
        )
        .copy(resetWrites: true);
    final after = _step(
      before,
      StoreField(written, allocation, _one),
      operands: [created.value, .constant(_one)],
    ).normal!;
    expect(
      () => caller.applySummary(
        caller.copy(resetWrites: true),
        after,
        mapObject: (object) => object,
        mapValue: (value) => value,
      ),
      throwsStateError,
    );
    final applied = caller.applySummary(
      before,
      after,
      mapObject: (object) => object,
      mapValue: (value) => value,
    );
    expect(
      _step(
        applied,
        LoadField(private, allocation),
        operands: [created.value],
      ).value.constant,
      _two,
    );
    expect(
      _step(
        applied,
        LoadField(written, allocation),
        operands: [created.value],
      ).value.constant,
      _one,
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
      final before = caller.project([a.value]).copy(resetWrites: true);
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
    final callback = FunctionTarget(_uri, 'constantCallback', .integer, []);
    final callable = FunctionConstant(callback);
    final constants = FlowValue.constant(
      SequenceConstant(CoreTypes.listOf(.object), [
        for (var i = -99; i <= 99; i++) Constant.string('$i'),
        SequenceConstant(CoreTypes.listOf(.function), [callable]),
      ]),
    );
    final cell = NewCell(CellType(.integer), _one);
    final allocated = _step(
      FlowState(IrProgram([], [_body(callback, const Return(_one))])),
      cell,
    );
    final address = FlowValue.unknown(.integer)
        .withReferences([allocated.value]);
    expect(address.types, [ValueType.integer]);
    final projected = allocated.normal!.project([address, constants]);
    for (final reachable in [
      projected.reachableValues([constants]),
      projected.exposedFrom([constants]),
    ]) {
      expect(
        reachable.constants.map((value) => value.structuralKey),
        contains(callable.structuralKey),
      );
    }
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

  test(
    'a successful write to outside storage publishes its callable value',
    () {
      final callback = FunctionTarget(_uri, 'privateCallback', .integer, []);
      final holder = ClassType(_uri, 'OutsideHolder');
      final field = InstanceField(
        holder,
        'callback',
        callback.signature,
        isLate: true,
        isFinal: true,
      );
      final program = IrProgram(
        [
          IrClass(holder, [field]),
        ],
        [_body(callback, const Return(_one))],
      );
      final receiver = Block([holder]).parameters.single;
      final value = FunctionConstant(callback);
      final state = FlowState(program);
      final written = _step(
        state,
        StoreField(field, receiver, value),
        operands: [.unknown(holder), .constant(value)],
      );
      expect(
        written.normal!.exposedValues.constants.map((c) => c.structuralKey),
        contains(value.structuralKey),
      );
      expect(written.exceptional!.exposedValues.isBottom, isTrue);
      expect(state.exposedValues.isBottom, isTrue);
    },
  );

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
  ValueType? resultType,
}) => state.transfer(
  instruction,
  operands ??
      instruction.inputs.map((v) => FlowValue.constant(v as Constant)).toList(),
  allocate: (site) => FlowObject(site, _activation),
  repeated: repeated,
  resultType: resultType,
  invoke:
      invoke ?? (_, _, _) => throw StateError('Unexpected initializer call'),
  call: call ?? (_, _, _) => throw StateError('Unexpected closure call'),
)!;

FlowResult _normal(FlowValue value, FlowState state) =>
    FlowResult(value: value, normal: state, exceptional: null);

IrFunction _body(FunctionTarget target, Terminator exit) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(exit)]);
