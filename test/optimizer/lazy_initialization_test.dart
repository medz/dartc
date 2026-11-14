import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:lazy-initialization');
const _one = Constant.integer(1);

void main() {
  test(
    'an unused pure final initializer disappears through ordinary calls',
    () {
      final initializer = FunctionTarget(_uri, 'initialize', .integer, []);
      final binding = _binding(initializer);
      final root = FunctionTarget(_uri, 'run', .integer, [.integer]);
      final entry = Block(root.parameterTypes);
      entry.emit(DirectCall(binding.getter.target, []));
      entry.finish(Return(entry.parameters.single));
      final program = IrProgram(
        [],
        [
          IrFunction(initializer, [Block()..finish(const Return(_one))]),
          binding.getter,
          IrFunction(root, [entry]),
        ],
        globals: [binding.global],
      );
      final optimized = _optimize(program, root);
      expect(optimized.definitions, {root});
      for (final graph in [program, optimized.program]) {
        final runner = IrInterpreter(graph, {});
        for (final input in [-3, 0, 41]) {
          expect(
            runner.run(graph.implementationOf(root) as IrFunction, [input]),
            input,
          );
        }
      }
    },
  );

  test(
    'an unused initialized value keeps observable initialization exactly once',
    () {
      final output = FunctionTarget(_uri, 'output', .integer, [.integer]);
      final initializer = FunctionTarget(_uri, 'initialize', .integer, []);
      final initializing = Block();
      initializing.finish(
        Return(initializing.emit(DirectCall(output, [_one]))),
      );
      final binding = _binding(initializer);
      final root = FunctionTarget(_uri, 'run', .integer, []);
      final entry = Block()
        ..emit(DirectCall(binding.getter.target, []))
        ..finish(const Return(_one));
      final program = IrProgram(
        [],
        [
          IrFunction(initializer, [initializing]),
          binding.getter,
          IrFunction(root, [entry]),
        ],
        globals: [binding.global],
        externals: [IrExternal(output)],
      );
      final optimized = _optimize(program, root);
      for (final graph in [program, optimized.program]) {
        var calls = 0;
        final runner = IrInterpreter(graph, {(_uri, 'output'): (_) => ++calls});
        final body = graph.implementationOf(root) as IrFunction;
        expect(runner.run(body, []), 1);
        expect(runner.run(body, []), 1);
        expect(calls, 1);
      }
    },
  );

  test('discarded values preserve a throwing initializer and its retry', () {
    final output = FunctionTarget(_uri, 'output', .integer, [.integer]);
    final initializer = FunctionTarget(_uri, 'initialize', .integer, []);
    final initializing = Block();
    initializing.finish(Return(initializing.emit(DirectCall(output, [_one]))));
    final binding = _binding(initializer);
    final root = FunctionTarget(_uri, 'run', .integer, []);
    final entry = Block(), normal = Block(), failed = Block();
    entry.finish(
      Invoke(
        DirectCall(binding.getter.target, []),
        onReturn: Jump(normal),
        onThrow: Jump(failed),
      ),
    );
    normal.finish(const Return(_one));
    failed.finish(const Return(Constant.integer(0)));
    final program = IrProgram(
      [],
      [
        IrFunction(initializer, [initializing]),
        binding.getter,
        IrFunction(root, [entry, normal, failed]),
      ],
      globals: [binding.global],
      externals: [IrExternal(output)],
    );
    final optimized = _optimize(program, root);
    for (final graph in [program, optimized.program]) {
      var attempts = 0;
      final runner = IrInterpreter(graph, {
        (_uri, 'output'): (_) {
          if (++attempts == 1) throw StateError('retry');
          return 7;
        },
      });
      final body = graph.implementationOf(root) as IrFunction;
      expect(runner.run(body, []), 0);
      expect(runner.run(body, []), 1);
      expect(runner.run(body, []), 1);
      expect(attempts, 2);
    }
  });

  test(
    'the first read freezes mutable state even when its result is unused',
    () {
      final mutable = GlobalVariable(
        _uri,
        'mutable',
        ValueType.integer.nullable,
      );
      final initializer = FunctionTarget(_uri, 'initialize', mutable.type, []);
      final initializing = Block();
      initializing.finish(Return(initializing.emit(LoadGlobal(mutable))));
      final binding = _binding(initializer);
      final root = FunctionTarget(_uri, 'run', mutable.type, [.integer]);
      final entry = Block(root.parameterTypes);
      entry.emit(StoreGlobal(mutable, entry.parameters.single));
      final first = entry.emit(DirectCall(binding.getter.target, []));
      entry.emit(StoreGlobal(mutable, const Constant.integer(99)));
      entry.finish(Return(entry.emit(DirectCall(binding.getter.target, []))));
      final program = IrProgram(
        [],
        [
          IrFunction(initializer, [initializing]),
          binding.getter,
          IrFunction(root, [entry]),
        ],
        globals: [mutable, binding.global],
      );
      final facts = ProgramFlow(program, [
        (target: root, arguments: [FlowValue.unknown(.integer)]),
      ]).facts;
      expect(facts.canDiscard(first), isFalse);
      final optimized = _optimize(program, root);
      for (final graph in [program, optimized.program]) {
        for (final value in [-3, 0, 41]) {
          final runner = IrInterpreter(graph, {});
          final body = graph.implementationOf(root) as IrFunction;
          expect(runner.run(body, [value]), value);
        }
      }
    },
  );
  test('discarding a lazy read cannot remove an initializer cycle', () {
    final initializer = FunctionTarget(_uri, 'initialize', .integer, []);
    final initializing = Block(), loop = Block();
    initializing.finish(Jump(loop));
    loop.finish(Jump(loop));
    final binding = _binding(initializer);
    final root = FunctionTarget(_uri, 'run', .integer, []);
    final entry = Block()
      ..emit(DirectCall(binding.getter.target, []))
      ..finish(const Return(_one));
    final program = IrProgram(
      [],
      [
        IrFunction(initializer, [initializing, loop]),
        binding.getter,
        IrFunction(root, [entry]),
      ],
      globals: [binding.global],
    );
    final optimized = _optimize(program, root);
    expect(optimized.definitions, contains(initializer));
    expect(optimized.returnedBy(root).isBottom, isTrue);
    final body = optimized.program.implementationOf(root) as IrFunction;
    expect(optimized.canDiscard(body.entry.instructions.single), isFalse);
  });
}

({GlobalVariable global, IrFunction getter}) _binding(
  FunctionTarget initializer,
) {
  final global = GlobalVariable(
    _uri,
    'value',
    initializer.returnType,
    isFinal: true,
    initializer: initializer,
  );
  final target = FunctionTarget(_uri, 'get', global.type, []);
  final entry = Block();
  entry.finish(Return(entry.emit(LoadGlobal(global))));
  return (global: global, getter: IrFunction(target, [entry]));
}

ProgramFlowFacts _optimize(IrProgram program, FunctionTarget root) =>
    ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
    ]).run(program, [
      (
        target: root,
        arguments: root.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ]);
