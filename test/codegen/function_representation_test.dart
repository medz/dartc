import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/function_representation.dart';
import 'package:dartc/src/codegen/function_liveness.dart';
import 'package:dartc/src/codegen/program_layout.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:representation');
  final layouts = ProgramLayout(IrProgram([], []));

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
}
