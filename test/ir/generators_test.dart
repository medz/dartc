import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final target = FunctionTarget(
    Uri.parse('memory:generators'),
    'values',
    CoreTypes.iterableOf(ValueType.integer),
    [ValueType.integer],
  );
  IrFunction generator(List<Block> blocks) =>
      IrFunction(target, blocks, bodyKind: .syncGenerator, yieldType: .integer);

  test('yield is an explicit resumable edge with checked SSA arguments', () {
    final entry = Block(target.parameterTypes);
    final resume = Block([ValueType.integer]);
    entry.finish(
      Yield(entry.parameters.single, Jump(resume, entry.parameters)),
    );
    resume.finish(const Return());
    final function = generator([entry, resume]);
    expect(function.target.returnType, CoreTypes.iterableOf(ValueType.integer));
    expect(function.bodyKind, FunctionBodyKind.syncGenerator);
    expect(entry.successors.single.target, same(resume));
    final output = StringBuffer();
    function.writeTo(output);
    expect(output.toString(), contains('-> Iterable<int> sync*<int>'));
    expect(output.toString(), contains('yield %0 resume b1(%0)'));
  });

  test('mode, element type and callable result must agree', () {
    final entry = Block(target.parameterTypes)..finish(const Return());
    expect(
      () => IrFunction(target, [entry], bodyKind: .syncGenerator),
      throwsArgumentError,
    );
    expect(
      () => IrFunction(target, [entry], yieldType: .integer),
      throwsArgumentError,
    );
    expect(
      () => IrFunction(
        target,
        [entry],
        bodyKind: .syncGenerator,
        yieldType: .string,
      ),
      throwsArgumentError,
    );
    expect(() => IrFunction(target, [entry]), throwsStateError);
    expect(() => generator([entry]), returnsNormally);
    final voidTarget = FunctionTarget(target.library, 'invalid', .voidType, []);
    final voidEntry = Block()..finish(const Return());
    expect(
      () => IrFunction(
        voidTarget,
        [voidEntry],
        bodyKind: .syncGenerator,
        yieldType: .dynamicType,
      ),
      throwsArgumentError,
    );

    final invalid = Block(target.parameterTypes)
      ..finish(Return(const Constant.integer(1)));
    expect(() => generator([invalid]), throwsStateError);
  });

  test('yield rejects ordinary bodies and incompatible element types', () {
    final entry = Block(target.parameterTypes),
        resume = Block()..finish(const Return());
    entry.finish(Yield(const Constant.integer(1), Jump(resume)));
    expect(() => IrFunction(target, [entry, resume]), throwsStateError);
    final wrong = Block(target.parameterTypes)
      ..finish(Yield(const Constant.string('x'), Jump(resume)));
    expect(() => generator([wrong, resume]), throwsStateError);
  });

  test('resume edges preserve reachability and dominance validation', () {
    final entry = Block(target.parameterTypes),
        resume = Block()..finish(const Return());
    entry.finish(Yield(const Constant.integer(1), Jump(resume)));
    expect(() => generator([entry]), throwsStateError);
    final foreign = Block([ValueType.integer]);
    final bad = Block(target.parameterTypes)
      ..finish(Yield(foreign.parameters.single, Jump(resume)));
    expect(() => generator([bad, resume]), throwsStateError);
    final a = Block(target.parameterTypes),
        b = Block(),
        c = Block(),
        done = Block()..finish(const Return());
    a.finish(Branch(const Constant.boolean(true), Jump(b), Jump(c)));
    final local = b.emit(
      IntBinary(.add, const Constant.integer(1), const Constant.integer(2)),
    );
    b.finish(Yield(local, Jump(done)));
    c.finish(Yield(local, Jump(done)));
    expect(() => generator([a, b, c, done]), throwsStateError);
  });

  test('resume arguments cannot use unwind values or foreign definitions', () {
    final entry = Block(target.parameterTypes);
    final resume = Block([ValueType.object])..finish(const Return());
    entry.finish(
      Yield(const Constant.integer(1), Jump(resume, [UnwindValue.exception])),
    );
    expect(() => generator([entry, resume]), throwsStateError);
  });

  test('yield types cannot smuggle storage or unbound type parameters', () {
    final entry = Block(target.parameterTypes)..finish(const Return());
    expect(
      () => IrFunction(
        target,
        [entry],
        bodyKind: .syncGenerator,
        yieldType: CellType(.integer),
      ),
      throwsArgumentError,
    );
    final foreign = TypeParameterType('T')
      ..initializeBound(ValueType.object.nullable);
    final broad = FunctionTarget(target.library, 'broad', .object, []);
    final body = Block()..finish(const Return());
    expect(
      () => IrFunction(
        broad,
        [body],
        bodyKind: .syncGenerator,
        yieldType: foreign,
      ),
      throwsStateError,
    );
  });

  test('a yielded cell is not an ordinary dynamic element', () {
    final broad = FunctionTarget(target.library, 'broad', .object, []);
    final entry = Block(), resume = Block()..finish(const Return());
    final cell = entry.emit(
      NewCell(CellType(.integer), const Constant.integer(1)),
    );
    entry.finish(Yield(cell, Jump(resume)));
    expect(
      () => IrFunction(
        broad,
        [entry, resume],
        bodyKind: .syncGenerator,
        yieldType: .dynamicType,
      ),
      throwsStateError,
    );
  });
}
