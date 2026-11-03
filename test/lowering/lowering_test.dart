import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixtures/conditionals.dart' as conditionals;
import 'fixtures/defaults.dart' as defaults;
import 'fixtures/effects.dart' as effects;
import 'fixtures/functions.dart' as dart;
import 'fixtures/loops.dart' as loops;
import 'fixtures/nullability.dart' as nullable;
import 'fixtures/updates.dart' as updates;

const _fixtures = 'test/lowering/fixtures';

Future<List<IrFunction>> _lower(List<String> names) => CheckedLibraries.read([
  for (final name in names) '$_fixtures/$name',
], Lowering.lower);

void main() {
  late Map<String, IrFunction> functions;
  late Map<FunctionTarget, IrFunction> bodies;
  late Map<FunctionTarget, Object? Function(int)> imports;
  setUpAll(() async {
    final result = await _lower([
      'functions.dart',
      'updates.dart',
      'loops.dart',
      'nullability.dart',
      'conditionals.dart',
      'defaults.dart',
      'scalar_constants.dart',
    ]);
    functions = {for (final f in result) f.target.name: f};
    bodies = {for (final f in result) f.target: f};
    imports = {
      for (final f in result)
        for (final b in f.blocks)
          for (final call in b.instructions.whereType<DirectCall>())
            if (call.target.library.path.endsWith('/effects.dart'))
              call.target: switch (call.target.name) {
                'tick' => effects.tick,
                'probe' => effects.probe,
                _ => throw StateError('Unknown fixture import'),
              },
    };
  });

  Object? execute(IrFunction function, List<Object?> args) {
    final values = <Value, Object?>{};
    Object? read(Value v) => switch (v) {
      Constant(:final value) => value,
      NonNullValue(:final test) => read(test.operand),
      _ => values[v],
    };
    var block = function.entry;
    for (var steps = 0; steps < 1000; steps++) {
      for (final (i, p) in block.parameters.indexed) {
        values[p] = args[i];
      }
      for (final op in block.instructions) {
        switch (op) {
          case NullTest(:final operand, :final negated):
            values[op] = (read(operand) == null) != negated;
          case NullCheck(:final operand):
            values[op] = read(operand)!;
          case IntBinary(:final operator, :final left, :final right):
            final a = read(left) as int, b = read(right) as int;
            values[op] = switch (operator) {
              .add => a + b,
              .subtract => a - b,
              .multiply => a * b,
              .lessThan => a < b,
            };
          case DirectCall(:final target, :final inputs):
            final arguments = inputs.map(read).toList();
            values[op] = bodies.containsKey(target)
                ? execute(bodies[target]!, arguments)
                : imports[target]!(arguments.single as int);
        }
      }
      final end = block.end;
      if (end is Return) return end.value == null ? null : read(end.value!);
      final edge = switch (end) {
        Throw(:final exception) => throw read(exception)!,
        Unreachable() => throw StateError('Reached a Never continuation'),
        Jump() => end,
        Branch() => read(end.condition) as bool ? end.ifTrue : end.ifFalse,
        Return() => throw StateError('Already returned'),
      };
      args = edge.arguments.map(read).toList();
      block = edge.target;
    }
    fail(
      'Fixture did not return in 1000 block visits: ${function.target.name}',
    );
  }

  void compare(String name, List<Object?> args, Object? Function() sdk) {
    (Object?, Object?, List<int>) observe(Object? Function() run) {
      effects.calls.clear();
      try {
        return (run(), null, List.of(effects.calls));
      } catch (e) {
        final error = switch (e) {
          StateError(:final message) => (StateError, message),
          TypeError() => (TypeError, e.toString()),
          _ => e,
        };
        return (null, error, List.of(effects.calls));
      }
    }

    final (expected, expectedError, trace) = observe(sdk);
    final (actual, error, calls) = observe(
      () => execute(functions[name]!, args),
    );
    expect(error, expectedError);
    expect(actual, expected);
    if (expected is double) {
      expect(actual, isA<double>());
      if (expected == 0) {
        expect((actual as double).isNegative, expected.isNegative);
      }
    }
    expect(calls, trace);
  }

  test(
    'short circuit skips calls and propagates exceptions from taken paths',
    () {
      for (final a in [false, true]) {
        for (final b in [false, true]) {
          for (final n in [-1, 0, 1]) {
            compare('gate', [a, b, n], () => dart.gate(a, b, n));
          }
        }
      }
    },
  );
  test(
    'named calls preserve evaluation order and discarded calls still run',
    () {
      for (final n in [-1, 3]) {
        compare('ordered', [n], () => dart.ordered(n));
        compare('discard', [n], () {
          dart.discard(n);
          return null;
        });
        for (final flag in [false, true]) {
          compare('nestedArguments', [
            n,
            flag,
          ], () => dart.nestedArguments(n, flag));
        }
      }
    },
  );
  test('void functions preserve observable return values through calls', () {
    compare('voidResult', [42], () => Function.apply(dart.voidResult, [42]));
    compare('forwardVoid', [42], () => Function.apply(dart.forwardVoid, [42]));
    compare('discard', [42], () => Function.apply(dart.discard, [42]));
  });
  test('loop-carried variables, branch joins and early returns match Dart', () {
    compare('literalBranch', [], dart.literalBranch);
    for (final flag in [false, true]) {
      for (final n in [0, 1, 6]) {
        compare('sum', [n, flag], () => dart.sum(n, flag));
      }
      compare('early', [flag], () => dart.early(flag));
    }
  });
  test(
    'local writes preserve prefix, postfix and compound assignment values',
    () {
      for (final x in [-3, 0, 4, 0x7fffffffffffffff]) {
        compare('readAndWrite', [x], () => updates.readAndWrite(x));
        compare('argumentWrites', [x], () => updates.argumentWrites(x));
      }
    },
  );

  test('short circuit merges only the writes on the executed path', () {
    for (final x in [-1, 0, 4]) {
      compare('knownGuards', [true, x], () => updates.knownGuards(true, x));
    }
    for (final first in [false, true]) {
      for (final second in [false, true]) {
        for (final x in [-1, 0, 4]) {
          compare('shortCircuitWrites', [
            first,
            second,
            x,
          ], () => updates.shortCircuitWrites(first, second, x));
        }
      }
    }
  });

  test('leaving a loop retains the writes made by its final condition', () {
    for (final limit in [-1, 0, 1, 2, 8]) {
      compare('loopWrites', [limit], () => updates.loopWrites(limit));
    }
  });

  test('loop transfers preserve destination locals and effect order', () {
    for (final n in [-1, 0, 1, 3, 5]) {
      compare('whileTransfers', [n], () => loops.whileTransfers(n));
      compare('firstIteration', [n], () => loops.firstIteration(n));
      for (final stop in [false, true]) {
        compare('doTransfers', [n, stop], () => loops.doTransfers(n, stop));
        compare('forever', [n, stop], () => loops.forever(n, stop));
      }
      for (final stop in [0, 15, 500]) {
        compare('nestedTransfers', [
          n,
          stop,
        ], () => loops.nestedTransfers(n, stop));
      }
    }
  });

  test('conditional expressions merge only the selected values and writes', () {
    for (final first in [true, false]) {
      for (final n in [-1, 0, 2, 4]) {
        for (final second in [true, false]) {
          compare('chooseArm', [
            first,
            second,
            n,
          ], () => conditionals.chooseArm(first, second, n));
        }
        for (final (name, reference) in [
          ('chooseVoid', conditionals.chooseVoid),
          ('localVoid', conditionals.localVoid),
        ]) {
          final args = [first, n];
          compare(name, args, () => Function.apply(reference, args));
        }
      }
    }
  });

  test('omitted arguments use the declaration constant, explicit arguments keep source order', () {
    compare('minInt', [], defaults.minInt);
    compare('fallthrough', [], defaults.fallthrough);
    for (final flag in [true, false]) {
      compare('pickText', [flag], () => defaults.pickText(flag));
      compare('pickNull', [
        flag,
      ], () => Function.apply(defaults.pickNull, [flag]));
      for (final n in [-1, 0, 2]) {
        compare('callDefaults', [
          flag,
          n,
        ], () => defaults.callDefaults(flag, n));
      }
    }
    for (final n in [-1, 0, 2]) {
      compare('pickNumber', [n], () => defaults.pickNumber(n));
    }
  });

  test(
    'nullable operands evaluate once and only a null value takes the fallback',
    () {
      for (final a in [null, 0, 3]) {
        for (final b in [null, 4]) {
          compare('reassigned', [a, b], () => nullable.reassigned(a, b));
          for (final n in [-1, 2]) {
            compare('fallback', [a, b, n], () => nullable.fallback(a, b, n));
            compare('assign', [a, b, n], () => nullable.assign(a, b, n));
          }
        }
        compare('promoted', [a], () => nullable.promoted(a));
        compare('checked', [a], () => nullable.checked(a));
        compare('nullableDefault', [a], () => nullable.nullableDefault(a));
        compare('mixed', [a], () => nullable.mixed(a));
        compare('different', [a], () => nullable.different(a));
        for (final enabled in [false, true]) {
          compare('sibling', [a, enabled], () => nullable.sibling(a, enabled));
          compare('abrupt', [a, enabled], () => nullable.abrupt(a, enabled));
          compare('abruptInLoop', [
            a,
            enabled,
          ], () => nullable.abruptInLoop(a, enabled));
        }
      }
      final guarded = functions['promoted']!.blocks.expand(
        (b) => b.instructions,
      );
      expect(guarded.whereType<NullTest>(), hasLength(1));
      expect(guarded.whereType<NullCheck>(), isEmpty);
    },
  );

  for (final (file, line) in [
    ('index_update.dart', 3),
    ('lazy.dart', 2),
    ('deferred_constant.dart', 3),
    ('object_default.dart', 1),
  ]) {
    test('reports the unsupported operation in $file at its source', () async {
      await expectLater(
        _lower([file]),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'location',
            contains('$file:$line:'),
          ),
        ),
      );
    });
  }

  test('an unused invalid declaration in a part prevents lowering', () async {
    await expectLater(
      _lower(['invalid_part/entry.dart']),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'diagnostic location',
          contains('other.dart'),
        ),
      ),
    );
  });

  test('different libraries can bind functions with the same name', () async {
    final [client, left, right] = await _lower([
      'package/entry.dart',
      'dependency/lib/left.dart',
      'dependency/lib/right.dart',
    ]);
    final calls = client.entry.instructions.whereType<DirectCall>();
    expect(calls.map((c) => c.target), [same(left.target), same(right.target)]);
    expect(left.target.library, Uri.parse('package:demo/left.dart'));
    expect(right.target.library, Uri.parse('package:demo/right.dart'));
    await expectLater(
      _lower(['package/entry.dart', 'package/entry.dart']),
      throwsArgumentError,
    );
  });

  test('package language version gates syntax in imported libraries', () async {
    await expectLater(
      _lower([
        'package/use_newer_syntax.dart',
        'dependency/lib/newer_syntax.dart',
      ]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'diagnostic location',
          contains('newer_syntax.dart'),
        ),
      ),
    );
  });
}
