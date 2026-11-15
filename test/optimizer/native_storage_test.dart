import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final _type = ClassType(null, 'Bytes');
final _program = IrProgram([IrClass(_type, [])], []);
final _layout = _Layout();
final _activation = Object();
final _u8 = NativeScalarType(Uint8);
final _u32 = NativeScalarType(Uint32);
final _i64 = NativeScalarType(Int64);
const _placeholder = Constant.integer(0);

void main() {
  test(
    'field-write summaries invalidate aliased bytes without touching payload',
    () {
      final field = InstanceField(_type, 'value', .integer);
      final program = IrProgram([
        IrClass(_type, [field]),
      ], []);
      final allocation = NewPayload(_type, const Constant.integer(8));
      final created = _step(
        FlowState(program, memoryLayout: _layout),
        allocation,
      );
      final address = FlowValue.address(
        FlowAddress(created.value.objects.single, ObjectHeader.fieldsOffset),
      );
      final payload = FlowValue.address(
        FlowAddress(
          created.value.objects.single,
          _layout.objectLayout(_type).size,
        ),
      );
      final caller = _store(
        _store(created.normal!, address, _i64, _integer(2)),
        payload,
        _i64,
        _integer(11),
      );
      final before = caller.project(
        [created.value],
        access: (
          fields: {field},
          globals: {},
          cells: false,
          memory: false,
          writes: true,
        ),
      );
      final after = _step(
        before,
        StoreField(field, allocation, _placeholder),
        operands: [created.value, _integer(7)],
      ).normal!;
      final applied = caller.applySummary(
        before,
        after,
        mapObject: (object) => object,
        mapValue: (value) => value,
      );
      expect(_number(_load(applied, address, _i64)), isNot(2));
      expect(_number(_load(applied, payload, _i64)), 11);
      expect(
        _number(
          _step(
            applied,
            LoadField(field, allocation),
            operands: [created.value],
          ).value,
        ),
        7,
      );
    },
  );

  for (final changed in [false, true]) {
    test(
      'native readers separate memory from unrelated global writes ($changed)',
      () {
        final uri = Uri.parse('memory:native-read-dependencies');
        final global = GlobalVariable(uri, 'unrelated', .integer, isLate: true);
        final fail = FunctionTarget(uri, 'fail', .never, []);
        final reader = FunctionTarget(uri, 'read', .integer, [_type]);
        final reading = Block(reader.parameterTypes),
            done = Block(),
            invalid = Block();
        final offset = Constant.integer(_layout.objectLayout(_type).size);
        final address = reading.emit(
          IntBinary(
            .add,
            reading.emit(ReferenceAddress(reading.parameters.single)),
            offset,
          ),
        );
        final value = reading.emit(LoadNative(address, _i64));
        reading.finish(
          Branch(
            reading.emit(
              IntBinary(.lessThan, value, const Constant.integer(0)),
            ),
            Jump(invalid),
            Jump(done),
          ),
        );
        done.finish(Return(value));
        invalid.finish(Unreachable(invalid.emit(DirectCall(fail, []))));
        final root = FunctionTarget(uri, 'root', .integer, []);
        final entry = Block();
        final object = entry.emit(NewPayload(_type, const Constant.integer(8)));
        entry.emit(
          StoreObjectData(object, offset, _i64, const Constant.integer(7)),
        );
        final first = entry.emit(DirectCall(reader, [object]));
        entry.emit(StoreGlobal(global, const Constant.integer(9)));
        if (changed) {
          entry.emit(
            StoreObjectData(object, offset, _i64, const Constant.integer(9)),
          );
        }
        final second = entry.emit(DirectCall(reader, [object]));
        entry.finish(Return(entry.emit(IntBinary(.add, first, second))));
        final facts = ProgramFlow(
          IrProgram(
            [IrClass(_type, [])],
            [
              IrFunction(root, [entry]),
              IrFunction(reader, [reading, done, invalid]),
            ],
            globals: [global],
            externals: [
              IrExternal(
                fail,
                effects: const {},
                memory: const .unchanged(),
                capturesArguments: false,
              ),
            ],
          ),
          [(target: root, arguments: <FlowValue>[])],
          memoryLayout: _layout,
        ).facts;
        expect(_number(facts.returnedBy(root)), changed ? 16 : 14);
        expect(facts.activationsOf(reader), hasLength(changed ? 2 : 1));
        expect(facts.definitions, isNot(contains(fail)));
      },
    );
  }

  for (final (capacity, progress) in [(49, 1), (12, 1), (49, 0)]) {
    test(
      'loop writes preserve globals only with proven bounds ($capacity, $progress)',
      () {
        final saved = GlobalVariable(
          Uri.parse('memory:bounded-loop'),
          'saved',
          .integer,
          isLate: true,
        );
        final reserve = FunctionTarget(null, 'reserve', .integer, [.integer]);
        final target = FunctionTarget(null, 'fill', .integer, [.boolean]);
        final entry = Block(target.parameterTypes),
            header = Block([ValueType.integer, ValueType.integer]),
            choose = Block(),
            small = Block(),
            large = Block(),
            done = Block(),
            failed = Block()..finish(const Return(Constant.integer(-1)));
        entry.emit(StoreGlobal(saved, const Constant.integer(37)));
        final address = entry.emit(
          DirectCall(reserve, [Constant.integer(capacity)]),
        );
        entry.finish(
          Branch(
            entry.emit(Equals(address, const Constant.integer(0))),
            Jump(failed),
            Jump(header, const [Constant.integer(0), Constant.integer(0)]),
          ),
        );
        final index = header.parameters.first, count = header.parameters.last;
        header.finish(
          Branch(
            header.emit(
              IntBinary(.lessThan, index, const Constant.integer(12)),
            ),
            Jump(choose),
            Jump(done),
          ),
        );
        choose.finish(
          Branch(entry.parameters.single, Jump(small), Jump(large)),
        );
        for (final (block, size) in [(small, 1), (large, 4)]) {
          Value next = count;
          for (var byte = 0; byte < size; byte++) {
            block.emit(
              StoreNative(
                block.emit(IntBinary(.add, address, next)),
                _u8,
                const Constant.integer(65),
              ),
            );
            next = block.emit(IntBinary(.add, next, const Constant.integer(1)));
          }
          block.finish(
            Jump(header, [
              block.emit(IntBinary(.add, index, Constant.integer(progress))),
              next,
            ]),
          );
        }
        done.emit(
          StoreNative(
            done.emit(IntBinary(.add, address, count)),
            _u8,
            const Constant.integer(10),
          ),
        );
        final read = done.emit(LoadGlobal(saved));
        done.finish(Return(read));
        final facts = ProgramFlow(
          IrProgram(
            [],
            [
              IrFunction(target, [
                entry,
                header,
                choose,
                small,
                large,
                done,
                failed,
              ]),
            ],
            globals: [saved],
            externals: [
              IrExternal(
                reserve,
                effects: const {.writesStorage},
                memory: const .zeroed(0),
              ),
            ],
          ),
          [
            (target: target, arguments: [FlowValue.unknown(.boolean)]),
          ],
          memoryLayout: _layout,
        ).facts;
        if (progress == 0) {
          expect(facts.reachesBlock(done), isFalse);
          expect(_number(facts.returnedBy(target)), -1);
        } else if (capacity == 49) {
          expect(_number(facts.valueOf(read)), 37);
        } else {
          expect(facts.valueOf(read).constant, isNull);
        }
      },
    );
  }

  test('recursive initialization retains its changed entry state', () {
    final context = FunctionTarget(null, 'context', .integer, []);
    final initialize = FunctionTarget(null, 'initialize', .integer, []);
    final body = Block(), start = Block(), ready = Block();
    final address = body.emit(DirectCall(context, []));
    body.finish(
      Branch(
        body.emit(
          Equals(
            body.emit(LoadNative(address, _i64)),
            const Constant.integer(0),
          ),
        ),
        Jump(start),
        Jump(ready),
      ),
    );
    ready.finish(const Return(Constant.integer(7)));
    start.emit(StoreNative(address, _i64, const Constant.integer(1)));
    final nested = start.emit(DirectCall(initialize, []));
    start.emit(StoreNative(address, _i64, const Constant.integer(0)));
    start.finish(
      Return(start.emit(IntBinary(.add, nested, const Constant.integer(2)))),
    );
    final entry = FunctionTarget(null, 'entry', .integer, []);
    final root = Block();
    root.finish(Return(root.emit(DirectCall(initialize, []))));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(initialize, [body, start, ready]),
          IrFunction(entry, [root]),
        ],
        externals: [
          IrExternal(
            context,
            effects: const {.readsStorage},
            memory: const .unchanged(),
          ),
        ],
      ),
      [(target: entry, arguments: [])],
      initialMemory: {context: List.filled(8, 0)},
      memoryLayout: _layout,
    ).facts;
    expect(_number(facts.valueOf(nested)), 7);
    expect(_number(facts.returnedBy(entry)), 9);
  });

  test(
    'entry storage survives getter calls and carries ordinary call writes',
    () {
      final context = FunctionTarget(null, 'context', .integer, []);
      final read = FunctionTarget(null, 'read', .integer, []);
      final reader = Block();
      reader.finish(
        Return(
          reader.emit(LoadNative(reader.emit(DirectCall(context, [])), _i64)),
        ),
      );
      final update = FunctionTarget(null, 'update', .integer, []);
      final body = Block();
      final before = body.emit(DirectCall(read, []));
      body.emit(
        StoreNative(
          body.emit(DirectCall(context, [])),
          _i64,
          body.emit(IntBinary(.add, before, const Constant.integer(7))),
        ),
      );
      body.finish(Return(body.emit(DirectCall(read, []))));
      final program = IrProgram(
        [],
        [
          IrFunction(read, [reader]),
          IrFunction(update, [body]),
        ],
        externals: [
          IrExternal(
            context,
            effects: const {.readsStorage},
            memory: const .unchanged(),
          ),
        ],
      );
      final initial = List<int?>.filled(8, 0);
      final flow = ProgramFlow(
        program,
        [(target: update, arguments: [])],
        initialMemory: {context: initial},
        memoryLayout: _layout,
      );
      initial[0] = 99;
      expect(_number(flow.facts.valueOf(before)), 0);
      expect(_number(flow.facts.returnedBy(update)), 7);
      expect(
        _number(
          ProgramOptimizer([])
              .run(
                program,
                [(target: update, arguments: [])],
                initialMemory: {context: List.filled(8, 0)},
                memoryLayoutFor: (_) => _layout,
              )
              .returnedBy(update),
        ),
        7,
      );

      final persistent = ProgramFlow(
        program,
        [(target: update, arguments: [])],
        initialMemory: {context: List.filled(8, null)},
        memoryLayout: _layout,
      ).facts;
      expect(persistent.returnedBy(update).constant, isNull);
    },
  );

  test('unknown native writes invalidate exposed entry storage', () {
    final context = FunctionTarget(null, 'context', .integer, []);
    final mutate = FunctionTarget(null, 'mutate', .voidType, [.integer]);
    final target = FunctionTarget(null, 'entry', .integer, []);
    final body = Block();
    final address = body.emit(DirectCall(context, []));
    body.emit(DirectCall(mutate, [address]));
    body.finish(Return(body.emit(LoadNative(address, _i64))));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(target, [body]),
        ],
        externals: [
          IrExternal(
            context,
            effects: const {.readsStorage},
            memory: const .unchanged(),
          ),
          IrExternal(mutate, effects: const {.writesStorage}),
        ],
      ),
      [(target: target, arguments: [])],
      initialMemory: {context: List.filled(8, 0)},
      memoryLayout: _layout,
    ).facts;
    expect(facts.returnedBy(target).constant, isNull);
  });

  test('native mappings preserve private cells and caller byte contents', () {
    final factory = FunctionTarget(null, 'map', .integer, [.integer]);
    final primitive = FunctionTarget(null, 'reserve', .integer, [.integer]);
    final body = Block(factory.parameterTypes);
    body.finish(
      Return(body.emit(DirectCall(primitive, [const Constant.integer(16)]))),
    );
    final target = FunctionTarget(null, 'use', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final address = entry.emit(DirectCall(factory, entry.parameters));
    final success = Block(),
        failure = Block()..finish(const Return(Constant.integer(-1)));
    entry.finish(
      Branch(
        entry.emit(Equals(address, const Constant.integer(0))),
        Jump(failure),
        Jump(success),
      ),
    );
    final cell = success.emit(
      NewCell(CellType(.integer), const Constant.integer(41)),
    );
    success.emit(StoreNative(address, _u8, const Constant.integer(9)));
    final output = FunctionTarget(null, 'output', .voidType, [.integer]);
    final write = success.emit(DirectCall(output, [address]));
    final unknown = FunctionTarget(null, 'unknown', .voidType, []);
    success.emit(DirectCall(unknown, []));
    final byte = success.emit(LoadNative(address, _u8));
    final local = success.emit(ReadCell(cell));
    success.finish(Return(success.emit(IntBinary(.add, byte, local))));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(factory, [body]),
          IrFunction(target, [entry, success, failure]),
        ],
        externals: [
          IrExternal(
            primitive,
            effects: const {Effect.writesStorage},
            memory: const .zeroed(0),
          ),
          IrExternal(
            output,
            effects: const {Effect.writesStorage},
            memory: const .unchanged(),
            capturesArguments: false,
            terminates: true,
          ),
          IrExternal(unknown, effects: const {Effect.writesStorage}),
        ],
      ),
      [
        (target: target, arguments: [FlowValue.unknown(.integer)]),
      ],
      memoryLayout: _layout,
    ).facts;
    expect(_number(facts.valueOf(byte)), 9);
    expect(_number(facts.valueOf(local)), 41);
    expect(facts.valueOf(address).references.objects, isEmpty);
    expect(
      (
        facts.returnedBy(target).integers?.lower,
        facts.returnedBy(target).integers?.upper,
      ),
      (-1, 50),
    );
    expect(facts.exitsOf(local).exceptional, isFalse);
    expect(facts.canDiscard(write), isFalse);
  });

  test('native links keep their backing allocation through call summaries', () {
    final context = FunctionTarget(null, 'context', .integer, []);
    final reserve = FunctionTarget(null, 'reserve', .integer, [.integer]);
    final initialize = FunctionTarget(null, 'initialize', .boolean, []);
    final entry = Block(), success = Block(), failure = Block();
    final address = entry.emit(
      DirectCall(reserve, [const Constant.integer(16)]),
    );
    entry.finish(
      Branch(
        entry.emit(Equals(address, const Constant.integer(0))),
        Jump(failure),
        Jump(success),
      ),
    );
    failure.finish(Throw(const Constant.integer(-1)));
    success.emit(StoreNative(address, _u8, const Constant.integer(9)));
    success.emit(
      StoreNative(success.emit(DirectCall(context, [])), _i64, address),
    );
    success.finish(const Return(Constant.boolean(true)));
    final target = FunctionTarget(null, 'use', .integer, []);
    final root = Block(), read = Block(), failed = Block();
    root.finish(
      Branch(root.emit(DirectCall(initialize, [])), Jump(read), Jump(failed)),
    );
    failed.finish(const Return(Constant.integer(-1)));
    final stored = read.emit(
      LoadNative(read.emit(DirectCall(context, [])), _i64),
    );
    final byte = read.emit(LoadNative(stored, _u8));
    read.finish(Return(byte));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(initialize, [entry, success, failure]),
          IrFunction(target, [root, read, failed]),
        ],
        externals: [
          IrExternal(
            context,
            effects: const {.readsStorage},
            memory: const .unchanged(),
            capturesArguments: false,
          ),
          IrExternal(
            reserve,
            effects: const {.writesStorage},
            memory: const .zeroed(0),
            capturesArguments: false,
          ),
        ],
      ),
      [(target: target, arguments: [])],
      initialMemory: {context: List.filled(8, 0)},
      memoryLayout: _layout,
    ).facts;
    expect(_number(facts.valueOf(byte)), 9);
    expect(facts.valueOf(stored).references.objects, isEmpty);
  });

  for (final release in [false, true]) {
    test(
      'native range invalidation does not follow stored pointers ($release)',
      () {
        final first = _allocate(FlowState(_program, memoryLayout: _layout), 16);
        final second = _allocate(first.state, 8);
        final linked = _store(
          second.state,
          first.address,
          _i64,
          second.address,
        );
        final initialized = _store(linked, second.address, _u8, _integer(9));
        final next = initialized.overwriteNative(
          first.address,
          _integer(8),
          release: release,
        );
        expect(_number(_load(next, second.address, _u8)), 9);
        expect(_load(next, first.address, _i64).constant, isNull);
        expect(next.containsNative(first.address, _i64), !release);
        expect(initialized.containsNative(first.address, _i64), isTrue);
      },
    );
  }

  test(
    'a pure allocation view retains fresh state through its call summary',
    () {
      final adopt = FunctionTarget(null, 'adopt', _type, [.integer]);
      final body = Block(adopt.parameterTypes);
      final object = body.emit(
        AllocatedObject(
          body.parameters.single,
          _type,
          const Constant.integer(8),
        ),
      );
      body.finish(Return(object));
      final target = FunctionTarget(null, 'entry', .integer, [.integer]);
      final entry = Block(target.parameterTypes);
      final result = entry.emit(DirectCall(adopt, entry.parameters));
      final read = entry.emit(
        LoadObjectData(
          result,
          const Constant.integer(ObjectHeader.fieldsOffset),
          _i64,
        ),
      );
      entry.finish(Return(read));
      final facts = ProgramFlow(
        IrProgram(_program.classes, [
          IrFunction(adopt, [body]),
          IrFunction(target, [entry]),
        ]),
        [
          (target: target, arguments: [FlowValue.unknown(.integer)]),
        ],
        memoryLayout: _layout,
      ).facts;
      expect(_number(facts.returnedBy(target)), 0);
      expect(facts.effectsOf(object), isEmpty);
    },
  );

  test(
    'void calls retain fresh storage reachable only by a saved raw address',
    () {
      final saved = GlobalVariable(
        Uri.parse('memory:allocation-state'),
        'saved',
        .integer,
        isLate: true,
      );
      final adopt = FunctionTarget(null, 'adopt', .voidType, [.integer]);
      final body = Block(adopt.parameterTypes);
      final object = body.emit(
        AllocatedObject(
          body.parameters.single,
          _type,
          const Constant.integer(8),
        ),
      );
      body.emit(
        StoreObjectData(
          object,
          const Constant.integer(ObjectHeader.fieldsOffset),
          _i64,
          const Constant.integer(93),
        ),
      );
      body.finish(const Return());
      final target = FunctionTarget(null, 'entry', .integer, [.integer]);
      final entry = Block(target.parameterTypes);
      entry.emit(StoreGlobal(saved, entry.parameters.single));
      entry.emit(DirectCall(adopt, entry.parameters));
      final address = entry.emit(
        IntBinary(
          .add,
          entry.emit(LoadGlobal(saved)),
          const Constant.integer(ObjectHeader.fieldsOffset),
        ),
      );
      final read = entry.emit(LoadNative(address, _i64));
      entry.finish(Return(read));
      final facts = ProgramFlow(
        IrProgram(
          _program.classes,
          [
            IrFunction(adopt, [body]),
            IrFunction(target, [entry]),
          ],
          globals: [saved],
        ),
        [
          (target: target, arguments: [FlowValue.unknown(.integer)]),
        ],
        memoryLayout: _layout,
      ).facts;
      expect(_number(facts.returnedBy(target)), 93);
    },
  );

  test(
    'fresh allocation storage preserves headers and aliases its source address',
    () {
      final parameter = Block([.integer]).parameters.single;
      final raw = FlowValue.unknown(.integer)
          .withSource(parameter, _activation);
      final operation = AllocatedObject(
        parameter,
        _type,
        const Constant.integer(8),
      );
      final initial = FlowState(_program, memoryLayout: _layout);
      final created = _step(initial, operation, operands: [raw, _integer(8)]);
      expect(created.effects, isEmpty);
      expect(created.exceptional, isNull);
      final object = created.value.objects.single;
      final address = FlowValue.address(FlowAddress(object, 0));
      expect(_load(created.normal!, address, _i64).constant, isNull);
      expect(
        _number(
          _load(
            created.normal!,
            _offset(address, ObjectHeader.fieldsOffset),
            _i64,
          ),
        ),
        0,
      );
      expect(
        _number(
          _load(
            created.normal!,
            _offset(address, _layout.objectLayout(_type).size),
            _i64,
          ),
        ),
        0,
      );
      final written = _store(created.normal!, raw, _i64, _integer(73));
      expect(_number(_load(written, address, _i64)), 73);
      expect(written.containsNative(raw, _i64), isTrue);
      final joined = written.copy()..join(initial);
      expect(joined.containsNative(raw, _i64), isFalse);
      final rebound = written.copy()..retainSources((_) => false);
      expect(rebound.containsNative(raw, _i64), isFalse);
      expect(_number(_load(rebound, address, _i64)), 73);
      final projected = written.project([raw]);
      expect(projected.objects, contains(object));
      expect(_number(_load(projected, raw, _i64)), 73);
    },
  );

  test('allocation views and their original addresses agree through call summaries', () {
    final field = InstanceField(_type, 'value', .integer);
    final saved = GlobalVariable(
      Uri.parse('memory:allocation-state'),
      'saved',
      .integer,
      isLate: true,
    );
    final adopt = FunctionTarget(null, 'adopt', _type, [.integer]);
    final create = Block(adopt.parameterTypes);
    final allocated = create.emit(
      AllocatedObject(
        create.parameters.single,
        _type,
        const Constant.integer(8),
      ),
    );
    create.emit(StoreField(field, allocated, const Constant.integer(42)));
    create.emit(
      StoreObjectReference(
        allocated,
        const Constant.integer(ObjectHeader.typeOffset),
        TypeConstant(_type),
      ),
    );
    final initialized = create.emit(LoadField(field, allocated));
    create.finish(Return(allocated));
    final target = FunctionTarget(null, 'entry', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    entry.emit(StoreGlobal(saved, const Constant.integer(7)));
    final object = entry.emit(DirectCall(adopt, entry.parameters));
    final raw = entry.emit(
      IntBinary(
        .add,
        entry.parameters.single,
        const Constant.integer(ObjectHeader.fieldsOffset),
      ),
    );
    entry.emit(StoreNative(raw, _i64, const Constant.integer(93)));
    final repeatedView = entry.emit(
      AllocatedObject(
        entry.parameters.single,
        _type,
        const Constant.integer(8),
      ),
    );
    final read = entry.emit(
      LoadObjectData(
        repeatedView,
        const Constant.integer(ObjectHeader.fieldsOffset),
        _i64,
      ),
    );
    final stale = entry.emit(LoadField(field, object));
    entry.finish(
      Return(entry.emit(IntBinary(.add, read, entry.emit(LoadGlobal(saved))))),
    );
    final graph = IrProgram(
      [
        IrClass(_type, [field]),
      ],
      [
        IrFunction(target, [entry]),
        IrFunction(adopt, [create]),
      ],
      globals: [saved],
    );
    final facts = ProgramFlow(graph, [
      (target: target, arguments: [FlowValue.unknown(.integer)]),
    ], memoryLayout: _layout).facts;
    expect(_number(facts.returnedBy(target)), 100);
    expect(_number(facts.valueOf(initialized)), 42);
    expect(facts.valueOf(stale).constant, isNull);
    expect(facts.valueOf(object).objects, facts.valueOf(repeatedView).objects);
    expect(facts.effectsOf(allocated), isEmpty);
    expect(facts.exitsOf(allocated).exceptional, isFalse);
  });

  test(
    'descriptor reads use emitted words without inventing relocated addresses',
    () {
      final state = FlowState(_program, memoryLayout: _layout);
      final address = _step(state, ObjectDescriptorAddress(_type)).value;
      expect(address.references.isBottom, isTrue);
      expect(state.nativeReferences(address).isBottom, isTrue);
      final words = _layout.objectLayout(_type).descriptorWords;
      for (final (index, word) in words.indexed) {
        expect(_number(_load(state, _offset(address, index * 8), _i64)), word);
      }
      expect(
        _load(state, _offset(address, words.length * 8), _i64).constant,
        isNull,
      );
      expect(_load(state, _offset(address, -1), _u8).constant, isNull);
      expect(_load(FlowState(_program), address, _i64).constant, isNull);
    },
  );

  test(
    'fixed bytes and declared fields never keep stale facts across writes',
    () {
      final field = InstanceField(_type, 'value', ValueType.integer);
      final graph = IrProgram([
        IrClass(_type, [field]),
      ], []);
      final allocate = NewPayload(_type, const Constant.integer(8));
      final created = _step(FlowState(graph, memoryLayout: _layout), allocate);
      final object = created.value;
      final fixed = FlowValue.address(
        FlowAddress(object.objects.single, ObjectHeader.fieldsOffset),
      );
      final payload = _offset(
        fixed,
        _layout.objectLayout(_type).size - ObjectHeader.fieldsOffset,
      );
      expect(_number(_load(created.normal!, fixed, _i64)), 0);
      expect(created.normal!.containsNative(fixed, _i64), isTrue);
      final mixed = fixed.join(object);
      expect(created.normal!.containsNative(mixed, _i64), isFalse);
      expect(created.normal!.nativeReferences(mixed).unknownTypes, isNotEmpty);
      expect(_load(created.normal!, mixed, _i64).constant, isNull);
      expect(created.normal!.containsNative(_offset(fixed, -1), _i64), isFalse);
      expect(
        created.normal!.containsNative(_offset(payload, 1), _i64),
        isFalse,
      );
      expect(
        created.normal!.containsNative(fixed.join(.unknown(.integer)), _i64),
        isFalse,
      );
      final assigned = _step(
        created.normal!,
        StoreField(field, allocate, _placeholder),
        operands: [object, _integer(42)],
      ).normal!;
      final filled = _store(assigned, payload, _i64, _integer(99));
      FlowValue readField(FlowState state) =>
          _step(state, LoadField(field, allocate), operands: [object]).value;
      expect(_number(readField(filled)), 42);
      expect(_load(filled, fixed, _i64).constant, isNull);
      final changed = _store(filled, fixed, _i64, _integer(7));
      expect(_number(_load(changed, fixed, _i64)), 7);
      expect(_number(_load(changed, payload, _i64)), 99);
      expect(readField(changed).constant, isNull);
      final uncertain = _step(
        changed,
        StoreField(field, allocate, _placeholder),
        operands: [FlowValue.unknown(_type), _integer(9)],
      ).normal!;
      expect(_load(uncertain, fixed, _i64).constant, isNull);
      expect(_number(_load(uncertain, payload, _i64)), 99);
    },
  );

  test(
    'string constants expose their length and UTF-16 bytes but no header',
    () {
      const literal = Constant.string('A\u{1f642}\ud800');
      final state = FlowState(_program, memoryLayout: _layout);
      final start = _layout.objectLayout(ValueType.string).size;
      final address = FlowValue.address(FlowAddress(literal, start));
      expect(state.containsNative(address, _i64), isTrue);
      expect(FlowState(_program).containsNative(address, _i64), isFalse);
      expect(
        _number(
          _load(
            state,
            _offset(address, ObjectHeader.fieldsOffset - start),
            _i64,
          ),
        ),
        4,
      );
      expect(_number(_step(state, StringLength(literal)).value), 4);
      for (final (index, unit) in [65, 0xd83d, 0xde42, 0xd800].indexed) {
        expect(
          _number(
            _load(state, _offset(address, index * 2), NativeScalarType(Uint16)),
          ),
          unit,
        );
        expect(
          _number(_load(state, _offset(address, index * 2), _u8)),
          unit & 0xff,
        );
      }
      for (final offset in [ObjectHeader.fieldsOffset - start - 1, -1, 7, 8]) {
        expect(
          _load(
            state,
            _offset(address, offset),
            NativeScalarType(Uint16),
          ).constant,
          isNull,
        );
      }
      expect(_load(FlowState(_program), address, _u8).constant, isNull);
    },
  );

  test('raw fixed writes invalidate late binding checks as well as values', () {
    final field = InstanceField(
      _type,
      'lateValue',
      .integer,
      isLate: true,
      isFinal: true,
    );
    final program = IrProgram([
      IrClass(_type, [field]),
    ], []);
    final allocation = NewPayload(_type, const Constant.integer(0));
    final created = _step(
      FlowState(program, memoryLayout: _layout),
      allocation,
    );
    final assigned = _step(
      created.normal!,
      StoreField(field, allocation, _placeholder),
      operands: [created.value, _integer(5)],
    ).normal!;
    final fixed = FlowValue.address(
      FlowAddress(created.value.objects.single, ObjectHeader.fieldsOffset),
    );
    final changed = _store(assigned, fixed, _i64, _integer(0));
    final read = _step(
      changed,
      LoadField(field, allocation),
      operands: [created.value],
    );
    expect(read.exceptional, isNotNull);
    expect(read.value.constant, isNull);
    final write = _step(
      changed,
      StoreField(field, allocation, _placeholder),
      operands: [created.value, _integer(6)],
    );
    expect(write.normal, isNotNull);
    expect(write.exceptional, isNotNull);
  });

  test(
    'string length follows its initialized field, not allocation capacity',
    () {
      final operation = NewPayload(
        ValueType.string,
        const Constant.integer(20),
      );
      final created = _step(
        FlowState(_program, memoryLayout: _layout),
        operation,
      );
      final address = FlowValue.address(
        FlowAddress(created.value.objects.single, ObjectHeader.fieldsOffset),
      );
      final initialized = _store(created.normal!, address, _i64, _integer(3));
      expect(
        _number(
          _step(
            initialized,
            StringLength(operation),
            operands: [created.value],
          ).value,
        ),
        3,
      );
      final overwritten = _store(
        initialized,
        address,
        _i64,
        FlowValue.unknown(.integer),
      );
      expect(
        _step(
          overwritten,
          StringLength(operation),
          operands: [created.value],
        ).value.constant,
        isNull,
      );
    },
  );

  test('rebound SSA definitions do not alias earlier payload contents', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final value = FlowValue.integerRange(FlowIntegerRange(3, 9))
        .withSource(Block([.integer]).parameters.single, _activation);
    final before = _store(allocation.state, allocation.address, _i64, value);
    final after = before.copy()..retainSources((_) => false);
    expect(_load(before, allocation.address, _i64), value);
    expect(_load(after, allocation.address, _i64), value.withSources(const []));
  });

  test('native integer fragments widen as one stored value at loop joins', () {
    final allocation = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final before = _store(
      allocation.state,
      allocation.address,
      _i64,
      FlowValue.integerRange(FlowIntegerRange(3, 5)),
    );
    final after = _store(
      before,
      allocation.address,
      _i64,
      FlowValue.integerRange(FlowIntegerRange(3, 9)),
    );
    final union = before.copy()..join(after);
    final widened = before.copy()..join(after, widen: true);
    expect(
      _load(union, allocation.address, _i64).integers,
      FlowIntegerRange(3, 9),
    );
    expect(
      _load(widened, allocation.address, _i64).integers,
      FlowIntegerRange(3, FlowIntegerRange.maximum),
    );
    expect(widened.join(after, widen: true), isFalse);
  });

  test('zeroed fields and payload exclude the header and require an explicit target', () {
    final allocation = _allocate(
      FlowState(_program, memoryLayout: _layout),
      16,
    );
    final start = _layout.objectLayout(_type).size;
    expect(
      _load(allocation.state, allocation.address, _i64).constant,
      isA<ScalarConstant>().having((c) => c.value, 'value', 0),
    );
    for (final offset in [
      0,
      ObjectHeader.fieldsOffset - 1,
      start + 12,
      start + 16,
    ]) {
      final address = FlowValue.address(
        FlowAddress(allocation.object.objects.single, offset),
      );
      expect(_load(allocation.state, address, _i64).constant, isNull);
    }
    final unknown = _allocate(FlowState(_program), 16);
    expect(_load(unknown.state, unknown.address, _u8).constant, isNull);
    expect(
      () => allocation.state.join(FlowState(_program, memoryLayout: _Layout())),
      throwsArgumentError,
    );
  });

  test(
    'bounded reads inspect sparse interior changes without enumerating memory',
    () {
      const length = 1 << 30;
      final a = _allocate(FlowState(_program, memoryLayout: _layout), length);
      final start = a.address.addresses.single.offset!;
      final offsets = FlowValue.integerRange(
        FlowIntegerRange(start, start + length - 8),
      );
      final load = LoadObjectData(
        ObjectConstant(_type, {}),
        _placeholder,
        _i64,
      );
      expect(
        _number(_step(a.state, load, operands: [a.object, offsets]).value),
        0,
      );
      final middle = _store(
        a.state,
        _offset(a.address, length ~/ 2),
        _u8,
        _integer(1),
      );
      final changed = _step(middle, load, operands: [a.object, offsets]).value;
      expect(changed.constant, isNull);
      expect(changed.integers!.contains(1), isTrue);
      expect(changed.integers!.contains(1 << 56), isTrue);
      expect(
        _number(_step(a.state, load, operands: [a.object, offsets]).value),
        0,
      );
    },
  );

  test('bounded reads agree with every concrete byte window', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 12);
    final start = a.address.addresses.single.offset!;
    final bytes = [0, 0, 7, 7, 7, 0, 2, 9, 0, 0, 0, 0];
    var state = a.state;
    for (final (index, byte) in bytes.indexed) {
      state = _store(state, _offset(a.address, index), _u8, _integer(byte));
    }
    final load = LoadObjectData(ObjectConstant(_type, {}), _placeholder, _u32);
    for (var lower = 0; lower <= bytes.length - 4; lower++) {
      for (var upper = lower; upper <= bytes.length - 4; upper++) {
        final result = _step(
          state,
          load,
          operands: [
            a.object,
            FlowValue.integerRange(
              FlowIntegerRange(start + lower, start + upper),
            ),
          ],
        ).value;
        final actual = [
          for (var offset = lower; offset <= upper; offset++)
            bytes[offset] |
                bytes[offset + 1] << 8 |
                bytes[offset + 2] << 16 |
                bytes[offset + 3] << 24,
        ]..sort();
        for (final value in actual) {
          expect(
            result.integers!.contains(value),
            isTrue,
            reason: 'byte starts $lower..$upper lost $value',
          );
        }
        expect(result.integers!.lower, actual.first);
        expect(result.integers!.upper, actual.last);
      }
    }
  });

  test(
    'aligned byte reads include unknown regions between unaligned boundaries',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 24);
      final start = a.address.addresses.single.offset!;
      final changed = _step(
        a.state,
        StoreObjectData(
          ObjectConstant(_type, {}),
          _placeholder,
          _u32,
          _placeholder,
        ),
        operands: [a.object, _integer(start + 5), FlowValue.unknown(.integer)],
      ).normal!;
      final value = _step(
        changed,
        LoadObjectData(ObjectConstant(_type, {}), _placeholder, _u8),
        operands: [
          a.object,
          FlowValue.integerRange(
            FlowIntegerRange(start, start + 16, strideBits: 3),
          ),
        ],
      ).value;
      expect(value.constant, isNull);
      expect(value.integers!.contains(255), isTrue);
    },
  );

  test(
    'bounded writes preserve outside bytes, other allocations and snapshots',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final b = _allocate(a.state, 8);
      final start = a.address.addresses.single.offset!;
      final store = StoreObjectData(
        ObjectConstant(_type, {}),
        _placeholder,
        _u32,
        _placeholder,
      );
      final written = _step(
        b.state,
        store,
        operands: [
          a.object,
          FlowValue.integerRange(FlowIntegerRange(start + 4, start + 7)),
          _integer(42),
        ],
      ).normal!;
      for (var index = 0; index < 16; index++) {
        expect(
          _number(_load(written, _offset(a.address, index), _u8)),
          4 <= index && index < 11 ? isNull : 0,
          reason: 'byte $index',
        );
        expect(_number(_load(b.state, _offset(a.address, index), _u8)), 0);
      }
      expect(_number(_load(written, b.address, _i64)), 0);
      for (final offsets in [
        FlowIntegerRange(
          ObjectHeader.fieldsOffset - 1,
          ObjectHeader.fieldsOffset + 1,
        ),
        FlowIntegerRange(start + 12, start + 13),
      ]) {
        final escaped = _step(
          b.state,
          store,
          operands: [a.object, FlowValue.integerRange(offsets), _integer(42)],
        ).normal!;
        expect(_load(escaped, b.address, _i64).constant, isNull);
      }
    },
  );

  test('native aliases observe truncated, signed and overlapping writes', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final first = _store(a.state, a.address, _u32, _integer(0x12345678));
    final byte = _offset(a.address, 1);
    expect(_number(_load(first, byte, NativeScalarType(Uint16))), 0x3456);
    final second = _store(first, byte, _u8, _integer(0x1ff));
    expect(_number(_load(second, a.address, _u32)), 0x1234ff78);
    expect(_number(_load(second, byte, NativeScalarType(Int8))), -1);
    expect(_number(_load(a.state, a.address, _u32)), 0);
    expect(_number(_load(first, a.address, _u32)), 0x12345678);
  });

  test(
    'native precision, negative zero and boolean storage match their types',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final f32 = NativeScalarType(Float), f64 = NativeScalarType(Double);
      final rounded = _store(
        a.state,
        a.address,
        f32,
        .constant(const Constant.floating(16777217.0)),
      );
      expect(_number(_load(rounded, a.address, f32)), 16777216.0);
      final signed = _store(
        rounded,
        a.address,
        f64,
        .constant(const Constant.floating(-0.0)),
      );
      expect(
        1 / (_number(_load(signed, a.address, f64)) as double),
        double.negativeInfinity,
      );
      final boolean = _store(signed, a.address, _u8, _integer(128));
      expect(
        _load(
          boolean,
          a.address,
          NativeScalarType(Bool),
        ).constant?.structuralKey,
        const Constant.boolean(true).structuralKey,
      );
    },
  );

  test(
    'joins retain untouched bytes and weaken ambiguous or repeated writes',
    () {
      final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
      final b = _allocate(a.state, 16);
      final left = _store(b.state, a.address, _u8, _integer(1));
      final right = _store(b.state, a.address, _u8, _integer(2));
      final joined = left.copy()..join(right);
      expect(_load(joined, a.address, _u8).constant, isNull);
      expect(_number(_load(joined, _offset(a.address, 1), _u8)), 0);
      final uncertain = _store(
        b.state,
        a.address.join(b.address),
        _u8,
        _integer(9),
      );
      expect(_load(uncertain, a.address, _u8).constant, isNull);
      expect(_load(uncertain, b.address, _u8).constant, isNull);

      final operation = NewPayload(_type, const Constant.integer(16));
      final result = _step(b.state, operation, repeated: true);
      final address = FlowValue.address(
        FlowAddress(
          result.value.objects.single,
          _layout.objectLayout(_type).size,
        ),
      );
      final repeated = _store(result.normal!, address, _u8, _integer(3));
      expect(_load(repeated, address, _u8).constant, isNull);
    },
  );

  test('external writes invalidate exposed storage, unbounded addresses do not guess bounds', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final b = _allocate(a.state, 8);
    final external = b.state.copy()..invalidate([a.address]);
    expect(_load(external, a.address, _i64).constant, isNull);
    expect(_number(_load(external, b.address, _i64)), 0);
    final unbounded = FlowValue.address(
      FlowAddress(a.object.objects.single, null),
    );
    final unknown = _store(b.state, unbounded, _u8, _integer(7));
    expect(_load(unknown, a.address, _u8).constant, isNull);
    expect(_load(unknown, b.address, _u8).constant, isNull);
    expect(_load(b.state, unbounded, _u8).constant, isNull);
  });

  test('unknown copy sources invalidate only the destination range', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final copied = _step(
      a.state,
      CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, 4)),
      operands: [_offset(a.address, 4), .unknown(.integer)],
    ).normal!;
    expect(_number(_load(copied, a.address, _u32)), 0);
    expect(_load(copied, _offset(a.address, 4), _u32).constant, isNull);
    expect(_number(_load(copied, _offset(a.address, 8), _i64)), 0);
    final empty = _step(
      a.state,
      CopyNative(
        _placeholder,
        _placeholder,
        NativeArrayType(_u8, 0, variableLength: true),
      ),
      operands: [.unknown(.integer), .unknown(.integer)],
    );
    expect(empty.effects, isEmpty);
    expect(empty.normal, a.state);
  });

  test('native copies use the source snapshot across overlapping ranges', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final first = _store(
      a.state,
      a.address,
      _i64,
      _integer(0x0807060504030201),
    );
    final copied = _step(
      first,
      CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, 8)),
      operands: [_offset(a.address, 2), a.address],
    ).normal!;
    expect(
      _number(_load(copied, _offset(a.address, 2), _i64)),
      0x0807060504030201,
    );
    expect(_number(_load(copied, a.address, _u32)), 0x02010201);
  });

  test(
    'large zeroed allocations and copies do not enumerate their byte range',
    () {
      const size = 1 << 30;
      final a = _allocate(FlowState(_program, memoryLayout: _layout), size);
      final b = _allocate(a.state, size);
      final source = _store(
        b.state,
        _offset(a.address, size - 1),
        _u8,
        _integer(42),
      );
      final copied = _step(
        source,
        CopyNative(_placeholder, _placeholder, NativeArrayType(_u8, size)),
        operands: [b.address, a.address],
      ).normal!;
      expect(_number(_load(copied, _offset(b.address, size - 1), _u8)), 42);
      expect(_number(_load(copied, _offset(b.address, size - 8), _u32)), 0);
    },
  );

  test('stored addresses retain allocation identities through projection and summaries', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 16);
    final b = _allocate(a.state, 8);
    final input = b.state.project([a.address, b.address]);
    expect(input.nativeReferences(a.address).isBottom, isTrue);
    final output = _store(input, a.address, _i64, b.address);
    expect(output.nativeReferences(a.address).objects, {
      b.object.objects.single,
    });
    expect(
      output.nativeReferences(a.address).objects,
      isNot(contains(a.object.objects.single)),
    );
    expect(
      output.nativeReferences(.unknown(.integer)).unknownTypes,
      isNotEmpty,
    );
    final mapped = FlowObject(b.object.objects.single.site, Object());
    FlowObject object(FlowObject value) =>
        value == b.object.objects.single ? mapped : value;
    FlowValue value(FlowValue source) => source.mapObjects(object);
    final applied = b.state.applySummary(
      input,
      output,
      mapObject: object,
      mapValue: value,
    );
    final address = _load(applied, a.address, _i64).addresses.single;
    expect(address.base, mapped);
    expect(address.offset, b.address.addresses.single.offset);
    expect(applied.reachableValues([a.object]).objects, contains(mapped));
    expect(applied.nativeReferences(a.address).objects, {mapped});
    expect(_number(_load(b.state, a.address, _i64)), 0);
  });

  test('partial writes destroy a stored address without losing its reachable owner', () {
    final a = _allocate(FlowState(_program, memoryLayout: _layout), 8);
    final b = _allocate(a.state, 8);
    final stored = _store(b.state, a.address, _i64, b.address);
    final overwritten = _store(stored, _offset(a.address, 3), _u8, _integer(0));
    final value = _load(overwritten, a.address, _i64);
    expect(value.addresses, isEmpty);
    expect(value.references.objects, contains(b.object.objects.single));
    final exposed = stored.copy()..invalidate([a.address]);
    expect(_load(exposed, a.address, _i64).addresses, isEmpty);
    expect(
      exposed.reachableValues([a.object]).objects,
      contains(b.object.objects.single),
    );
  });
}

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.linux, .x64));

  @override
  ObjectLayout objectLayout(ClassType type) =>
      ObjectLayout([.word, .reference]);
}

({FlowState state, FlowValue object, FlowValue address}) _allocate(
  FlowState state,
  int bytes,
) {
  final result = _step(state, NewPayload(_type, Constant.integer(bytes)));
  return (
    state: result.normal!,
    object: result.value,
    address: FlowValue.address(
      FlowAddress(
        result.value.objects.single,
        _layout.objectLayout(_type).size,
      ),
    ),
  );
}

FlowValue _offset(FlowValue value, int amount) {
  final address = value.addresses.single;
  return FlowValue.address(FlowAddress(address.base, address.offset! + amount));
}

FlowValue _integer(int value) => .constant(Constant.integer(value));
Object? _number(FlowValue value) => (value.constant as ScalarConstant?)?.value;

FlowValue _load(FlowState state, FlowValue address, NativeTypeRef type) =>
    _step(state, LoadNative(_placeholder, type), operands: [address]).value;

FlowState _store(
  FlowState state,
  FlowValue address,
  NativeTypeRef type,
  FlowValue value,
) => _step(
  state,
  StoreNative(
    _placeholder,
    type,
    type.isFloating ? const Constant.floating(0) : _placeholder,
  ),
  operands: [address, value],
).normal!;

FlowResult _step(
  FlowState state,
  Instruction operation, {
  List<FlowValue>? operands,
  bool repeated = false,
}) => state.transfer(
  operation,
  operands ??
      operation.inputs.map((v) => FlowValue.constant(v as Constant)).toList(),
  allocate: (site) => FlowObject(site, _activation),
  repeated: repeated,
  invoke: (_, _, _) => throw StateError('Unexpected call'),
  call: (_, _, _) => throw StateError('Unexpected closure'),
)!;
