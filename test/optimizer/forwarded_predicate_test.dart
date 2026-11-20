import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  for (final independent in [false, true]) {
    test(
      'a forwarded comparison bounds its index (independent=$independent)',
      () {
        final guard = FunctionTarget(null, 'guard', .integer, [
          .integer,
          .integer,
          .boolean,
        ]);
        final entry = Block(guard.parameterTypes);
        final index = entry.parameters[0], length = entry.parameters[1];
        final second = Block(),
            alternative = Block(),
            forwarded = Block([.boolean]);
        final success = Block(), failure = Block();
        final negative = entry.emit(
          IntBinary(.lessThan, index, const Constant.integer(0)),
        );
        entry.finish(Branch(negative, Jump(failure), Jump(second)));
        final exceeds = second.emit(IntBinary(.greaterOrEqual, index, length));
        if (independent) {
          second.finish(
            Branch(
              entry.parameters[2],
              Jump(alternative),
              Jump(forwarded, [exceeds]),
            ),
          );
          alternative.finish(Jump(forwarded, [const Constant.boolean(false)]));
        } else {
          second.finish(Jump(forwarded, [exceeds]));
        }
        forwarded.finish(
          Branch(forwarded.parameters.single, Jump(failure), Jump(success)),
        );
        success.finish(Return(index));
        failure.finish(Throw(const Constant.integer(-1)));
        final program = IrProgram([], [
          IrFunction(guard, [
            entry,
            second,
            if (independent) alternative,
            forwarded,
            success,
            failure,
          ]),
        ]);
        final facts = ProgramFlow(program, [
          (
            target: guard,
            arguments: [
              FlowValue.unknown(.integer),
              FlowValue.constant(const Constant.integer(8)),
              FlowValue.unknown(.boolean),
            ],
          ),
        ]).facts;
        expect(facts.thrownBy(guard).exception.integers?.constant, -1);
        final range = facts.returnedBy(guard).integers;
        expect(
          (range?.lower, range?.upper),
          (0, independent ? FlowIntegerRange.maximum : 7),
        );
      },
    );
  }

  test('a saved comparison cannot constrain the next iteration index', () {
    final target = FunctionTarget(null, 'previous', .integer, [.integer]);
    final entry = Block(target.parameterTypes);
    final header = Block([.integer, .boolean]), body = Block(), exit = Block();
    entry.finish(
      Jump(header, [entry.parameters.single, const Constant.boolean(false)]),
    );
    final current = header.parameters.first, previous = header.parameters.last;
    header.finish(Branch(previous, Jump(exit), Jump(body)));
    final comparison = body.emit(
      IntBinary(.lessThan, current, const Constant.integer(0)),
    );
    body.finish(Jump(header, [const Constant.integer(7), comparison]));
    exit.finish(Return(current));
    final program = IrProgram([], [
      IrFunction(target, [entry, header, body, exit]),
    ]);
    final facts = ProgramFlow(program, [
      (
        target: target,
        arguments: [FlowValue.constant(const Constant.integer(-1))],
      ),
    ]).facts;
    expect(facts.returnedBy(target).integers?.contains(7), isTrue);
  });
}
