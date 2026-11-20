import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  for (final invoke in [false, true]) {
    for (final overwritten in [false, true]) {
      test(
        'result guard keeps matching writes (invoke=$invoke, intervening write=$overwritten)',
        () {
          final uri = Uri.parse('memory:result-guard');
          final saved = GlobalVariable(uri, 'saved', .integer, isLate: true);
          final choose = FunctionTarget(uri, 'choose', .integer, [
            .boolean,
            .boolean,
          ]);
          final entry = Block(choose.parameterTypes),
              placed = Block(),
              empty = Block(),
              failed = Block(),
              normal = Block();
          entry.finish(Branch(entry.parameters[1], Jump(failed), Jump(normal)));
          failed.emit(StoreGlobal(saved, const Constant.integer(61)));
          failed.finish(Throw(const Constant.string('failed')));
          normal.finish(Branch(entry.parameters[0], Jump(placed), Jump(empty)));
          placed.emit(StoreGlobal(saved, const Constant.integer(37)));
          placed.finish(const Return(Constant.integer(8)));
          empty.finish(const Return(Constant.integer(0)));
          final main = FunctionTarget(uri, 'main', .integer, [
            .boolean,
            .boolean,
          ]);
          final start = Block(main.parameterTypes),
              guard = Block([ValueType.integer]),
              zero = Block(),
              nonzero = Block(),
              caught = Block();
          start.emit(StoreGlobal(saved, const Constant.integer(12)));
          final call = DirectCall(choose, start.parameters);
          if (invoke) {
            start.finish(
              Invoke(
                call,
                onReturn: Jump(guard, [call]),
                onThrow: Jump(caught),
              ),
            );
          } else {
            start.emit(call);
            start.finish(Jump(guard, [call]));
          }
          if (overwritten) {
            guard.emit(StoreGlobal(saved, const Constant.integer(49)));
          }
          final equals = guard.emit(
            Equals(guard.parameters.single, const Constant.integer(0)),
          );
          guard.finish(Branch(equals, Jump(zero), Jump(nonzero)));
          final onZero = zero.emit(LoadGlobal(saved)),
              onSuccess = nonzero.emit(LoadGlobal(saved)),
              onThrow = caught.emit(LoadGlobal(saved));
          zero.finish(Return(onZero));
          nonzero.finish(Return(onSuccess));
          caught.finish(Return(onThrow));
          final root = IrFunction(main, [
            start,
            guard,
            zero,
            nonzero,
            if (invoke) caught,
          ]);
          final program = IrProgram(
            [],
            [
              root,
              IrFunction(choose, [entry, normal, placed, empty, failed]),
            ],
            globals: [saved],
          );
          final ir = IrInterpreter(program, {});
          expect(ir.run(root, [true, false]), overwritten ? 49 : 37);
          expect(ir.run(root, [false, false]), overwritten ? 49 : 12);
          if (invoke) expect(ir.run(root, [true, true]), 61);
          final facts = ProgramFlow(program, [
            (
              target: main,
              arguments: [
                FlowValue.unknown(.boolean),
                FlowValue.unknown(.boolean),
              ],
            ),
          ]).facts;
          int? result(Value v) =>
              (facts.valueOf(v).constant as ScalarConstant?)?.value as int?;
          expect(facts.exitsOf(call), (normal: true, exceptional: true));
          if (invoke) expect(result(onThrow), 61);
          expect(result(onZero), overwritten ? 49 : 12);
          expect(result(onSuccess), overwritten ? 49 : 37);
        },
      );
    }
  }
  test(
    'open returns reach both arms and each predecessor contributes its writes',
    () {
      final uri = Uri.parse('memory:return-alternatives');
      const integer = ValueType.integer;
      final saved = GlobalVariable(uri, 'saved', integer, isLate: true);
      final choose = FunctionTarget(uri, 'choose', integer, [
        .boolean,
        .boolean,
        integer,
      ]);
      final entry = Block(choose.parameterTypes),
          fallback = Block(),
          known = Block(),
          zero = Block(),
          nonzero = Block();
      entry.finish(Branch(entry.parameters[0], Jump(fallback), Jump(known)));
      fallback.finish(Return(entry.parameters[2]));
      known.finish(Branch(entry.parameters[1], Jump(zero), Jump(nonzero)));
      zero.emit(StoreGlobal(saved, const Constant.integer(37)));
      zero.finish(const Return(Constant.integer(0)));
      nonzero.emit(StoreGlobal(saved, const Constant.integer(61)));
      nonzero.finish(const Return(Constant.integer(7)));
      final root = FunctionTarget(uri, 'root', integer, [
        .boolean,
        ...choose.parameterTypes,
      ]);
      final start = Block(root.parameterTypes),
          callBlock = Block(),
          bypass = Block(),
          guard = Block([integer]),
          yes = Block(),
          no = Block();
      start.emit(StoreGlobal(saved, const Constant.integer(12)));
      start.finish(Branch(start.parameters[0], Jump(bypass), Jump(callBlock)));
      bypass.emit(StoreGlobal(saved, const Constant.integer(79)));
      bypass.finish(Jump(guard, [const Constant.integer(0)]));
      final call = callBlock.emit(DirectCall(choose, start.parameters.skip(1)));
      callBlock.finish(Jump(guard, [call]));
      guard.finish(
        Branch(
          guard.emit(
            Equals(guard.parameters.single, const Constant.integer(0)),
          ),
          Jump(yes),
          Jump(no),
        ),
      );
      final whenZero = yes.emit(LoadGlobal(saved)),
          whenNonzero = no.emit(LoadGlobal(saved));
      yes.finish(Return(whenZero));
      no.finish(Return(whenNonzero));
      final main = IrFunction(root, [start, bypass, callBlock, guard, yes, no]);
      final program = IrProgram(
        [],
        [
          main,
          IrFunction(choose, [entry, fallback, known, zero, nonzero]),
        ],
        globals: [saved],
      );
      final facts = ProgramFlow(program, [
        (
          target: root,
          arguments: root.parameterTypes.map(FlowValue.unknown).toList(),
        ),
      ]).facts;
      final ir = IrInterpreter(program, {});
      for (final (args, expected) in [
        ([true, false, false, 3], 79),
        ([false, true, false, 0], 12),
        ([false, true, false, 1], 12),
        ([false, false, true, 3], 37),
        ([false, false, false, 3], 61),
      ]) {
        expect(ir.run(main, args), expected);
      }
      final empty = facts.valueOf(whenZero).integers!,
          present = facts.valueOf(whenNonzero).integers!;
      expect((empty.lower, empty.upper), (12, 79));
      expect(empty.contains(37), isTrue);
      expect((present.lower, present.upper), (12, 61));
    },
  );
  test(
    'a later invocation adds returns and updates a previously reached exit',
    () {
      final uri = Uri.parse('memory:return-reentry');
      final saved = GlobalVariable(uri, 'saved', .integer, isLate: true);
      final choose = FunctionTarget(uri, 'choose', .integer, [
        .boolean,
        .integer,
      ]);
      final entry = Block(choose.parameterTypes),
          success = Block(),
          failed = Block();
      entry.finish(Branch(entry.parameters[0], Jump(success), Jump(failed)));
      success.emit(StoreGlobal(saved, entry.parameters[1]));
      success.finish(const Return(Constant.integer(1)));
      failed.finish(const Return(Constant.integer(0)));
      final root = FunctionTarget(uri, 'root', .integer, choose.parameterTypes);
      final start = Block(root.parameterTypes),
          guard = Block([ValueType.integer]),
          zero = Block(),
          nonzero = Block();
      start.emit(StoreGlobal(saved, const Constant.integer(5)));
      final call = start.emit(DirectCall(choose, start.parameters));
      start.finish(Jump(guard, [call]));
      guard.finish(
        Branch(
          guard.emit(
            Equals(guard.parameters.single, const Constant.integer(0)),
          ),
          Jump(zero),
          Jump(nonzero),
        ),
      );
      final a = zero.emit(LoadGlobal(saved)),
          b = nonzero.emit(LoadGlobal(saved));
      zero.finish(Return(a));
      nonzero.finish(Return(b));
      final program = IrProgram(
        [],
        [
          IrFunction(root, [start, guard, zero, nonzero]),
          IrFunction(choose, [entry, success, failed]),
        ],
        globals: [saved],
      );
      FlowEntry invocation(bool ok, int amount) => (
        target: root,
        arguments: [
          FlowValue.constant(Constant.boolean(ok)),
          FlowValue.constant(Constant.integer(amount)),
        ],
      );
      final flow = ProgramFlow(program, [invocation(true, 12)]);
      expect(flow.facts.reachesBlock(zero), isFalse);
      expect(flow.facts.valueOf(b).integers!.constant, 12);
      flow.extend(entries: [invocation(false, 27), invocation(true, 40)]);
      expect(flow.facts.reachesBlock(zero), isTrue);
      expect(flow.facts.valueOf(a).integers!.constant, 5);
      final range = flow.facts.valueOf(b).integers!;
      expect((range.lower, range.upper), (12, 40));
    },
  );
  test('a new guarded reader shares an already published ordinary summary', () {
    final uri = Uri.parse('memory:late-reader');
    final saved = GlobalVariable(uri, 'saved', .integer, isLate: true);
    final choose = FunctionTarget(uri, 'choose', .integer, [.boolean]);
    final entry = Block(choose.parameterTypes),
        success = Block(),
        failed = Block();
    entry.finish(Branch(entry.parameters.single, Jump(success), Jump(failed)));
    success.emit(StoreGlobal(saved, const Constant.integer(37)));
    success.finish(const Return(Constant.integer(8)));
    failed.finish(const Return(Constant.integer(0)));
    final ordinary = FunctionTarget(uri, 'ordinary', .integer, [.boolean]),
        guarded = FunctionTarget(uri, 'guarded', .integer, [.boolean]);
    final first = Block(ordinary.parameterTypes),
        second = Block(guarded.parameterTypes),
        guard = Block([ValueType.integer]),
        zero = Block(),
        nonzero = Block();
    first.emit(StoreGlobal(saved, const Constant.integer(12)));
    final plain = first.emit(DirectCall(choose, first.parameters));
    final merged = first.emit(LoadGlobal(saved));
    first.finish(Return(merged));
    second.emit(StoreGlobal(saved, const Constant.integer(12)));
    final split = second.emit(DirectCall(choose, second.parameters));
    second.finish(Jump(guard, [split]));
    guard.finish(
      Branch(
        guard.emit(Equals(guard.parameters.single, const Constant.integer(0))),
        Jump(zero),
        Jump(nonzero),
      ),
    );
    final a = zero.emit(LoadGlobal(saved)), b = nonzero.emit(LoadGlobal(saved));
    zero.finish(Return(a));
    nonzero.finish(Return(b));
    final f = IrFunction(ordinary, [first]),
        g = IrFunction(guarded, [second, guard, zero, nonzero]);
    final program = IrProgram(
      [],
      [
        IrFunction(choose, [entry, success, failed]),
        f,
        g,
      ],
      globals: [saved],
    );
    FlowEntry root(FunctionTarget target) =>
        (target: target, arguments: [FlowValue.unknown(.boolean)]);
    final flow = ProgramFlow(program, [root(ordinary)]);
    final previous = flow.facts
        .callActivationsOf(
          plain,
          activation: flow.facts.activationsOf(ordinary).single,
        )
        .single;
    expect(
      (
        flow.facts.valueOf(merged).integers!.lower,
        flow.facts.valueOf(merged).integers!.upper,
      ),
      (12, 37),
    );
    flow.extend(entries: [root(guarded)]);
    final reader = flow.facts
        .callActivationsOf(
          split,
          activation: flow.facts.activationsOf(guarded).single,
        )
        .single;
    expect(reader, same(previous));
    final ir = IrInterpreter(program, {});
    for (final root in [f, g]) {
      expect(ir.run(root, [false]), 12);
      expect(ir.run(root, [true]), 37);
    }
    expect(flow.facts.valueOf(plain).integers!.contains(0), isTrue);
    expect(flow.facts.valueOf(plain).integers!.contains(8), isTrue);
    for (final value in [a, b, merged]) {
      final range = flow.facts.valueOf(value).integers!;
      expect((range.lower, range.upper), (12, 37));
    }
  });

  test(
    'a recursive return retains the write performed after the nested call',
    () {
      final uri = Uri.parse('memory:recursive-returns');
      final saved = GlobalVariable(uri, 'saved', .integer, isLate: true);
      final choose = FunctionTarget(uri, 'choose', .integer, [
        .integer,
        .boolean,
      ]);
      final entry = Block(choose.parameterTypes),
          descend = Block(),
          base = Block(),
          success = Block(),
          failed = Block();
      entry.finish(
        Branch(
          entry.emit(
            IntBinary(
              .greaterThan,
              entry.parameters.first,
              const Constant.integer(0),
            ),
          ),
          Jump(descend),
          Jump(base),
        ),
      );
      base.finish(Branch(entry.parameters.last, Jump(success), Jump(failed)));
      success.emit(StoreGlobal(saved, const Constant.integer(37)));
      success.finish(const Return(Constant.integer(8)));
      failed.emit(StoreGlobal(saved, const Constant.integer(12)));
      failed.finish(const Return(Constant.integer(0)));
      final recursive = descend.emit(
        DirectCall(choose, [
          descend.emit(
            IntBinary(
              .subtract,
              entry.parameters.first,
              const Constant.integer(1),
            ),
          ),
          entry.parameters.last,
        ]),
      );
      descend.emit(StoreGlobal(saved, const Constant.integer(99)));
      descend.finish(Return(recursive));
      final root = FunctionTarget(uri, 'root', .integer, [.boolean]);
      final start = Block(root.parameterTypes),
          guard = Block([ValueType.integer]),
          zero = Block(),
          nonzero = Block();
      final result = start.emit(
        DirectCall(choose, [
          const Constant.integer(3),
          start.parameters.single,
        ]),
      );
      start.finish(Jump(guard, [result]));
      guard.finish(
        Branch(
          guard.emit(
            Equals(guard.parameters.single, const Constant.integer(0)),
          ),
          Jump(zero),
          Jump(nonzero),
        ),
      );
      final a = zero.emit(LoadGlobal(saved)),
          b = nonzero.emit(LoadGlobal(saved));
      zero.finish(Return(a));
      nonzero.finish(Return(b));
      final f = IrFunction(root, [start, guard, zero, nonzero]);
      final program = IrProgram(
        [],
        [
          f,
          IrFunction(choose, [entry, descend, base, success, failed]),
        ],
        globals: [saved],
      );
      final ir = IrInterpreter(program, {});
      expect(ir.run(f, [true]), 99);
      expect(ir.run(f, [false]), 99);
      final facts = ProgramFlow(program, [
        (target: root, arguments: [FlowValue.unknown(.boolean)]),
      ]).facts;
      expect(facts.reachesBlock(descend), isTrue);
      expect(facts.reachesBlock(base), isTrue);
      expect(facts.valueOf(a).integers!.constant, 99);
      expect(facts.valueOf(b).integers!.constant, 99);
    },
  );

  test('a returned string distinguishes two independently allocated mutable objects', () {
    final uri = Uri.parse('memory:result-tagged-fresh');
    final box = ClassType(uri, 'Cell');
    final n = InstanceField(box, 'n', .integer, initiallyUnbound: true);
    final saved = GlobalVariable(uri, 'saved', box, isLate: true);
    final choose = FunctionTarget(uri, 'choose', .string, [.boolean]);
    final head = Block(choose.parameterTypes), left = Block(), right = Block();
    head.finish(Branch(head.parameters.single, Jump(left), Jump(right)));
    for (final (block, tag, value) in [(left, 'L', 17), (right, 'R', 89)]) {
      final fresh = block.emit(NewPayload(box, const Constant.integer(0)));
      block.emit(StoreField(n, fresh, Constant.integer(value)));
      block.emit(StoreGlobal(saved, fresh));
      block.finish(Return(Constant.string(tag)));
    }
    final root = FunctionTarget(uri, 'root', .integer, [.boolean]);
    final start = Block(root.parameterTypes),
        guard = Block([ValueType.string]),
        yes = Block(),
        no = Block();
    final call = start.emit(DirectCall(choose, start.parameters));
    start.finish(Jump(guard, [call]));
    guard.finish(
      Branch(
        guard.emit(Equals(guard.parameters.single, const Constant.string('L'))),
        Jump(yes),
        Jump(no),
      ),
    );
    final first = yes.emit(LoadField(n, yes.emit(LoadGlobal(saved))));
    final second = no.emit(LoadField(n, no.emit(LoadGlobal(saved))));
    yes.finish(Return(first));
    no.finish(Return(second));
    final top = IrFunction(root, [start, guard, yes, no]),
        graph = IrProgram(
          [
            IrClass(box, [n]),
          ],
          [
            top,
            IrFunction(choose, [head, left, right]),
          ],
          globals: [saved],
        );
    final ir = IrInterpreter(graph, {});
    final facts = ProgramFlow(graph, [
      (target: root, arguments: [FlowValue.unknown(.boolean)]),
    ]).facts;
    for (final (flag, v) in [(true, first), (false, second)]) {
      final actual = ir.run(top, [flag]);
      expect(facts.valueOf(v).integers!.constant, actual);
    }
  });
}
