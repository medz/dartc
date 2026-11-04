import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/generic_functions.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late IrProgram program;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      'test/lowering/fixtures/generic_functions.dart',
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

  test('generic declarations retain one body across instantiations', () {
    final identities = program.functions.where(
      (f) => f.target.name == 'identity',
    );
    expect(identities, hasLength(1));
    expect(identities.single.target.typeParameters, hasLength(1));
  });

  void compareIntegers(List<(String, Object? Function(int))> cases) {
    for (final seed in [-1, 0, 1, 7]) {
      for (final (name, function) in cases) {
        compare(name, [seed], () => function(seed));
      }
    }
  }

  test('direct calls and function value instantiation match SDK', () {
    compareIntegers([
      ('genericDirect', sdk.genericDirect),
      ('genericBounded', sdk.genericBounded),
      ('genericFunctionValue', sdk.genericFunctionValue),
      ('genericInstantiation', sdk.genericInstantiation),
      ('genericOptionalNamed', sdk.genericOptionalNamed),
      ('genericExplicitCall', sdk.genericExplicitCall),
      ('genericGetterCall', sdk.genericGetterCall),
      ('genericCallable', sdk.genericCallable),
      ('genericStaticMethod', sdk.genericStaticMethod),
      ('genericDotStaticMethod', sdk.genericDotStaticMethod),
    ]);
  });

  test('generic virtual methods preserve owner arguments and checks', () {
    compareIntegers([
      ('genericMethod', sdk.genericMethod),
      ('genericVirtualMethod', sdk.genericVirtualMethod),
      ('genericMethodTearoff', sdk.genericMethodTearoff),
      ('genericCovariantMethod', sdk.genericCovariantMethod),
      ('genericRuntimeBound', sdk.genericRuntimeBound),
      ('genericNullableMethod', sdk.genericNullableMethod),
      ('genericCascadeMethod', sdk.genericCascadeMethod),
    ]);
  });

  test('generic bound tearoffs fail at extraction before later effects', () {
    compareIntegers([
      ('genericBoundTearoffExtraction', sdk.genericBoundTearoffExtraction),
      ('genericBoundInstantiatedTearoff', sdk.genericBoundInstantiatedTearoff),
      (
        'genericBoundTearoffEvaluationOrder',
        sdk.genericBoundTearoffEvaluationOrder,
      ),
    ]);
  });

  test('nested generic bounds reify covariant callback parameters', () {
    compare(
      'genericNestedBoundCovariance',
      [],
      sdk.genericNestedBoundCovariance,
    );
  });

  test(
    'anonymous generic closures retain captured enclosing type arguments',
    () {
      compareIntegers([('genericAnonymous', sdk.genericAnonymous)]);
      for (final candidate in <Object>[1, 2.5, 'x', true]) {
        compare('genericNestedAnonymous', [
          candidate,
        ], () => sdk.genericNestedAnonymous(candidate));
        compare('genericReturnedAnonymous', [
          candidate,
        ], () => sdk.genericReturnedAnonymous(candidate));
      }
    },
  );

  test('generic constructor callables instantiate owners and redirects', () {
    compareIntegers([
      ('genericConstructorFunction', sdk.genericConstructorFunction),
      ('genericAliasConstructor', sdk.genericAliasConstructor),
      ('genericFactoryConstructor', sdk.genericFactoryConstructor),
      (
        'genericReorderedAliasConstructor',
        sdk.genericReorderedAliasConstructor,
      ),
      ('genericFixedAliasConstructor', sdk.genericFixedAliasConstructor),
      ('genericRepeatedAliasConstructor', sdk.genericRepeatedAliasConstructor),
    ]);
  });

  test('generic recursion may change type arguments', () {
    compareIntegers([('genericLocalRecursion', sdk.genericLocalRecursion)]);
    for (final depth in [0, 1, 3]) {
      compare('genericRecursion', [depth], () => sdk.genericRecursion(depth));
    }
  });

  test('generic closures retain owner and enclosing function types', () {
    for (final candidate in <Object>[1, 2.5, 'x', true]) {
      compare('genericCapturedBoth', [
        candidate,
      ], () => sdk.genericCapturedBoth(candidate));
      compare('genericCapturedOwner', [
        candidate,
      ], () => sdk.genericCapturedOwner(candidate));
      compare('genericCapturedFunction', [
        candidate,
      ], () => sdk.genericCapturedFunction(candidate));
    }
  });

  test('generic function runtime types and identity match SDK', () {
    for (final (name, function) in <(String, Object? Function())>[
      ('genericFunctionTests', sdk.genericFunctionTests),
      ('genericInstantiationTests', sdk.genericInstantiationTests),
      ('genericTearoffEquality', sdk.genericTearoffEquality),
      ('genericLocalEquality', sdk.genericLocalEquality),
      ('genericUnusedTypeIdentity', sdk.genericUnusedTypeIdentity),
      ('genericRawConstructorEquality', sdk.genericRawConstructorEquality),
      ('genericAliasConstructorEquality', sdk.genericAliasConstructorEquality),
      ('genericAliasConstructorIdentity', sdk.genericAliasConstructorIdentity),
      ('genericDependentBounds', sdk.genericDependentBounds),
    ]) {
      compare(name, [], function);
    }
  });
  test('literal null tests remain dependent on runtime type arguments', () {
    compare('genericNullLiteralChecks', [], sdk.genericNullLiteralChecks);
    compare(
      'genericNullLiteralCastFailure',
      [],
      sdk.genericNullLiteralCastFailure,
    );
  });
}
