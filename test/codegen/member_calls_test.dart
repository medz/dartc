import 'package:dartc/ir.dart';
import 'package:dartc/src/codegen/member_calls.dart';
import 'package:test/test.dart';

void main() {
  test('generic collection calls exclude unrelated constructed classes', () {
    final list = ClassType(
      null,
      'Items',
      interfaces: [CoreTypes.listOf(.integer)],
    );
    final unrelated = ClassType(null, 'Unrelated');
    final write = FunctionTarget(
      null,
      '[]=',
      .voidType,
      [.integer, .integer],
      owner: list,
      kind: .method,
    );
    final body = IrFunction(write, [
      Block(write.parameterTypes)..finish(const Return()),
    ]);
    final element = TypeParameterType('E')..initializeBound(.number);
    final parameter = TypeParameterType('L')
      ..initializeBound(CoreTypes.listOf(element));
    final program = IrProgram(
      [
        IrClass(list, [], members: [write]),
        IrClass(unrelated, []),
      ],
      [body],
    );
    final calls = MemberCalls(
      program,
      {write},
      instantiatedTypes: [list, unrelated],
    );
    expect(calls.targetsFor(parameter, write.selector), {list: write});
    expect(calls.targetsFor(parameter.nonNullable, write.selector), {
      list: write,
    });
  });
}
