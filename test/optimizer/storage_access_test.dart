import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:storage-access');
final _i64 = NativeScalarType(Int64);

void main() {
  for (final bound in [false, true]) {
    for (final wrap in [false, true]) {
      test(
        'late final initialization survives call summaries (bound=$bound, wrapper=$wrap)',
        () {
          final owner = ClassType(_uri, 'LateBox');
          final field = InstanceField(
            owner,
            'value',
            .integer,
            isLate: true,
            isFinal: true,
          );
          final external = FunctionTarget(_uri, 'externalWrite', .voidType, [
            owner,
          ]);
          final wrapper = FunctionTarget(_uri, 'wrapper', .voidType, [owner]);
          final bridge = Block(wrapper.parameterTypes);
          bridge.emit(DirectCall(external, bridge.parameters));
          bridge.finish(const Return());
          final setter = FunctionTarget(_uri, 'oracleWrite', .voidType, [
            owner,
          ]);
          final setterBlock = Block(setter.parameterTypes);
          setterBlock.emit(
            StoreField(
              field,
              setterBlock.parameters.single,
              const Constant.integer(42),
            ),
          );
          setterBlock.finish(const Return());
          final setterBody = IrFunction(setter, [setterBlock]);
          final root = FunctionTarget(_uri, 'root', .integer, []);
          final entry = Block();
          final value = entry.emit(
            NewPayload(owner, const Constant.integer(0)),
          );
          if (bound)
            entry.emit(StoreField(field, value, const Constant.integer(7)));
          entry.emit(DirectCall(wrap ? wrapper : external, [value]));
          final read = entry.emit(LoadField(field, value));
          entry.finish(Return(read));
          final program = IrProgram(
            [
              IrClass(owner, [field]),
            ],
            [
              IrFunction(root, [entry]),
              IrFunction(wrapper, [bridge]),
              setterBody,
            ],
            externals: [
              IrExternal(
                external,
                effects: const {Effect.writesStorage},
                capturesArguments: false,
              ),
            ],
          );
          final facts = _analyze(program, root);
          expect(facts.valueOf(read).isBottom, isFalse);
          if (bound) expect(_integer(facts.returnedBy(root)), 7);
          final rewritten = ProgramOptimizer(const [ProgramSimplification()])
              .run(program, [(target: root, arguments: [])])
              .program;
          for (final graph in [program, rewritten]) {
            late IrInterpreter interpreter;
            interpreter = IrInterpreter(
              graph,
              {},
              externalCalls: {
                external: (arguments) =>
                    bound ? null : interpreter.run(setterBody, arguments),
              },
            );
            expect(
              interpreter.run(graph.implementationOf(root) as IrFunction, []),
              bound ? 7 : 42,
            );
          }
        },
      );
    }
  }

  test('local allocation and recursion exclude unrelated global state', () {
    const count = 16;
    final plain = FunctionTarget(_uri, 'plain', .integer, [.integer]);
    final allocate = FunctionTarget(_uri, 'allocate', .integer, [.integer]);
    final recursive = FunctionTarget(_uri, 'recursive', .integer, [.integer]);
    final plainBlock = Block(plain.parameterTypes)
      ..finish(const Return(Constant.integer(7)));
    final allocateBlock = Block(allocate.parameterTypes);
    final allocation = allocateBlock.emit(
      NewCell(CellType(.integer), const Constant.integer(42)),
    );
    allocateBlock.finish(const Return(Constant.integer(7)));
    final recursiveBlock = Block(recursive.parameterTypes);
    final zero = Block()..finish(const Return(Constant.integer(7)));
    final next = Block();
    recursiveBlock.finish(
      Branch(
        recursiveBlock.emit(
          Equals(recursiveBlock.parameters.single, const Constant.integer(0)),
        ),
        Jump(zero),
        Jump(next),
      ),
    );
    next.finish(
      Return(
        next.emit(
          DirectCall(recursive, [
            next.emit(
              IntBinary(
                .subtract,
                recursiveBlock.parameters.single,
                const Constant.integer(1),
              ),
            ),
          ]),
        ),
      ),
    );
    final globals = [
      for (var i = 0; i < count; i++)
        GlobalVariable(_uri, 'global$i', ValueType.integer.nullable),
    ];
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    Value sum = const Constant.integer(0);
    for (var i = 0; i < count; i++) {
      entry.emit(StoreGlobal(globals[i], Constant.integer(i)));
      for (final target in [plain, allocate, recursive]) {
        final call = entry.emit(
          DirectCall(target, [const Constant.integer(0)]),
        );
        sum = entry.emit(IntBinary(.add, sum, call));
      }
    }
    entry.finish(Return(sum));
    final facts = _analyze(
      IrProgram([], [
        IrFunction(root, [entry]),
        IrFunction(plain, [plainBlock]),
        IrFunction(allocate, [allocateBlock]),
        IrFunction(recursive, [recursiveBlock, zero, next]),
      ], globals: globals),
      root,
    );
    expect(_integer(facts.returnedBy(root)), 21 * count);
    for (final target in [plain, allocate, recursive]) {
      expect(facts.activationsOf(target), hasLength(1), reason: target.name);
    }
    expect(facts.effectsOf(allocation), contains(Effect.allocates));
  });

  test(
    'growing call inputs preserve newly admitted caller object identities',
    () {
      final box = ClassType(_uri, 'Box');
      final identity = FunctionTarget(_uri, 'identity', box, [box]);
      final body = Block(identity.parameterTypes);
      body.finish(Return(body.parameters.single));
      final root = FunctionTarget(_uri, 'root', box, [.boolean]);
      final entry = Block(root.parameterTypes);
      final first = entry.emit(NewPayload(box, const Constant.integer(0)));
      final second = entry.emit(NewPayload(box, const Constant.integer(0)));
      final selected = Block([box]);
      entry.finish(
        Branch(
          entry.parameters.single,
          Jump(selected, [second]),
          Jump(selected, [first]),
        ),
      );
      final call = selected.emit(DirectCall(identity, selected.parameters));
      selected.finish(Return(call));
      final program = IrProgram(
        [IrClass(box, [])],
        [
          IrFunction(root, [entry, selected]),
          IrFunction(identity, [body]),
        ],
      );
      final flow = ProgramFlow(program, [
        (
          target: root,
          arguments: [FlowValue.constant(const Constant.boolean(false))],
        ),
      ]);
      final original = flow.facts.valueOf(first).objects.single;
      expect(flow.facts.valueOf(call).objects, {original});
      flow.extend(
        entries: [
          (
            target: root,
            arguments: [FlowValue.constant(const Constant.boolean(true))],
          ),
        ],
      );
      final actual = flow.facts;
      expect(actual.valueOf(call).objects, {
        original,
        actual.valueOf(second).objects.single,
      });
      expect(actual.activationsOf(identity), hasLength(1));
    },
  );

  test('a recursive component propagates its real global dependency', () {
    final global = GlobalVariable(_uri, 'observed', .integer, isLate: true);
    final noise = GlobalVariable(_uri, 'noise', ValueType.integer.nullable);
    final left = FunctionTarget(_uri, 'left', .integer, [.boolean]);
    final right = FunctionTarget(_uri, 'right', .integer, []);
    final leftEntry = Block(left.parameterTypes),
        base = Block(),
        again = Block();
    leftEntry.finish(
      Branch(leftEntry.parameters.single, Jump(again), Jump(base)),
    );
    base.finish(Return(base.emit(LoadGlobal(global))));
    again.finish(Return(again.emit(DirectCall(right, []))));
    final rightEntry = Block();
    rightEntry.finish(
      Return(
        rightEntry.emit(DirectCall(left, [const Constant.boolean(false)])),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    entry.emit(StoreGlobal(global, const Constant.integer(1)));
    final first = entry.emit(DirectCall(right, []));
    entry.emit(StoreGlobal(global, const Constant.integer(2)));
    final second = entry.emit(DirectCall(right, []));
    entry.emit(StoreGlobal(noise, const Constant.integer(9)));
    final third = entry.emit(DirectCall(right, []));
    entry.finish(
      Return(
        entry.emit(
          IntBinary(.add, first, entry.emit(IntBinary(.add, second, third))),
        ),
      ),
    );
    final facts = _analyze(
      IrProgram(
        [],
        [
          IrFunction(root, [entry]),
          IrFunction(left, [leftEntry, base, again]),
          IrFunction(right, [rightEntry]),
        ],
        globals: [global, noise],
      ),
      root,
    );
    expect(_integer(facts.returnedBy(root)), 5);
    expect(
      facts.callActivationsOf(first),
      isNot(facts.callActivationsOf(second)),
    );
    expect(facts.callActivationsOf(second), facts.callActivationsOf(third));
    expect(facts.activationsOf(left), hasLength(2));
    expect(facts.activationsOf(right), hasLength(2));
  });

  test('executed recursion retains joined identity and caller writes', () {
    final global = GlobalVariable(_uri, 'observed', .integer, isLate: true);
    final recurse = FunctionTarget(_uri, 'recurse', .integer, [.integer]);
    final head = Block(recurse.parameterTypes), base = Block(), again = Block();
    head.finish(
      Branch(
        head.emit(Equals(head.parameters.single, const Constant.integer(0))),
        Jump(base),
        Jump(again),
      ),
    );
    base.finish(Return(base.emit(LoadGlobal(global))));
    again.finish(
      Return(
        again.emit(
          DirectCall(recurse, [
            again.emit(
              IntBinary(
                .subtract,
                head.parameters.single,
                const Constant.integer(1),
              ),
            ),
          ]),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'root', .integer, [.integer]);
    final entry = Block(root.parameterTypes);
    entry.emit(StoreGlobal(global, const Constant.integer(7)));
    entry.finish(Return(entry.emit(DirectCall(recurse, entry.parameters))));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(root, [entry]),
          IrFunction(recurse, [head, base, again]),
        ],
        globals: [global],
      ),
      [
        (target: root, arguments: [FlowValue.unknown(.integer)]),
      ],
    ).facts;
    expect(_integer(facts.returnedBy(root)), 7);
    expect(facts.activationsOf(recurse).length, lessThanOrEqualTo(3));
  });

  test(
    'native reads distinguish changed bytes but ignore unrelated globals',
    () {
      final context = FunctionTarget(_uri, 'context', .integer, []);
      final read = FunctionTarget(_uri, 'read', .integer, [.integer]);
      final body = Block(read.parameterTypes);
      body.finish(Return(body.emit(LoadNative(body.parameters.single, _i64))));
      final root = FunctionTarget(_uri, 'root', .integer, []);
      final noise = GlobalVariable(_uri, 'noise', ValueType.integer.nullable);
      final entry = Block();
      final address = entry.emit(DirectCall(context, []));
      entry.emit(StoreNative(address, _i64, const Constant.integer(1)));
      final first = entry.emit(DirectCall(read, [address]));
      entry.emit(StoreNative(address, _i64, const Constant.integer(2)));
      final second = entry.emit(DirectCall(read, [address]));
      entry.emit(StoreGlobal(noise, const Constant.integer(9)));
      final third = entry.emit(DirectCall(read, [address]));
      entry.finish(
        Return(
          entry.emit(
            IntBinary(.add, first, entry.emit(IntBinary(.add, second, third))),
          ),
        ),
      );
      final facts = ProgramFlow(
        IrProgram(
          [],
          [
            IrFunction(root, [entry]),
            IrFunction(read, [body]),
          ],
          globals: [noise],
          externals: [
            IrExternal(
              context,
              effects: const {.readsStorage},
              memory: const .unchanged(),
              capturesArguments: false,
            ),
          ],
        ),
        [(target: root, arguments: [])],
        initialMemory: {context: List.filled(8, 0)},
        memoryLayout: _Memory(),
      ).facts;
      expect(_integer(facts.returnedBy(root)), 5);
      expect(
        facts.callActivationsOf(first),
        isNot(facts.callActivationsOf(second)),
      );
      expect(facts.callActivationsOf(second), facts.callActivationsOf(third));
      expect(facts.activationsOf(read), hasLength(2));
    },
  );

  test('noncapturing native writes retain previously escaped capabilities', () {
    final type = ClassType(_uri, 'Box');
    final field = InstanceField(type, 'value', .integer);
    final expose = FunctionTarget(_uri, 'expose', .voidType, [type]);
    final mutate = FunctionTarget(_uri, 'mutate', .voidType, []);
    final helper = FunctionTarget(_uri, 'helper', .voidType, []);
    final body = Block();
    body.emit(DirectCall(mutate, []));
    body.finish(const Return());
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    final object = entry.emit(NewPayload(type, const Constant.integer(0)));
    entry.emit(StoreField(field, object, const Constant.integer(7)));
    entry.emit(DirectCall(expose, [object]));
    entry.emit(DirectCall(helper, []));
    entry.finish(Return(entry.emit(LoadField(field, object))));
    final facts = _analyze(
      IrProgram(
        [
          IrClass(type, [field]),
        ],
        [
          IrFunction(root, [entry]),
          IrFunction(helper, [body]),
        ],
        externals: [
          IrExternal(expose, effects: const {}, memory: const .unchanged()),
          IrExternal(
            mutate,
            effects: const {.writesStorage},
            memory: const .arbitrary(),
            capturesArguments: false,
          ),
        ],
      ),
      root,
    );
    expect(facts.returnedBy(root).isBottom, isFalse);
    expect(facts.returnedBy(root).constant, isNull);
  });

  for (final compatible in [true, false]) {
    test('unresolved generic aliases use possible instances ($compatible)', () {
      final box = ClassType(_uri, 'Box');
      final subtype = ClassType(_uri, 'Subtype', superclass: box);
      final value = InstanceField(box, 'value', .integer);
      final t = TypeParameterType('T')
        ..initializeBound(compatible ? box : subtype);
      final u = TypeParameterType('U')..initializeBound(box);
      final holder = ClassType(_uri, 'Holder', typeParameters: [u]);
      final held = InstanceField(holder, 'held', u);
      final e = TypeParameterType('E')..initializeBound(box);
      final wrap = FunctionTarget(
        _uri,
        'wrap',
        holder.instantiate([e]),
        [box],
        typeParameters: [e],
      );
      final setter = FunctionTarget(_uri, 'set', .voidType, [box]);
      final body = Block(setter.parameterTypes);
      body.emit(
        StoreField(value, body.parameters.single, const Constant.integer(9)),
      );
      body.finish(const Return());
      final root = FunctionTarget(
        _uri,
        'root',
        .integer,
        [],
        typeParameters: [t],
      );
      final entry = Block();
      final object = entry.emit(NewPayload(box, const Constant.integer(0)));
      entry.emit(StoreField(value, object, const Constant.integer(1)));
      // For T=Box this permitted external can put its retained argument into
      // Holder<T>. For T extends Subtype that concrete Box cannot be the alias.
      final wrapped = entry.emit(
        DirectCall(wrap, [object], typeArguments: [t]),
      );
      final alias = entry.emit(LoadField(held, wrapped));
      entry.emit(DirectCall(setter, [alias]));
      final observed = entry.emit(LoadField(value, object));
      entry.finish(Return(observed));
      final facts = _analyze(
        IrProgram(
          [
            IrClass(box, [value]),
            IrClass(subtype, []),
            IrClass(holder, [held]),
          ],
          [
            IrFunction(root, [entry]),
            IrFunction(setter, [body]),
          ],
          externals: [
            IrExternal(wrap, effects: const {}, memory: const .unchanged()),
          ],
        ),
        root,
      );
      expect(facts.valueOf(alias).unknownTypes, contains(t));
      expect(t.accepts(box), isFalse);
      expect(t.mayHaveInstance(box), compatible);
      if (compatible) {
        expect(facts.valueOf(observed).constant, isNull);
        expect(facts.returnedBy(root).integers!.contains(9), isTrue);
      } else {
        expect(_integer(facts.returnedBy(root)), 1);
      }
    });
  }

  test('unbounded raw writes invalidate private caller objects and globals', () {
    final type = ClassType(_uri, 'Box');
    final field = InstanceField(type, 'value', .integer);
    final global = GlobalVariable(_uri, 'global', .integer, isLate: true);
    final writer = FunctionTarget(_uri, 'write', .voidType, [.integer]);
    final body = Block(writer.parameterTypes);
    body.emit(
      StoreNative(body.parameters.single, _i64, const Constant.integer(9)),
    );
    body.finish(const Return());
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block();
    final object = entry.emit(NewPayload(type, const Constant.integer(0)));
    entry.emit(StoreField(field, object, const Constant.integer(7)));
    entry.emit(StoreGlobal(global, const Constant.integer(8)));
    // A constant numeric address carries no proved region or allocation range.
    entry.emit(DirectCall(writer, [const Constant.integer(4096)]));
    final readField = entry.emit(LoadField(field, object));
    final readGlobal = entry.emit(LoadGlobal(global));
    entry.finish(Return(entry.emit(IntBinary(.add, readField, readGlobal))));
    final facts = _analyze(
      IrProgram(
        [
          IrClass(type, [field]),
        ],
        [
          IrFunction(root, [entry]),
          IrFunction(writer, [body]),
        ],
        globals: [global],
      ),
      root,
    );
    expect(facts.valueOf(readField).constant, isNull);
    expect(facts.valueOf(readGlobal).constant, isNull);
    expect(facts.returnedBy(root).isBottom, isFalse);
  });

  for (final throwing in [false, true]) {
    test(
      'recursive summary retains writes on ${throwing ? 'exceptional' : 'normal'} exit',
      () {
        final cellType = ClassType(_uri, 'Swapped');
        final field = InstanceField(cellType, 'value', .integer);
        final change = FunctionTarget(_uri, 'change', .voidType, [
          cellType,
          .integer,
        ]);
        final body = Block(change.parameterTypes),
            base = Block(),
            recurse = Block();
        body.finish(
          Branch(
            body.emit(Equals(body.parameters[1], const Constant.integer(0))),
            Jump(base),
            Jump(recurse),
          ),
        );
        base.finish(
          throwing ? Throw(const Constant.string('done')) : const Return(),
        );
        final read = recurse.emit(LoadField(field, body.parameters[0]));
        recurse.emit(
          StoreField(
            field,
            body.parameters[0],
            recurse.emit(IntBinary(.subtract, const Constant.integer(3), read)),
          ),
        );
        recurse.emit(
          DirectCall(change, [
            body.parameters[0],
            recurse.emit(
              IntBinary(
                .subtract,
                body.parameters[1],
                const Constant.integer(1),
              ),
            ),
          ]),
        );
        recurse.finish(const Return());
        final root = FunctionTarget(_uri, 'root', .integer, []);
        final entry = Block(), normal = Block(), exceptional = Block();
        final cell = entry.emit(
          NewPayload(cellType, const Constant.integer(0)),
        );
        entry.emit(StoreField(field, cell, const Constant.integer(1)));
        final call = DirectCall(change, [cell, const Constant.integer(3)]);
        entry.finish(
          Invoke(call, onReturn: Jump(normal), onThrow: Jump(exceptional)),
        );
        final normalRead = normal.emit(LoadField(field, cell));
        final exceptionalRead = exceptional.emit(LoadField(field, cell));
        normal.finish(Return(normalRead));
        exceptional.finish(Return(exceptionalRead));
        final facts = _analyze(
          IrProgram(
            [
              IrClass(cellType, [field]),
            ],
            [
              IrFunction(root, [entry, normal, exceptional]),
              IrFunction(change, [body, base, recurse]),
            ],
          ),
          root,
        );
        final observed = facts.valueOf(throwing ? exceptionalRead : normalRead);
        expect(observed.integers!.contains(2), isTrue);
        expect(observed.constant, isNot(const Constant.integer(1)));
        if (throwing) {
          expect(
            facts.failureOf(call).exception.constant,
            const Constant.string('done'),
          );
        }
      },
    );
  }

  test('allocation failure contributes real global and exceptional state', () {
    final global = GlobalVariable(_uri, 'reported', .integer, isLate: true);
    final fail = FunctionTarget(_uri, 'failure', .never, []);
    final failure = Block();
    failure.emit(StoreGlobal(global, const Constant.integer(9)));
    failure.finish(Throw(const Constant.string('exhausted')));
    final allocate = FunctionTarget(_uri, 'allocate', .integer, []);
    final body = Block();
    body.emit(NewCell(CellType(.integer), const Constant.integer(42)));
    body.finish(const Return(Constant.integer(7)));
    final root = FunctionTarget(_uri, 'root', .integer, []);
    final entry = Block(), done = Block(), handler = Block();
    entry.emit(StoreGlobal(global, const Constant.integer(0)));
    final call = DirectCall(allocate, []);
    entry.finish(Invoke(call, onReturn: Jump(done), onThrow: Jump(handler)));
    done.finish(const Return(Constant.integer(7)));
    final observed = handler.emit(LoadGlobal(global));
    handler.finish(Return(observed));
    final facts = ProgramFlow(
      IrProgram(
        [],
        [
          IrFunction(root, [entry, done, handler]),
          IrFunction(allocate, [body]),
          IrFunction(fail, [failure]),
        ],
        globals: [global],
      ),
      [(target: root, arguments: [])],
      allocationFailure: fail,
    ).facts;
    expect(_integer(facts.valueOf(observed)), 9);
    expect(
      facts.failureOf(call).exception.constant,
      const Constant.string('exhausted'),
    );
  });
}

ProgramFlowFacts _analyze(IrProgram program, FunctionTarget root) =>
    ProgramFlow(program, [(target: root, arguments: [])]).facts;

Object? _integer(FlowValue value) => switch (value.constant) {
  ScalarConstant(:final value) => value,
  _ => null,
};

final class _Memory() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(const Target(.macos, .arm64));
  @override
  ObjectLayout objectLayout(ClassType type) =>
      throw StateError('No object layout');
}
