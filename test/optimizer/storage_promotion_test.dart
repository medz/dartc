import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:dartc/src/optimizer/program_optimizer.dart';
import 'package:dartc/src/optimizer/simplification.dart';
import 'package:dartc/src/optimizer/storage_elimination.dart';
import 'package:dartc/src/optimizer/storage_promotion.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

final _uri = Uri.parse('memory:storage-promotion');

void main() {
  for (final invoke in [false, true]) {
    test(
      'exception payload fields promote from their actual unwind edge (invoke=$invoke)',
      () {
        final box = ClassType(_uri, 'ThrownBox');
        final field = InstanceField(box, 'value', .integer);
        final constructor = FunctionTarget(
          _uri,
          '',
          .voidType,
          [.integer],
          owner: box,
          kind: .initializer,
        );
        final initializing = Block(constructor.parameterTypes);
        initializing.emit(
          StoreField(
            field,
            initializing.parameters[0],
            initializing.parameters[1],
          ),
        );
        initializing.finish(const Return());
        final fail = FunctionTarget(_uri, 'fail', .never, [box]);
        final target = FunctionTarget(_uri, 'catchValue', .integer, [
          .boolean,
          .integer,
          .integer,
        ]);
        final entry = Block(target.parameterTypes),
            left = Block(),
            right = Block(),
            handler = Block([.object]);
        entry.finish(Branch(entry.parameters[0], Jump(left), Jump(right)));
        for (final (block, argument) in [
          (left, entry.parameters[1]),
          (right, entry.parameters[2]),
        ]) {
          final payload = block.emit(Construct(constructor, [argument]));
          final edge = Jump(handler, [UnwindValue.exception]);
          if (invoke) {
            block.finish(
              Invoke(
                DirectCall(fail, [payload]),
                onReturn: null,
                onThrow: edge,
              ),
            );
          } else {
            block.finish(Throw(payload, onThrow: edge));
          }
        }
        final receiver = handler.emit(
          UncheckedCast(handler.parameters.single, box),
        );
        handler.finish(Return(handler.emit(LoadField(field, receiver))));
        final original = IrFunction(target, [entry, left, right, handler]);
        final throwing = Block(fail.parameterTypes);
        throwing.finish(Throw(throwing.parameters.single));
        final program = IrProgram(
          [
            IrClass(box, [field], constructors: [constructor]),
          ],
          [
            IrFunction(constructor, [initializing]),
            IrFunction(fail, [throwing]),
            original,
          ],
        );
        final facts = ProgramFlow(program, [
          (
            target: target,
            arguments: target.parameterTypes.map(FlowValue.unknown).toList(),
          ),
        ]).facts;
        final optimized = const ProgramStoragePromotion().run(facts);
        for (final graph in [program, optimized]) {
          final body = graph.implementationOf(target) as IrFunction;
          for (final choose in [true, false]) {
            for (final (left, right) in [(-4, 9), (0, 41), (7, -2)]) {
              expect(
                IrInterpreter(graph, {}).run(body, [choose, left, right]),
                choose ? left : right,
              );
            }
          }
        }
        expect(
          (optimized.implementationOf(target) as IrFunction).blocks
              .expand((block) => block.instructions)
              .whereType<LoadField>(),
          isEmpty,
        );
      },
    );
  }

  test(
    'unknown reentry writes survive both the normal and exceptional edge',
    () {
      final global = GlobalVariable(_uri, 'value', .integer, isLate: true);
      final writer = FunctionTarget(_uri, 'write', .integer, [.integer]);
      final writing = Block(writer.parameterTypes);
      writing.emit(StoreGlobal(global, writing.parameters.single));
      writing.finish(Return(writing.parameters.single));
      final write = IrFunction(writer, [writing]);
      final external = FunctionTarget(_uri, 'foreign', .integer, [.integer]);
      final target = FunctionTarget(_uri, 'run', .integer, [
        .boolean,
        .integer,
        .integer,
        .integer,
      ]);
      final entry = Block(target.parameterTypes),
          left = Block(),
          right = Block(),
          join = Block(),
          normal = Block(),
          failed = Block();
      entry.finish(Branch(entry.parameters[0], Jump(left), Jump(right)));
      left.emit(StoreGlobal(global, entry.parameters[1]));
      left.finish(Jump(join));
      right.emit(StoreGlobal(global, entry.parameters[2]));
      right.finish(Jump(join));
      final call = DirectCall(external, [entry.parameters[3]]);
      join.finish(Invoke(call, onReturn: Jump(normal), onThrow: Jump(failed)));
      normal.finish(Return(normal.emit(LoadGlobal(global))));
      failed.finish(Return(failed.emit(LoadGlobal(global))));
      final root = IrFunction(target, [
        entry,
        left,
        right,
        join,
        normal,
        failed,
      ]);
      final program = IrProgram(
        [],
        [root, write],
        globals: [global],
        externals: [IrExternal(external)],
      );
      final optimized = _optimize(program, target, openEntries: [writer]);
      for (final input in [program, optimized]) {
        final events = <int>[];
        late IrInterpreter interpreter;
        interpreter = IrInterpreter(input, {
          (_uri, 'foreign'): (int value) {
            events.add(value);
            interpreter.run(input.implementationOf(writer) as IrFunction, [
              value,
            ]);
            if (value < 0) throw StateError('after write');
            return value;
          },
        });
        final body = input.implementationOf(target) as IrFunction;
        for (final args in [
          [true, 3, 5, 9],
          [false, 3, 5, 11],
          [true, 3, 5, -7],
          [false, 3, 5, -13],
        ]) {
          expect(interpreter.run(body, args), args[3]);
        }
        expect(events, [9, 11, -7, -13]);
      }
    },
  );

  test('field phis preserve distinct allocation identities across unrelated writes', () {
    final box = ClassType(_uri, 'Box');
    final field = InstanceField(box, 'value', .integer);
    final constructor = FunctionTarget(
      _uri,
      '',
      .voidType,
      [.integer],
      owner: box,
      kind: .initializer,
    );
    final initialize = Block(constructor.parameterTypes);
    initialize.emit(
      StoreField(field, initialize.parameters[0], initialize.parameters[1]),
    );
    initialize.finish(const Return());
    final target = FunctionTarget(_uri, 'select', .integer, [
      .boolean,
      .integer,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        left = Block(),
        right = Block(),
        join = Block();
    final selected = entry.emit(Construct(constructor, [entry.parameters[1]]));
    final other = entry.emit(
      Construct(constructor, [const Constant.integer(0)]),
    );
    entry.finish(Branch(entry.parameters[0], Jump(left), Jump(right)));
    left.emit(StoreField(field, selected, entry.parameters[1]));
    left.finish(Jump(join));
    right.emit(StoreField(field, selected, entry.parameters[2]));
    right.finish(Jump(join));
    join.emit(StoreField(field, other, const Constant.integer(99)));
    final result = join.emit(LoadField(field, selected));
    join.finish(Return(result));
    final root = IrFunction(target, [entry, left, right, join]);
    final program = IrProgram(
      [
        IrClass(box, [field], constructors: [constructor]),
      ],
      [
        IrFunction(constructor, [initialize]),
        root,
      ],
    );
    final optimized = _optimize(program, target);
    for (final input in [program, optimized]) {
      final body = input.implementationOf(target) as IrFunction;
      for (final args in [
        [true, 3, 5],
        [false, 3, 5],
        [false, -3, -5],
      ]) {
        expect(
          IrInterpreter(input, {}).run(body, args),
          args[0] == true ? args[1] : args[2],
        );
      }
    }
    final residual = (optimized.implementationOf(target) as IrFunction).blocks
        .expand((b) => b.instructions);
    expect(
      residual.where(
        (op) => op is Construct || op is LoadField || op is StoreField,
      ),
      isEmpty,
    );
  });
}

IrProgram _optimize(
  IrProgram program,
  FunctionTarget entry, {
  Iterable<FunctionTarget> openEntries = const [],
}) =>
    ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
    ]).run(program, [
      (
        target: entry,
        arguments: entry.parameterTypes.map(FlowValue.unknown).toList(),
      ),
    ], openEntries: openEntries).program;
