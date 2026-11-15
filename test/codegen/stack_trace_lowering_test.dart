import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  final trace = ClassType(null, 'Trace', interfaces: [ValueType.stackTrace]);
  final walker = FunctionTarget(null, 'walk', .stackTrace, [
    .integer,
    .integer,
  ]);
  final captured = ObjectConstant(trace, {});
  final walk = IrFunction(walker, [
    Block(walker.parameterTypes)..finish(Return(captured)),
  ]);
  final capture = FunctionTarget(null, 'capture', .stackTrace, []);
  IrFunction snapshot() {
    final entry = Block();
    entry.finish(Return(entry.emit(CaptureStackTrace())));
    return IrFunction(capture, [entry]);
  }

  test('unobserved snapshots disappear before runtime expansion', () {
    final root = FunctionTarget(null, 'root', .integer, []);
    final entry = Block();
    entry.emit(DirectCall(capture, []));
    entry.finish(const Return(Constant.integer(42)));
    final program = IrProgram(
      [IrClass(trace, [])],
      [
        IrFunction(root, [entry]),
        snapshot(),
        walk,
      ],
    );
    final facts = ProgramOptimizer([
      const ProgramSimplification(),
      const DirectCallInlining(maxCalleeCost: 1000),
      StackTraceLowering(walker),
    ]).run(program, [(target: root, arguments: [])]);
    expect(facts.definitions, {root});
    final body = facts.program.implementationOf(root) as IrFunction;
    expect(body.entry.instructions, isEmpty);
    expect((body.entry.end as Return).value, const Constant.integer(42));
  });

  test('retained snapshots pass frame values to the ordinary Dart walker', () {
    final program = IrProgram([IrClass(trace, [])], [snapshot(), walk]);
    final lowered = StackTraceLowering(walker).lower(program);
    final body = lowered.implementationOf(capture) as IrFunction;
    final call = body.entry.instructions.whereType<DirectCall>().single;
    expect(call.target, same(walker));
    expect(call.inputs.cast<FrameValue>().map((value) => value.kind), [
      FrameValueKind.callerStackPointer,
      FrameValueKind.returnAddress,
    ]);
    expect(StackTraceLowering(walker).lower(lowered), same(lowered));
    expect(
      ProgramFlow(lowered, [
        (target: capture, arguments: []),
      ]).facts.definitions,
      {capture, walker},
    );
  });

  for (final operationKind in ['call', 'snapshot', 'payload']) {
    for (final fails in [false, true]) {
      test(
        '$operationKind preserves storage on a retained allocation failure ($fails)',
        () {
          final allocator = FunctionTarget(null, 'allocate', trace, [.integer]);
          final allocationBody = IrFunction(allocator, [
            Block(allocator.parameterTypes)..finish(
              fails
                  ? Throw(const Constant.string('allocation failed'))
                  : Return(captured),
            ),
          ]);
          final failingWalker = IrFunction(walker, [
            Block(walker.parameterTypes)..finish(
              fails
                  ? Throw(const Constant.string('capture failed'))
                  : Return(captured),
            ),
          ]);
          final root = FunctionTarget(null, 'root', .object, [.object]);
          final entry = Block(root.parameterTypes);
          final saved = entry.emit(
            NewCell(CellType(.object), const Constant.string('old')),
          );
          entry.emit(WriteCell(saved, entry.parameters.single));
          final Instruction allocation = switch (operationKind) {
            'call' => DirectCall(capture, []),
            'snapshot' => CaptureStackTrace(),
            _ => NewPayload(trace, const Constant.integer(0)),
          };
          final done = Block([allocation.type]), handler = Block();
          entry.finish(
            Invoke(
              allocation,
              onReturn: Jump(done, [allocation]),
              onThrow: Jump(handler),
            ),
          );
          done.finish(Return(done.parameters.single));
          handler.finish(Return(handler.emit(ReadCell(saved))));
          final source = IrProgram(
            [IrClass(trace, [])],
            [
              IrFunction(root, [entry, done, handler]),
              snapshot(),
              failingWalker,
              allocationBody,
            ],
          );
          const passes = <ProgramPass>[
            ProgramSimplification(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            DirectCallInlining(),
          ];
          final roots = [
            (target: root, arguments: [FlowValue.unknown(.object)]),
          ];
          final before = ProgramFlow(source, roots).facts;
          expect(before.canDiscard(allocation), isTrue);
          expect(before.exitsOf(allocation), (normal: true, exceptional: true));
          expect(before.reachesBlock(handler), isTrue);
          final shrunk = ProgramOptimizer(passes).run(source, roots).program;
          final expanded = operationKind == 'payload'
              ? IrProgram(shrunk.classes, [
                  for (final function in shrunk.functions)
                    FunctionRewrite(
                      function,
                      operations: {
                        for (final block in function.blocks)
                          if (block.end case Invoke(
                            operation: final NewPayload value,
                          ))
                            value: DirectCall(allocator, [value.bytes]),
                      },
                    ).run(),
                ])
              : StackTraceLowering(walker).lower(shrunk);
          final after = ProgramOptimizer(passes).run(expanded, roots).program;
          for (final program in [expanded, after]) {
            // This walker ignores PCs; the interpreter has no machine frame.
            final executable = IrProgram(program.classes, [
              for (final function in program.functions)
                FunctionRewrite(
                  function,
                  replacements: {
                    for (final block in function.blocks)
                      for (final operation in block.instructions)
                        if (operation is FrameValue)
                          operation: const Constant.integer(0),
                  },
                ).run(),
            ]);
            for (final sentinel in ['saved', '', Object()]) {
              final result = IrInterpreter(executable, {}).run(
                executable.implementationOf(root) as IrFunction,
                [sentinel],
              );
              if (fails) {
                expect(result, same(sentinel));
              } else {
                expect(IrInterpreter.exceptionType(result!), same(trace));
              }
            }
          }
        },
      );
    }
  }

  test('snapshot and frame reads preserve their owning call boundary', () {
    for (final value in <Instruction>[
      CaptureStackTrace(),
      for (final kind in FrameValueKind.values) FrameValue(kind),
    ]) {
      final target = FunctionTarget(null, 'observe', value.type, []);
      final entry = Block()..emit(value);
      entry.finish(Return(value));
      final root = FunctionTarget(null, 'root', value.type, []);
      final caller = Block();
      caller.finish(Return(caller.emit(DirectCall(target, []))));
      final source = IrFunction(target, [entry]);
      final calling = IrFunction(root, [caller]);
      final program = IrProgram([], [calling, source]);
      expect(
        () => FunctionRewrite(
          calling,
          inlined: {
            caller.instructions.single: (
              body: source,
              arguments: const [],
              environment: const {},
              handler: null,
            ),
          },
        ).run(),
        throwsArgumentError,
      );
      final facts = ProgramFlow(program, [(target: root, arguments: [])]).facts;
      final after = const DirectCallInlining(maxCalleeCost: 1000).run(facts);
      final body = after.implementationOf(root) as IrFunction;
      expect(
        body.entry.instructions.whereType<DirectCall>().single.target,
        same(target),
      );
      expect(value.mapInputs((input) => input).runtimeType, value.runtimeType);
    }
  });
}
