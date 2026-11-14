import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:dartc/src/optimizer/storage_elimination.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:storage-demand');
const _one = Constant.integer(1);
const _null = Constant.nullValue();

void main() {
  test(
    'caller reads retain factory writes across distinct summary instances',
    () {
      final box = _box();
      final factory = FunctionTarget(_uri, 'factory', box.type, [.integer]);
      final creating = Block(factory.parameterTypes);
      creating.finish(
        Return(
          creating.emit(
            Construct(box.constructor.target, [creating.parameters.single]),
          ),
        ),
      );
      final root = FunctionTarget(_uri, 'read', .integer, [.integer, .integer]);
      final reading = Block(root.parameterTypes);
      final first = reading.emit(DirectCall(factory, [reading.parameters[0]]));
      final second = reading.emit(DirectCall(factory, [reading.parameters[1]]));
      reading.finish(
        Return(
          reading.emit(
            IntBinary(
              .subtract,
              reading.emit(LoadField(box.field, first)),
              reading.emit(LoadField(box.field, second)),
            ),
          ),
        ),
      );
      final program = IrProgram(
        [box.declaration],
        [
          box.constructor,
          IrFunction(factory, [creating]),
          IrFunction(root, [reading]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: [.unknown(.integer), .unknown(.integer)]),
      ]).facts;
      expect(
        facts.valueOf(first).objects.single,
        isNot(facts.valueOf(second).objects.single),
      );
      final optimized = const ProgramStorageElimination().run(facts);
      for (final graph in [program, optimized]) {
        final entry = graph.implementationOf(root) as IrFunction;
        for (final (left, right) in [(3, 11), (42, -7), (0, 0)]) {
          expect(
            IrInterpreter(graph, {}).run(entry, [left, right]),
            left - right,
          );
        }
      }
    },
  );

  test('a private sibling instance does not demand its unrelated writes', () {
    final box = _box();
    final factory = FunctionTarget(_uri, 'factory', box.type, [.integer]);
    final creating = Block(factory.parameterTypes);
    creating.finish(
      Return(
        creating.emit(
          Construct(box.constructor.target, [creating.parameters.single]),
        ),
      ),
    );
    final root = FunctionTarget(_uri, 'read', .integer, [.integer, .integer]);
    final reading = Block(root.parameterTypes);
    final first = reading.emit(DirectCall(factory, [reading.parameters[0]]));
    final second = reading.emit(DirectCall(factory, [reading.parameters[1]]));
    reading.emit(StoreField(box.field, first, const Constant.integer(77)));
    reading.finish(Return(reading.emit(LoadField(box.field, second))));
    final program = IrProgram(
      [box.declaration],
      [
        box.constructor,
        IrFunction(factory, [creating]),
        IrFunction(root, [reading]),
      ],
    );
    final facts = ProgramFlow(program, [
      (target: root, arguments: [.unknown(.integer), .unknown(.integer)]),
    ]).facts;
    final optimized = const ProgramStorageElimination().run(facts);
    expect(_operations(optimized, root).whereType<StoreField>(), isEmpty);
    for (final graph in [program, optimized]) {
      final entry = graph.implementationOf(root) as IrFunction;
      for (final (left, right) in [(3, 11), (42, -7), (0, 0)]) {
        expect(IrInterpreter(graph, {}).run(entry, [left, right]), right);
      }
    }
  });

  test('unused globals disappear without removing their value effects', () {
    final tick = FunctionTarget(_uri, 'tick', .integer, [.integer]);
    final global = GlobalVariable(_uri, 'unused', ValueType.integer.nullable);
    final target = FunctionTarget(_uri, 'run', .integer, []);
    final block = Block();
    final value = block.emit(DirectCall(tick, [_one]));
    block.emit(StoreGlobal(global, value));
    block.finish(const Return(_one));
    final body = IrFunction(target, [block]);
    final program = IrProgram([], [body], globals: [global]);
    final optimized = _optimize(program, target);
    final operations = _operations(optimized, target);
    expect(operations.whereType<StoreGlobal>(), isEmpty);
    expect(operations.whereType<DirectCall>().map((call) => call.target), [
      tick,
    ]);
    for (final input in [program, optimized]) {
      final effects = <int>[];
      final runner = IrInterpreter(input, {
        (_uri, 'tick'): (value) {
          effects.add(value);
          return value;
        },
      });
      expect(runner.run(input.implementationOf(target) as IrFunction, []), 1);
      expect(effects, [1]);
    }
  });

  test('an unused binding still establishes a later late-final failure', () {
    final global = GlobalVariable(
      _uri,
      'once',
      ValueType.object.nullable,
      isLate: true,
      isFinal: true,
    );
    final target = FunctionTarget(_uri, 'run', .voidType, []);
    final block = Block()
      ..emit(StoreGlobal(global, _null))
      ..emit(StoreGlobal(global, _one))
      ..finish(const Return());
    final program = IrProgram(
      [],
      [
        IrFunction(target, [block]),
      ],
      globals: [global],
    );
    final optimized = _optimize(program, target);
    expect(
      _operations(optimized, target).whereType<StoreGlobal>(),
      hasLength(2),
    );
    Object failure(IrProgram input) {
      try {
        IrInterpreter(
          input,
          {},
        ).run(input.implementationOf(target) as IrFunction, []);
      } catch (error) {
        return IrInterpreter.exceptionType(error);
      }
      fail('The second binding must throw.');
    }

    expect(failure(optimized), failure(program));
  });

  test(
    'source constructor writes remain visible through an escaping return',
    () {
      final box = _box();
      final target = FunctionTarget(_uri, 'create', box.type, []);
      final block = Block();
      block.finish(
        Return(block.emit(Construct(box.constructor.target, [_one]))),
      );
      final getter = FunctionTarget(_uri, 'read', .integer, [box.type]);
      final read = Block(getter.parameterTypes);
      read.finish(
        Return(read.emit(LoadField(box.field, read.parameters.single))),
      );
      final program = IrProgram(
        [box.declaration],
        [
          box.constructor,
          IrFunction(target, [block]),
          IrFunction(getter, [read]),
        ],
      );
      final optimized = _optimize(program, target, escapingReturns: [target]);
      expect(
        _operations(optimized, box.constructor.target).whereType<StoreField>(),
        hasLength(1),
      );
      final runner = IrInterpreter(optimized, {});
      final value = runner.run(
        optimized.implementationOf(target) as IrFunction,
        [],
      );
      expect(
        runner.run(optimized.implementationOf(getter) as IrFunction, [value]),
        1,
      );
    },
  );

  for (final use in ['ignore', 'read', 'rethrow']) {
    test('a caught exception retains only $use storage observations', () {
      final box = _box();
      final target = FunctionTarget(_uri, 'catchBox', .integer, [.integer]);
      final entry = Block(target.parameterTypes);
      final handler = Block([.object, .stackTrace]);
      final value = entry.emit(
        Construct(box.constructor.target, [entry.parameters.single]),
      );
      entry.finish(
        Throw(
          value,
          onThrow: Jump(handler, [
            UnwindValue.exception,
            UnwindValue.stackTrace,
          ]),
        ),
      );
      final getter = FunctionTarget(_uri, 'readBox', .integer, [box.type]);
      final reading = Block(getter.parameterTypes);
      reading.finish(
        Return(reading.emit(LoadField(box.field, reading.parameters.single))),
      );
      switch (use) {
        case 'ignore':
          handler.finish(Return(entry.parameters.single));
        case 'read':
          handler.finish(
            Return(
              handler.emit(
                LoadField(
                  box.field,
                  handler.emit(
                    UncheckedCast(handler.parameters.first, box.type),
                  ),
                ),
              ),
            ),
          );
        case 'rethrow':
          handler.finish(
            Throw(
              handler.parameters.first,
              stackTrace: handler.parameters.last,
            ),
          );
      }
      final program = IrProgram(
        [box.declaration],
        [
          box.constructor,
          IrFunction(target, [entry, handler]),
          IrFunction(getter, [reading]),
        ],
      );
      final facts = ProgramFlow(program, [
        (target: target, arguments: [FlowValue.unknown(.integer)]),
      ]).facts;
      final optimized = const ProgramStorageElimination().run(facts);
      for (final graph in [program, optimized]) {
        final runner = IrInterpreter(graph, {});
        final body = graph.implementationOf(target) as IrFunction;
        for (final input in [-4, 0, 41]) {
          if (use != 'rethrow') {
            expect(runner.run(body, [input]), input);
          } else {
            Object? error;
            try {
              runner.run(body, [input]);
            } catch (value) {
              error = value;
            }
            expect(error, isNotNull);
            expect(
              runner.run(graph.implementationOf(getter) as IrFunction, [error]),
              input,
            );
          }
        }
      }
      expect(
        _operations(optimized, box.constructor.target).whereType<StoreField>(),
        use == 'ignore' ? isEmpty : hasLength(1),
      );
    });
  }

  test('a value passed to unknown code keeps its observable fields', () {
    final box = _box();
    final consume = FunctionTarget(_uri, 'consume', .voidType, [box.type]);
    final target = FunctionTarget(_uri, 'run', .voidType, []);
    final block = Block();
    final value = block.emit(Construct(box.constructor.target, [_one]));
    block.emit(DirectCall(consume, [value]));
    block.finish(const Return());
    final program = IrProgram(
      [box.declaration],
      [
        box.constructor,
        IrFunction(target, [block]),
      ],
    );
    final optimized = _optimize(program, target);
    expect(
      _operations(optimized, box.constructor.target).whereType<StoreField>(),
      hasLength(1),
    );
  });

  test('weak observations preserve a target that remains accessible', () {
    final targetType = ClassType(_uri, 'Target');
    final targetCtor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [],
      owner: targetType,
      kind: .initializer,
    );
    final weakType = ClassType(_uri, 'Weak');
    final weakField = InstanceField(weakType, 'target', targetType.nullable);
    final weakCtor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [targetType],
      owner: weakType,
      kind: .initializer,
    );
    final initializing = Block(weakCtor.parameterTypes);
    initializing.emit(
      StoreField(
        weakField,
        initializing.parameters[0],
        initializing.parameters[1],
      ),
    );
    initializing.finish(const Return());
    final global = GlobalVariable(_uri, 'root', targetType.nullable);
    final target = FunctionTarget(_uri, 'run', .boolean, []);
    final block = Block();
    final value = block.emit(Construct(targetCtor, []));
    block.emit(StoreGlobal(global, value));
    final weak = block.emit(Construct(weakCtor, [value]));
    final observed = block.emit(LoadField(weakField, weak));
    final retained = block.emit(LoadGlobal(global));
    block.finish(Return(block.emit(Identical(observed, retained))));
    final program = IrProgram(
      [
        IrClass(targetType, [], constructors: [targetCtor]),
        IrClass(
          weakType,
          [weakField],
          constructors: [weakCtor],
          weakFields: [weakField],
        ),
      ],
      [
        _empty(targetCtor),
        IrFunction(weakCtor, [initializing]),
        IrFunction(target, [block]),
      ],
      globals: [global],
    );
    final optimized = _optimize(program, target);
    for (final input in [program, optimized]) {
      expect(
        IrInterpreter(
          input,
          {},
        ).run(input.implementationOf(target) as IrFunction, []),
        isTrue,
      );
    }
  });

  test('explicit lifetime operations survive storage rewriting', () {
    final box = _box();
    final target = FunctionTarget(_uri, 'run', .voidType, []);
    final closure = FunctionTarget(
      _uri,
      'keep',
      .integer,
      [],
      kind: .closure,
      enclosing: target,
      sourceOffset: 0,
      captures: [box.type],
    );
    final closureBody = Block(closure.parameterTypes)
      ..finish(const Return(_one));
    final block = Block();
    final value = block.emit(Construct(box.constructor.target, [_one]));
    final captured = block.emit(MakeClosure(closure, [value]));
    final global = GlobalVariable(_uri, 'root', box.type.nullable);
    block.emit(StoreGlobal(global, value));
    block.emit(KeepAlive(captured));
    block.finish(const Return());
    final program = IrProgram(
      [box.declaration],
      [
        box.constructor,
        IrFunction(closure, [closureBody]),
        IrFunction(target, [block]),
      ],
      globals: [global],
    );
    final optimized = _optimize(program, target);
    expect(_operations(optimized, target).whereType<KeepAlive>(), hasLength(1));
  });

  test('an isolated nullable late-final binding can be removed', () {
    final global = GlobalVariable(
      _uri,
      'unused',
      ValueType.object.nullable,
      isLate: true,
      isFinal: true,
    );
    final target = FunctionTarget(_uri, 'run', .voidType, []);
    final block = Block()
      ..emit(StoreGlobal(global, _null))
      ..finish(const Return());
    final program = IrProgram(
      [],
      [
        IrFunction(target, [block]),
      ],
      globals: [global],
    );
    expect(
      _operations(_optimize(program, target), target).whereType<StoreGlobal>(),
      isEmpty,
    );
  });
}

IrProgram _optimize(
  IrProgram program,
  FunctionTarget target, {
  Iterable<FunctionTarget> escapingReturns = const [],
}) => const ProgramStorageElimination().run(
  ProgramFlow(program, [
    (target: target, arguments: <FlowValue>[]),
  ], escapingReturns: escapingReturns).facts,
);

Iterable<Instruction> _operations(IrProgram program, FunctionTarget target) =>
    (program.implementationOf(target) as IrFunction).blocks.expand(
      (block) => [
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    );

IrFunction _empty(FunctionTarget target) =>
    IrFunction(target, [Block(target.parameterTypes)..finish(const Return())]);

({
  ClassType type,
  InstanceField field,
  IrClass declaration,
  IrFunction constructor,
})
_box() {
  final type = ClassType(_uri, 'Box');
  final field = InstanceField(type, 'value', .integer);
  final constructor = FunctionTarget(
    _uri,
    '',
    .voidType,
    [.integer],
    owner: type,
    kind: .initializer,
  );
  final block = Block(constructor.parameterTypes);
  block.emit(StoreField(field, block.parameters[0], block.parameters[1]));
  block.finish(const Return());
  return (
    type: type,
    field: field,
    declaration: IrClass(type, [field], constructors: [constructor]),
    constructor: IrFunction(constructor, [block]),
  );
}
