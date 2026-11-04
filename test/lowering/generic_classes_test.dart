import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/generic_classes.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late IrProgram program;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      'test/lowering/fixtures/generic_classes.dart',
    ], Lowering.lower);
    functions = {
      for (final function in program.functions)
        if (function.target.owner == null) function.target.name: function,
    };
    final library = Uri.base.resolve('test/lowering/fixtures/effects.dart');
    runner = FixtureRunner(program, {
      (library, 'tick'): effects.tick,
      (library, 'probe'): effects.probe,
    });
  });

  void compare(String name, List<Object?> args, Object? Function() expected) {
    (Object?, Object?, List<int>) observe(Object? Function() run) {
      effects.calls.clear();
      Object? result;
      Object? error;
      try {
        result = run();
      } catch (e) {
        error = switch (e) {
          StateError(:final message) => (StateError, message),
          TypeError() => TypeError,
          _ => e.runtimeType,
        };
      }
      return (result, error, List.of(effects.calls));
    }

    final reference = observe(expected);
    final actual = observe(() => runner.run(functions[name]!, args));
    expect(actual.$1, reference.$1, reason: name);
    expect(actual.$2, reference.$2, reason: name);
    expect(actual.$3, reference.$3, reason: name);
  }

  test('generic instances share one declaration and method body', () {
    final declarations = program.classes
        .where((c) => c.type.name == 'Box')
        .toList();
    expect(declarations, hasLength(1));
    final declaration = declarations.single.type;
    expect(declaration.typeParameters, hasLength(1));
    expect(
      program.functions.where(
        (f) => f.target.owner == declaration && f.target.name == 'replace',
      ),
      hasLength(1),
    );
    expect(
      declaration.instantiate([ValueType.integer]).declaration,
      same(declaration),
    );
    expect(
      declaration.instantiate([ValueType.string]).declaration,
      same(declaration),
    );
  });

  test(
    'generic classes preserve storage, construction, inheritance and checks',
    () {
      for (final seed in [-1, 0, 1, 7]) {
        for (final (name, function) in <(String, Object? Function(int))>[
          ('genericStorage', sdk.genericStorage),
          ('genericBoundReceiver', sdk.genericBoundReceiver),
          ('genericConstantTearoff', sdk.genericConstantTearoff),
          ('genericDefaultTearoff', sdk.genericDefaultTearoff),
          ('genericRecord', sdk.genericRecord),
          ('genericConstructorTearoff', sdk.genericConstructorTearoff),
          ('genericReorderedInheritance', sdk.genericReorderedInheritance),
          ('genericInheritance', sdk.genericInheritance),
          ('genericSubtype', sdk.genericSubtype),
          ('genericFactories', sdk.genericFactories),
          ('genericBound', sdk.genericBound),
          ('genericCovariantWrite', sdk.genericCovariantWrite),
          ('genericCovariantCall', sdk.genericCovariantCall),
          ('genericTearoff', sdk.genericTearoff),
          ('genericTearoffCall', sdk.genericTearoffCall),
        ]) {
          compare(name, [seed], () => function(seed));
        }
      }
    },
  );

  test('applied constructor tearoffs have distinct identity', () {
    compare('genericConstructorIdentity', [], sdk.genericConstructorIdentity);
    compare('genericVariance', [], sdk.genericVariance);
    compare('genericRecursiveBound', [], sdk.genericRecursiveBound);
    compare('genericSelfHierarchy', [], sdk.genericSelfHierarchy);
  });

  test('type arguments survive tests, casts and closure environments', () {
    for (final candidate in <Object?>[null, 1, 2.5, 'x', true]) {
      for (final (name, function) in <(String, Object? Function(Object?))>[
        ('genericTypes', sdk.genericTypes),
        ('genericNullOperations', sdk.genericNullOperations),
        ('genericNonNull', sdk.genericNonNull),
        ('genericNestedType', sdk.genericNestedType),
        ('genericNullableTypes', sdk.genericNullableTypes),
        ('genericCast', sdk.genericCast),
        ('genericClosure', sdk.genericClosure),
      ]) {
        compare(name, [candidate], () => function(candidate));
      }
    }
  });
}
