import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:representation');
  final layouts = ProgramLayout([]);

  test('an earlier boxed argument is live while the next one allocates', () {
    final accept = FunctionTarget(uri, 'accept', .voidType, [.object, .object]);
    final caller = FunctionTarget(uri, 'caller', .voidType, [
      .integer,
      .floating,
    ]);
    final entry = Block(caller.parameterTypes);
    final call = entry.emit(DirectCall(accept, entry.parameters));
    entry.finish(const Return());
    final body = FunctionRepresentation(IrFunction(caller, [entry]), layouts);
    final boxes = body.boxes.keys.toList();
    final flow = FunctionLiveness(body, body.inputsOf, {...boxes, call});
    expect(boxes, hasLength(2));
    expect(flow.acrossCalls[boxes.last], {boxes.first});
    expect(flow.acrossCalls[call], isEmpty);
    expect(body.inputsOf(call), boxes);
    expect(entry.instructions, [call]);
  });

  test('edge conversions are conditional and unused conversions stay dead', () {
    final target = FunctionTarget(uri, 'branch', .integer, [
      .boolean,
      .integer,
    ]);
    final entry = Block(target.parameterTypes),
        taken = Block([.object]),
        other = Block();
    entry.finish(
      Branch(
        entry.parameters[0],
        Jump(taken, [entry.parameters[1]]),
        Jump(other),
      ),
    );
    taken.finish(Return(const Constant.integer(1)));
    other.finish(Return(const Constant.integer(0)));
    final body = FunctionRepresentation(
      IrFunction(target, [entry, taken, other]),
      layouts,
    );
    final flow = FunctionLiveness(body, body.inputsOf, body.boxes.keys.toSet());
    final branch = body.ends[entry] as Branch;
    expect(branch.ifFalse.target, same(other));
    expect(branch.ifTrue.target, isNot(same(taken)));
    expect(body.boxes.keys, hasLength(1));
    expect(flow.omitted, body.introduced);
    expect(flow.acrossCalls, isEmpty);
    expect(flow.liveIn[entry], {entry.parameters.first});
  });

  test(
    'invoke arguments and outcomes convert at their own execution points',
    () {
      final target = FunctionTarget(uri, 'invoke', .object, [.integer]);
      final callee = FunctionTarget(uri, 'callee', .integer, [.object]);
      final handle = FunctionTarget(uri, 'handle', .object, [
        .object,
        .stackTrace,
        .object,
      ]);
      final entry = Block(target.parameterTypes), success = Block([.object]);
      final failure = Block([.object, .stackTrace, .object]);
      final argument = entry.parameters.single;
      final call = DirectCall(callee, [argument]);
      final invoke = Invoke(
        call,
        onReturn: Jump(success, [call]),
        onThrow: Jump(failure, [
          UnwindValue.exception,
          UnwindValue.stackTrace,
          argument,
        ]),
      );
      entry.finish(invoke);
      success.finish(Return(success.parameters.single));
      failure.finish(
        Return(failure.emit(DirectCall(handle, failure.parameters))),
      );
      final body = FunctionRepresentation(
        IrFunction(target, [entry, success, failure]),
        layouts,
      );
      final selected = body.ends[entry] as Invoke;
      final normalEdge = selected.onReturn!.target,
          failedEdge = selected.onThrow.target;
      final inputBox = body.instructions[entry]!.first;
      final normalBox = body.instructions[normalEdge]!.single;
      final failedBox = body.instructions[failedEdge]!.single;
      final flow = FunctionLiveness(body, body.inputsOf, {
        ...body.boxes.keys,
        call,
      });

      expect(body.instructions[entry], [inputBox, call]);
      expect(body.inputsOf(call), [inputBox]);
      expect(body.successors(entry), [selected.onReturn, selected.onThrow]);
      expect(selected.onReturn!.arguments, [call]);
      expect(selected.onThrow.arguments, invoke.onThrow.arguments);
      expect(flow.acrossCalls[call], {argument});
      expect(flow.acrossCalls[normalBox], isEmpty);
      expect(
        flow.acrossCalls[failedBox],
        failedEdge.parameters.take(2).toSet(),
      );
      expect(flow.liveIn[entry], {argument});
      expect(entry.instructions, isEmpty);
      expect(entry.end, same(invoke));
      expect(call.inputs, [argument]);
    },
  );

  test('boxing a thrown scalar keeps an existing trace alive', () {
    final target = FunctionTarget(uri, 'rethrow', .voidType, [
      .integer,
      .stackTrace,
    ]);
    final entry = Block(target.parameterTypes);
    entry.finish(
      Throw(entry.parameters.first, stackTrace: entry.parameters.last),
    );
    final body = FunctionRepresentation(IrFunction(target, [entry]), layouts);
    final box = body.boxes.keys.single;
    final flow = FunctionLiveness(body, body.inputsOf, {box});
    final end = body.ends[entry] as Throw;
    expect(end.exception, same(box));
    expect(end.stackTrace, same(entry.parameters.last));
    expect(flow.acrossCalls[box], {entry.parameters.last});
    expect(flow.liveIn[entry], entry.parameters.toSet());
    expect(entry.instructions, isEmpty);
  });
}
