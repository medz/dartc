import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/definite_assignment.dart' as sdk;

void main() {
  late Map<String, IrFunction> functions;
  late FixtureRunner runner;
  setUpAll(() async {
    final program = await CheckedLibraries.read([
      'test/lowering/fixtures/definite_assignment.dart',
    ], Lowering.lower);
    functions = {
      for (final fn in program.functions)
        if (fn.target.enclosing == null) fn.target.name: fn,
    };
    runner = FixtureRunner(program, {});
  });

  void compare(String name, List<Object?> arguments, Object? expected) {
    expect(runner.run(functions[name]!, arguments), expected);
  }

  test('straight-line assignment and nullable defaults', () {
    for (final input in [-10, 0, 10]) {
      compare('straight', [input], sdk.straight(input));
      compare('shadowAssignment', [input], sdk.shadowAssignment(input));
    }
    compare('nullableDefault', [], sdk.nullableDefault());
  });

  test(
    'wildcard declarations retain initializer effects without binding names',
    () {
      compare('wildcardBindings', [99], sdk.wildcardBindings(99));
      compare('wildcardThrow', [], sdk.wildcardThrow());
    },
  );

  test('all branch paths establish final and mutable bindings', () {
    for (final first in [true, false]) {
      compare('branches', [first, 5], sdk.branches(first, 5));
      compare('nullableFinal', [first], sdk.nullableFinal(first));
      compare('returningBranch', [first], sdk.returningBranch(first));
      for (final second in [true, false]) {
        compare('nestedBranches', [
          first,
          second,
        ], sdk.nestedBranches(first, second));
      }
    }
  });

  test('loop and switch exits preserve definite assignments', () {
    for (final input in [-1, 0, 1, 4]) {
      compare('loopAssignment', [input], sdk.loopAssignment(input));
      compare('unusedForBinding', [input], sdk.unusedForBinding(input));
      compare('initializedForBinding', [
        input,
      ], sdk.initializedForBinding(input));
      compare('capturedUninitializedForBinding', [
        input,
      ], sdk.capturedUninitializedForBinding(input));
      compare('breakAssignment', [input], sdk.breakAssignment(input));
      compare('switchAssignment', [input], sdk.switchAssignment(input));
    }
  });

  test('closures share bindings declared without initializers', () {
    for (final first in [true, false]) {
      compare('capturedFinal', [first], sdk.capturedFinal(first));
    }
    for (final input in [-1, 0, 4]) {
      compare('capturedMutable', [input], sdk.capturedMutable(input));
      compare('capturedBeforeAssignment', [
        input,
      ], sdk.capturedBeforeAssignment(input));
    }
  });

  test('catch and finally paths establish assignments', () {
    for (final fail in [true, false]) {
      compare('catchAssignment', [fail], sdk.catchAssignment(fail));
    }
    for (final input in [-1, 0, 4]) {
      compare('finallyAssignment', [input], sdk.finallyAssignment(input));
    }
  });
}
