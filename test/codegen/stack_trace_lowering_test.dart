import 'package:dartc/codegen.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

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
