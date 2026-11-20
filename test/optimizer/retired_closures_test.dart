import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test('returned and thrown method closures keep their allocation and target across rebinding', () async {
    final graph = await AnalysisSession([
      'test/optimizer/fixtures/retired_closures.dart',
    ]).use((session) async => (await Lowering().lower(session)).program);
    FunctionTarget named(String name) =>
        graph.functions.singleWhere((f) => f.target.name == name).target;
    final left = named('left'),
        right = named('right'),
        thrown = named('thrown'),
        use = named('use'),
        method = named('read');
    final publish = named('publish'), useSaved = named('useSaved');
    final targets = [left, right, thrown, use, publish];
    FlowEntry input(FunctionTarget target, int n) => (
      target: target,
      arguments: [
        FlowValue.constant(Constant.integer(n)),
        FlowValue.unknown(.boolean),
      ],
    );
    final flow = ProgramFlow(
      graph,
      [for (final t in targets) input(t, 11)],
      escapingReturns: [left, right, thrown, publish],
    );
    final first = flow.facts.returnedBy(left).objects.toSet();
    expect(first, isNotEmpty);
    for (final n in [12, 13, 14]) {
      for (final target in targets) {
        flow.extend(entries: [input(target, n)]);
      }
    }
    expect(flow.extend(openEntries: [publish, useSaved]), isTrue);
    for (final target in targets) {
      flow.extend(entries: [input(target, 15)]);
    }
    final facts = flow.facts;
    final savedRead = facts.returnedBy(useSaved).integers!;
    expect(savedRead.contains(-1) && savedRead.contains(11), isTrue);
    expect(facts.returnedBy(left).objects.containsAll(first), isTrue);
    final read = facts.returnedBy(use).integers!;
    expect(read.lower, 11);
    expect(read.contains(15), isTrue);
    for (final target in [use, useSaved]) {
      final body = graph.implementationOf(target) as IrFunction;
      final invocation = [
        for (final block in body.blocks) ...[
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
      ].whereType<FunctionCall>().single;
      expect(facts.targetsOf(invocation), contains(method));
      expect(facts.hasUnknownCall(invocation), isFalse);
    }
    final simplified = const ProgramSimplification().run(facts);
    final specialized = const ProgramCallSpecialization().run(facts);
    for (final (name, program) in [
      ('source', graph),
      ('simplified', simplified),
      ('specialized', specialized),
    ]) {
      final vm = IrInterpreter(program, {});
      Object? run(FunctionTarget t, int n) =>
          vm.run(program.implementationOf(t) as IrFunction, [n, false]);
      final earlier = run(left, 11), later = run(right, 14);
      expect(identical(earlier, run(left, 11)), isFalse, reason: name);
      expect(identical(earlier, later), isFalse, reason: name);
      expect(vm.call(earlier, []), 11);
      expect(vm.call(later, []), 14);
      Object? caught;
      try {
        run(thrown, 13);
      } catch (e) {
        caught = e;
      }
      expect(vm.call(caught, []), 13);
      for (var n = 11; n <= 15; n++) {
        expect(run(use, n), n, reason: name);
      }
      final getSaved = program.implementationOf(useSaved) as IrFunction;
      expect(vm.run(getSaved, []), -1);
      run(publish, 11);
      expect(vm.run(getSaved, []), 11, reason: name);
      run(publish, 15);
      expect(vm.run(getSaved, []), 11, reason: name);
    }
  });
}
