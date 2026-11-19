import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

void main() {
  test('removing the last caller releases an internally recursive graph', () {
    final uri = Uri.parse('memory:retired-cycle');
    FunctionTarget target(String name) =>
        FunctionTarget(uri, name, .integer, [.integer, .boolean]);
    final loop = target('loop'), wrapper = target('wrapper');
    final roots = [target('left'), target('right')];
    final start = Block(loop.parameterTypes), recur = Block(), done = Block();
    start.finish(Branch(start.parameters[1], Jump(recur), Jump(done)));
    final again = recur.emit(DirectCall(loop, start.parameters));
    recur.finish(Return(again));
    done.finish(Return(start.parameters.first));
    final forward = Block(wrapper.parameterTypes);
    final via = forward.emit(DirectCall(loop, forward.parameters));
    forward.finish(Return(via));
    final graph = <FunctionTarget, List<(Instruction, FunctionTarget)>>{
      wrapper: [(via, loop)],
      loop: [(again, loop)],
    };
    final functions = [
      IrFunction(loop, [start, recur, done]),
      IrFunction(wrapper, [forward]),
    ];
    for (final root in roots) {
      final b = Block(root.parameterTypes);
      final call = b.emit(DirectCall(wrapper, b.parameters));
      b.finish(Return(call));
      functions.add(IrFunction(root, [b]));
      graph[root] = [(call, wrapper)];
    }
    final program = IrProgram([], functions);
    FlowEntry input(FunctionTarget r, int x) => (
      target: r,
      arguments: [
        FlowValue.constant(Constant.integer(x)),
        FlowValue.unknown(.boolean),
      ],
    );
    final flow = ProgramFlow(program, [for (final r in roots) input(r, 11)]);
    void verify() {
      final facts = flow.facts, live = <Object>{};
      final work = [for (final r in roots) (r, facts.activationsOf(r).single)];
      for (var i = 0; i < work.length; i++) {
        final (target, activation) = work[i];
        if (!live.add(activation)) continue;
        for (final (op, callee) in graph[target]!) {
          for (final next in facts.callActivationsOf(
            op,
            activation: activation,
          )) {
            work.add((callee, next));
          }
        }
      }
      for (final target in graph.keys) {
        final retained = facts.activationsOf(target).toSet();
        expect(
          retained.difference(live),
          isEmpty,
          reason:
              'Detached ${target.name}: ${retained.difference(live).length} of ${retained.length}',
        );
      }
    }

    verify();
    for (final x in [12, 13, 14]) {
      for (final root in roots) {
        flow.extend(entries: [input(root, x)]);
        expect(flow.facts.returnedBy(root).integers?.lower, 11);
        expect(flow.facts.returnedBy(root).integers?.upper, x);
        verify();
      }
    }
  });
}
