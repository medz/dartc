import 'package:dartc/src/_internal/ir/ir.dart';
import 'package:test/test.dart';

void main() {
  final f = FunctionTarget(Uri.parse('memory:test'), 'f', .integer, [.boolean]);
  const one = Constant.integer(1);

  test('a branch-local value cannot escape through the other arm', () {
    final entry = Block(f.parameterTypes),
        yes = Block(),
        no = Block(),
        join = Block();
    entry.finish(Branch(entry.parameters.single, Jump(yes), Jump(no)));
    final temporary = yes.emit(IntBinary(.add, one, one));
    yes.finish(Jump(join));
    no.finish(Jump(join));
    join.finish(Return(temporary));
    expect(() => IrFunction(f, [entry, yes, no, join]), throwsStateError);
  });

  test('uses before definition and foreign block parameters are rejected', () {
    final entry = Block(f.parameterTypes);
    final next = IntBinary(.add, one, one);
    final result = entry.emit(IntBinary(.subtract, next, one));
    entry.emit(next);
    entry.finish(Return(result));
    expect(() => IrFunction(f, [entry]), throwsStateError);

    final foreign = Block([ValueType.integer]);
    final other = Block(f.parameterTypes)
      ..finish(Return(foreign.parameters.single));
    expect(() => IrFunction(f, [other]), throwsStateError);
  });

  test('edges and function returns check arity, type and block membership', () {
    final join = Block([ValueType.integer])..finish(const Return(one));
    expect(() => Jump(join), throwsArgumentError);
    expect(
      () => Jump(join, [const Constant.boolean(true)]),
      throwsArgumentError,
    );
    final entry = Block(f.parameterTypes)..finish(Jump(join, [one]));
    expect(() => IrFunction(f, [entry]), throwsStateError);
    final wrongReturn = Block(f.parameterTypes)..finish(const Return());
    expect(() => IrFunction(f, [wrongReturn]), throwsStateError);
    expect(() => IrFunction(f, [entry, join]), returnsNormally);
    expect(() => join.emit(IntBinary(.add, one, one)), throwsStateError);
  });
}
