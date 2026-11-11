import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/callables.dart' as callables;
import 'fixtures/closures.dart' as closures;
import 'fixtures/conditionals.dart' as conditionals;
import 'fixtures/defaults.dart' as defaults;
import 'fixtures/destructure.dart' as destructure;
import 'fixtures/effects.dart' as effects;
import 'fixtures/exceptions.dart' as exceptions;
import 'fixtures/extension_operator.dart' as extension_operator;
import 'fixtures/finalizers.dart' as finalizers;
import 'fixtures/functions.dart' as dart;
import 'fixtures/index_update.dart' as index_update;
import 'fixtures/loops.dart' as loops;
import 'fixtures/lazy.dart' as lazy;
import 'fixtures/nominal/constructors.dart' as nominal;
import 'fixtures/nominal/factories.dart' as factories;
import 'fixtures/nominal/members.dart' as members;
import 'fixtures/nominal/updates.dart' as object_updates;
import 'fixtures/nullability.dart' as nullable;
import 'fixtures/patterns.dart' as patterns;
import 'fixtures/records.dart' as records;
import 'fixtures/switch_statements.dart' as switches;
import 'fixtures/type_checks.dart' as types;
import 'fixtures/updates.dart' as updates;

const _fixtures = 'test/frontend/lowering/fixtures';

Future<IrProgram> _lower(List<String> names) =>
    AnalysisSession([for (final name in names) '$_fixtures/$name'])
        .use((input) async => (await Lowering().lower(input)).program);

void main() {
  late Map<String, IrFunction> functions;
  late IrInterpreter runner;
  setUpAll(() async {
    final result = await _lower([
      'functions.dart',
      'callables.dart',
      'closures.dart',
      'updates.dart',
      'loops.dart',
      'nullability.dart',
      'patterns.dart',
      'records.dart',
      'switch_statements.dart',
      'type_checks.dart',
      'conditionals.dart',
      'defaults.dart',
      'destructure.dart',
      'exceptions.dart',
      'finalizers.dart',
      'nominal/constructors.dart',
      'nominal/factories.dart',
      'nominal/members.dart',
      'nominal/updates.dart',
      'nominal/other.dart',
      'scalar_constants.dart',
    ]);
    functions = {
      for (final f in result.functions)
        if (f.target.owner == null && f.target.enclosing == null)
          f.target.name: f,
    };
    final library = Uri.base.resolve('$_fixtures/effects.dart');
    runner = IrInterpreter(result, {
      (library, 'tick'): effects.tick,
      (library, 'probe'): effects.probe,
    });
  });

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
      () => runner.run(functions[name]!, args),
    );
    expect(error, expectedError);
    if (expected is double && expected.isNaN) {
      expect(actual, isNaN);
    } else {
      expect(actual, expected);
    }
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
      expect(guarded.whereType<TypeTest>(), hasLength(1));
      expect(guarded.whereType<NullCheck>(), isEmpty);
    },
  );

  test(
    'type tests narrow the selected arm and casts throw before later effects',
    () {
      for (final value in [null, 4, 1.5, 'hello', false, <int>[]]) {
        compare('classify', [value], () => types.classify(value));
        compare('nestedTest', [value], () => types.nestedTest(value));
        compare('castBeforeCall', [value], () => types.castBeforeCall(value));
        compare('impossible', [value], () => types.impossible(value));
        for (final string in [false, true]) {
          compare('nullableCast', [
            value,
            string,
          ], () => types.nullableCast(value, string));
        }
      }
      final ops = functions['nestedTest']!.blocks.expand((b) => b.instructions);
      expect(ops.whereType<TypeCast>(), isEmpty);
    },
  );

  test('patterns share bindings only after a match and preserve effects of failed guards', () {
    for (final x in [
      null,
      -1,
      0,
      2,
      8,
      1.0,
      1.5,
      double.nan,
      'yes',
      false,
      _UnexpectedEquality(),
    ]) {
      for (final initial in [0, 3]) {
        compare('matchCases', [
          x,
          initial,
        ], () => patterns.matchCases(x, initial));
        compare('matchIf', [x, initial], () => patterns.matchIf(x, initial));
      }
      compare('checkedPattern', [x], () => patterns.checkedPattern(x));
      compare('alternatives', [x], () => patterns.alternatives(x));
    }
    for (final flag in [null, false, true]) {
      compare('exhaustive', [flag], () => patterns.exhaustive(flag));
      if (flag != null) {
        compare('throwCase', [flag], () => patterns.throwCase(flag));
      }
    }
  });

  test(
    'switch statements share case bodies and continue directly to labels',
    () {
      for (final n in [-1, 0, 1, 3]) {
        for (final x in [null, -2, 0, 3, 1.5, 'hit', 'miss', true, false]) {
          compare('shared', [x, n], () => switches.shared(x, n));
        }
      }
      for (final x in [-1, 0, 1, 2, 3, 4, 9]) {
        compare('partial', [x], () => switches.partial(x));
        for (final stop in [true, false]) {
          compare('labels', [x, stop], () => switches.labels(x, stop));
        }
      }
      for (final flag in [true, false, null]) {
        compare('allFlags', [flag], () => switches.allFlags(flag));
      }
      for (final number in [3, -1, 0.5, double.nan]) {
        compare('allNumbers', [number], () => switches.allNumbers(number));
      }
    },
  );

  test(
    'record fields preserve source order, structural types and null-shortening',
    () {
      compare('constantRecord', [], records.constantRecord);
      compare('castRecord', [3], () => records.castRecord(3));
      for (final run in [
        () => records.castRecord('wrong'),
        () => runner.run(functions['castRecord']!, ['wrong']),
      ]) {
        effects.calls.clear();
        expect(run, throwsA(isA<TypeError>()));
        expect(effects.calls, [7]);
      }
      for (final n in [-1, 0, 4]) {
        compare('fieldOrder', [n], () => records.fieldOrder(n));
        compare('stopInMiddle', [n], () => records.stopInMiddle(n));
        compare('unusualNames', [n], () => records.unusualNames(n));
      }
      for (final value in [null, 2, 1.5, 'ok', _UnexpectedEquality()]) {
        for (final flag in [false, true]) {
          compare('recordShape', [
            value,
            flag,
          ], () => records.recordShape(value, flag));
        }
        compare('equalFields', [value, 2], () => records.equalFields(value, 2));
      }
      for (final n in [null, 3]) {
        for (final missing in [false, true]) {
          compare('shortChain', [
            missing,
            n,
          ], () => records.shortChain(missing, n));
          compare('parenthesized', [
            missing,
            n,
          ], () => records.parenthesized(missing, n));
        }
      }
      for (final empty in [true, false]) {
        compare('emptyOrSingleton', [
          empty,
        ], () => records.emptyOrSingleton(empty));
      }
    },
  );

  test('record patterns preserve field order, staged assignment and alternative bindings', () {
    for (final n in [-1, 0, 2, 6]) {
      compare('namedBindings', [n], () => destructure.namedBindings(n));
      compare('loopBindings', [n], () => destructure.loopBindings(n));
      for (final (a, b) in [(0, 3), (4, 0), (0, 0), (2, 3), (-1, 4)]) {
        compare('swap', [a, b], () => destructure.swap(a, b));
        compare('chooseField', [
          a,
          b,
          n,
        ], () => destructure.chooseField(a, b, n));
      }
    }
    for (final kind in [0, 1, 2, 3]) {
      for (final value in [null, 3, 4, 'x']) {
        compare('matchShape', [
          kind,
          value,
        ], () => destructure.matchShape(kind, value));
      }
    }
    for (final flag in [false, true]) {
      for (final value in [null, 1, 'x']) {
        compare('patternOrder', [
          flag,
          value,
        ], () => destructure.patternOrder(flag, value));
      }
      for (final b in [null, false, true]) {
        compare('exhaustivePair', [
          flag,
          b,
        ], () => destructure.exhaustivePair(flag, b));
      }
    }
  });

  test(
    'handlers see writes at the throw site and rethrow the original exception',
    () {
      for (final n in [-1, 0, 1, 4]) {
        compare('siteLocals', [n], () => exceptions.siteLocals(n));
      }
      for (final value in [null, 8]) {
        compare('atomic', [3, 4, value], () => exceptions.atomic(3, 4, value));
      }
      for (final value in [3, 'message', false]) {
        for (final again in [true, false]) {
          compare('filter', [
            value,
            again,
          ], () => exceptions.filter(value, again));
        }
        compare('sameThrow', [value], () => exceptions.sameThrow(value));
      }
      for (final value in [null, 2, 3, 'other', _UnexpectedEquality()]) {
        compare('implicitThrow', [
          value,
          2,
        ], () => exceptions.implicitThrow(value, 2));
      }
    },
  );

  test(
    'finally preserves or replaces the pending return, exception or jump',
    () {
      for (final n in [-5, -1, 0, 1, 4]) {
        compare('savedReturn', [n], () => finalizers.savedReturn(n));
        compare('forwardThroughCleanup', [
          n,
        ], () => Function.apply(finalizers.forwardThroughCleanup, [n]));
        compare('loopExits', [n], () => finalizers.loopExits(n));
        compare('toCase', [n], () => finalizers.toCase(n));
      }
      for (final kind in [0, 1, 2]) {
        compare('replaceReturnWithJump', [
          kind,
        ], () => finalizers.replaceReturnWithJump(kind));
      }
      for (final stop in [true, false]) {
        compare('leaveTry', [stop], () => finalizers.leaveTry(stop));
      }
      for (final action in [-1, 0, 1, 2]) {
        for (final replace in [-1, 0, 1, 2]) {
          compare('overrideCompletion', [
            action,
            replace,
          ], () => finalizers.overrideCompletion(action, replace));
        }
      }
    },
  );

  test('constructors share nominal identities and initialize each instance in order', () {
    for (final n in [-1, 0, 3]) {
      compare('construct', [n], () => nominal.construct(n));
      compare('primary', [n], () => nominal.primary(n));
      compare('inheritedDefault', [n], () => nominal.inheritedDefault(n));
      compare('exhaustiveGeneric', [n], () => nominal.exhaustiveGeneric(n));
    }
    for (final flag in [false, true]) {
      compare('separateLibraries', [
        flag,
      ], () => nominal.separateLibraries(flag));
      compare('typedException', [flag], () => nominal.typedException(flag));
      compare('exhaustiveChoice', [flag], () => nominal.exhaustiveChoice(flag));
    }
  });

  test('virtual calls bind defaults to the selected implementation and keep private selectors separate', () {
    compare('hiddenMembers', [], members.hiddenMembers);
    for (final flag in [false, true]) {
      for (final n in [-1, 0, 3]) {
        compare('selected', [flag, n], () => members.selected(flag, n));
        compare('optionalMember', [
          flag,
          n,
        ], () => members.optionalMember(flag, n));
        compare('equalTokens', [n, 3], () => members.equalTokens(n, 3));
      }
    }
    for (final value in [3, 'wrong']) {
      compare('promotedField', [value], () => members.promotedField(value));
      compare('checkedArgument', [value], () => members.checkedArgument(value));
    }
  });

  test('property and index updates preserve evaluation, shorting and assignment results', () {
    for (final n in [-4, -1, 0, 3]) {
      for (final mode in [0, 1, 2, 3, 4, 5]) {
        compare('locations', [
          n,
          mode,
        ], () => object_updates.locations(n, mode));
      }
      for (final missing in [false, true]) {
        for (final initial in [null, 4]) {
          compare('optionalWrite', [
            missing,
            initial,
            n,
          ], () => object_updates.optionalWrite(missing, initial, n));
        }
      }
      compare('overloaded', [n], () => object_updates.overloaded(n));
      for (final b in [-1, 0, 2, 63, 65]) {
        compare('integerOps', [n, b], () => object_updates.integerOps(n, b));
        compare('quotient', [n, b], () => object_updates.quotient(n, b));
      }
    }
    for (final other in [null, 1, 'x']) {
      compare('compareSuper', [
        other,
      ], () => object_updates.compareSuper(other));
    }
  });

  test('factory redirects preserve omitted arguments through a chain', () {
    for (final mode in [0, 1, 2, 3, 4, 5]) {
      for (final n in [-1, 0, 6]) {
        compare('redirected', [mode, n], () => factories.redirected(mode, n));
      }
    }
  });

  test(
    'tear-offs retain their receiver, call shape, defaults and equality',
    () {
      for (final mode in [0, 1, 2, 3, 4]) {
        for (final n in [-1, 0, 3]) {
          compare('indirect', [mode, n], () => callables.indirect(mode, n));
        }
        compare('sameMethods', [mode], () => callables.sameMethods(mode));
      }
      compare('sameCallable', [], callables.sameCallable);
      compare('selfDefault', [], callables.selfDefault);
      for (final n in [-1, 4]) {
        compare('parenthesizedGetter', [
          n,
        ], () => callables.parenthesizedGetter(n));
        compare('getterCall', [n], () => callables.getterCall(n));
        compare('objectCall', [n], () => callables.objectCall(n));
      }
      for (final x in [null, 4, 'x']) {
        compare('covariantValue', [x], () => callables.covariantValue(x));
      }
      for (final flag in [false, true]) {
        compare('factoryValue', [flag], () => callables.factoryValue(flag));
        for (final n in [-1, 4]) {
          compare('selectedCall', [
            flag,
            n,
          ], () => callables.selectedCall(flag, n));
        }
      }
    },
  );

  test('lexical closures preserve shared variables, receivers and per-iteration bindings', () {
    compare('updateBindings', [], closures.updateBindings);
    for (final n in [-1, 0, 2, 4]) {
      compare('sharedCounter', [n], () => closures.sharedCounter(n));
      compare('transitive', [n], () => closures.transitive(n));
      compare('recursive', [n], () => closures.recursive(n));
      compare('destructuredLoop', [n], () => closures.destructuredLoop(n));
      compare('capturedReceiver', [n], () => closures.capturedReceiver(n));
      compare('capturedSuperGetter', [
        n,
      ], () => closures.capturedSuperGetter(n));
      compare('inConstructors', [n], () => closures.inConstructors(n));
      compare('inGuards', [n], () => closures.inGuards(n));
      compare('scoped', [n], () => closures.scoped(n));
    }
    for (final flag in [false, true]) {
      compare('afterExit', [flag], () => closures.afterExit(flag));
      compare('iteration', [flag], () => closures.iteration(flag));
    }
  });

  test('updates imported global storage through its linked accessor', () async {
    final program = await _lower(['index_update.dart', 'effects.dart']);
    final linked = IrInterpreter(program, {});
    final tick = program.functions.singleWhere((f) => f.target.name == 'tick');
    final update = program.functions.singleWhere(
      (f) => f.target.name == 'updateFirst',
    );
    effects.calls.clear();
    expect(linked.run(tick, [7]), effects.tick(7));
    for (var i = 0; i < 3; i++) {
      expect(linked.run(update, []), index_update.updateFirst());
    }
  });

  test('lowers the original lazy local fixture', () async {
    final program = await _lower(['lazy.dart']);
    final function = program.functions.singleWhere((f) => f.target.name == 'f');
    expect(IrInterpreter(program, {}).run(function, []), lazy.f());
  });

  test(
    'extension operator uses the receiver static view and direct ABI',
    () async {
      final program = await _lower(['extension_operator.dart']);
      final function = program.functions.singleWhere(
        (f) => f.target.name == 'compareAsObject',
      );
      final runner = IrInterpreter(program, {});
      for (final seed in [-1, 0, 7]) {
        expect(
          runner.run(function, [seed]),
          extension_operator.compareAsObject(seed),
        );
      }
      final instructions = function.blocks
          .expand((b) => b.instructions)
          .toList();
      expect(instructions.whereType<InstanceCall>(), isEmpty);
      final call = instructions.whereType<DirectCall>().single;
      expect(call.target.owner, isNull);
      expect(call.target.name, startsWith('<extension:'));
      expect(call.inputs, hasLength(2));
    },
  );

  test('void parameters retain constant collection defaults', () async {
    final program = await _lower(['object_default.dart']);
    final value = program.functions
        .singleWhere((f) => f.target.name == 'objectDefault')
        .defaults[0];
    expect(value, isA<SequenceConstant>());
    expect(value!.type, CoreTypes.listOf(ValueType.integer));
  });

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
    final IrProgram(functions: [client, left, right]) = await _lower([
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

final class _UnexpectedEquality() {
  @override
  bool operator ==(Object other) => throw StateError('Wrong equality receiver');

  @override
  int get hashCode => 0;
}
