import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/generic_functions.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('generic_functions');
  });

  test('generic declarations retain one body across instantiations', () {
    final identities = fixture.program.functions.where(
      (f) => f.target.name == 'identity',
    );
    expect(identities, hasLength(1));
    expect(identities.single.target.typeParameters, hasLength(1));
  });

  void compareIntegers(List<(String, Object? Function(int))> cases) {
    for (final seed in [-1, 0, 1, 7]) {
      for (final (name, function) in cases) {
        fixture.compare(name, [seed], () => function(seed));
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
    fixture.compare(
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
        fixture.compare('genericNestedAnonymous', [
          candidate,
        ], () => sdk.genericNestedAnonymous(candidate));
        fixture.compare('genericReturnedAnonymous', [
          candidate,
        ], () => sdk.genericReturnedAnonymous(candidate));
      }
    },
  );

  test('generic constructor callables instantiate owners and redirects', () {
    compareIntegers([
      ('genericConstructorFunction', sdk.genericConstructorFunction),
      ('genericAliasConstructor', sdk.genericAliasConstructor),
      ('genericLexicalConstructorChecks', sdk.genericLexicalConstructorChecks),
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
      fixture.compare('genericRecursion', [
        depth,
      ], () => sdk.genericRecursion(depth));
    }
  });

  test('generic closures retain owner and enclosing function types', () {
    for (final candidate in <Object>[1, 2.5, 'x', true]) {
      fixture.compare('genericCapturedBoth', [
        candidate,
      ], () => sdk.genericCapturedBoth(candidate));
      fixture.compare('genericCapturedOwner', [
        candidate,
      ], () => sdk.genericCapturedOwner(candidate));
      fixture.compare('genericCapturedFunction', [
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
      fixture.compare(name, [], function);
    }
  });
  test('literal null tests remain dependent on runtime type arguments', () {
    fixture.compare(
      'genericNullLiteralChecks',
      [],
      sdk.genericNullLiteralChecks,
    );
    fixture.compare(
      'genericNullLiteralCastFailure',
      [],
      sdk.genericNullLiteralCastFailure,
    );
  });
}
