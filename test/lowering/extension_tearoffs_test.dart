import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_tearoffs.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_tearoffs');
  });

  test('extension extraction uses ordinary lexical wrappers', () {
    final wrappers = fixture.program.functions.where(
      (function) => function.target.name.startsWith('<extension-tearoff:'),
    );
    expect(wrappers, isNotEmpty);
    for (final wrapper in wrappers) {
      expect(wrapper.target.kind, FunctionKind.closure);
      expect(wrapper.target.owner, isNull);
      expect(wrapper.target.captures, hasLength(1));
      expect(wrapper.blocks, hasLength(1));
      final calls = wrapper.entry.instructions.whereType<DirectCall>();
      expect(calls, hasLength(1));
      final forwarded = calls.single;
      for (final parameter in wrapper.target.typeParameters) {
        expect(forwarded.target.typeParameters.contains(parameter), isFalse);
      }
      expect(
        wrapper.defaults.keys.toSet(),
        wrapper.target.signature.optionalSlots.toSet(),
      );
    }
  });

  test('extraction preserves defaults, receivers, identity and effects', () {
    for (final (name, function) in <(String, Object? Function(int))>[
      ('extractedDefaults', sdk.extractedDefaults),
      ('capturedReceiver', sdk.capturedReceiver),
      ('nonClassReceivers', sdk.nonClassReceivers),
      ('extractedLexical', sdk.extractedLexical),
      ('extractedCallMethod', sdk.extractedCallMethod),
      ('objectPatternTearOff', sdk.objectPatternTearOff),
      ('extractedIdentity', sdk.extractedIdentity),
      ('escapedTypeEnvironment', sdk.escapedTypeEnvironment),
      ('extractionEffects', sdk.extractionEffects),
      ('extractedNever', sdk.extractedNever),
      ('extractedVoid', sdk.extractedVoid),
      ('extractedVoidResult', sdk.extractedVoidResult),
      ('patternReuse', sdk.patternReuse),
    ]) {
      for (final seed in [-1, 0, 3]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    }
  });

  test('nullable receivers and null-aware extraction remain distinct', () {
    for (final seed in <int?>[null, 0, 3]) {
      fixture.compare('nullableTearOff', [
        seed,
      ], () => sdk.nullableTearOff(seed));
      fixture.compare('nullAwareTearOff', [
        seed,
      ], () => sdk.nullAwareTearOff(seed));
    }
  });

  test('receiver checks happen during extraction before later effects', () {
    for (final seed in <Object?>[null, 1, 'bad']) {
      fixture.compare('checkedExtraction', [
        seed,
      ], () => sdk.checkedExtraction(seed));
    }
  });

  test('generic wrappers retain defaults, fresh binders and environments', () {
    for (final (name, function) in <(String, Object? Function())>[
      ('genericIdentity', sdk.genericIdentity),
      ('genericTearOff', sdk.genericTearOff),
      ('dependentDynamicDefault', sdk.dependentDynamicDefault),
      ('recursiveBinderIdentity', sdk.recursiveBinderIdentity),
      ('globalTearOff', sdk.globalTearOff),
    ]) {
      fixture.compare(name, [], function);
    }
  });
  test('extension runtime defaults use declaration bounds and variance', () {
    for (final (name, function) in <(String, Object? Function())>[
      ('independentTearOffDefault', sdk.independentTearOffDefault),
      ('coupledTearOffDefaults', sdk.coupledTearOffDefaults),
      ('boundedTearOffDefault', sdk.boundedTearOffDefault),
      ('boundedCovariantDefault', sdk.boundedCovariantDefault),
      ('boundedContravariantDefault', sdk.boundedContravariantDefault),
      ('covariantTearOffDefault', sdk.covariantTearOffDefault),
      ('contravariantTearOffDefault', sdk.contravariantTearOffDefault),
      ('recursiveTearOffDefault', sdk.recursiveTearOffDefault),
      ('recursiveContraTearOffDefault', sdk.recursiveContraTearOffDefault),
      ('dependentPairTearOffDefault', sdk.dependentPairTearOffDefault),
      ('explicitTearOffDefault', sdk.explicitTearOffDefault),
      ('patternTearOffDefault', sdk.patternTearOffDefault),
      ('patternIndependentDefault', sdk.patternIndependentDefault),
      ('boundedSuccessfulDefault', sdk.boundedSuccessfulDefault),
    ]) {
      fixture.compare(name, [], function);
    }
  });
  test('wrapper default templates retain their exact runtime shapes', () {
    List<TypeParameterType> parameters(String enclosing) => fixture
        .program
        .functions
        .singleWhere(
          (function) =>
              function.target.name.startsWith('<extension-tearoff:') &&
              function.target.enclosing?.name == enclosing,
        )
        .target
        .typeParameters;
    final bottomCallback = FunctionType(ValueType.voidType, [ValueType.never]);
    expect(
      parameters('dependentDynamicDefault').single.defaultType,
      ValueType.dynamicType,
    );
    expect(
      parameters('boundedTearOffDefault').single.defaultType,
      ValueType.number,
    );
    expect(parameters('boundedTearOffDefault').single.bound, ValueType.integer);
    expect(
      parameters('covariantTearOffDefault').single.defaultType,
      CoreTypes.listOf(ValueType.dynamicType),
    );
    expect(
      parameters('boundedCovariantDefault').single.defaultType,
      CoreTypes.listOf(ValueType.number),
    );
    expect(
      parameters('contravariantTearOffDefault').single.defaultType,
      bottomCallback,
    );
    expect(
      parameters('boundedContravariantDefault').single.defaultType,
      bottomCallback,
    );
    expect(
      parameters('recursiveContraTearOffDefault').single.defaultType,
      bottomCallback,
    );
    expect(parameters('coupledTearOffDefaults').map((p) => p.defaultType), [
      ValueType.number,
      CoreTypes.listOf(ValueType.number),
    ]);
    expect(
      parameters('explicitTearOffDefault').single.defaultType,
      ValueType.dynamicType,
    );
    expect(
      parameters('patternTearOffDefault').single.defaultType,
      ValueType.dynamicType,
    );
  });
}
