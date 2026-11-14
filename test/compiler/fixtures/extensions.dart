import '../../frontend/lowering/fixtures/extension_access.dart' as access;
import '../../frontend/lowering/fixtures/extension_call.dart' as call;
import '../../frontend/lowering/fixtures/extension_tearoffs.dart' as tearoffs;
import 'extension_types.dart' show observe;

void main(List<String> args) {
  switch (args.single) {
    case 'access':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('getterSetter', access.getterSetter),
        ('updates', access.updates),
        ('explicitIndex', access.explicitIndex),
        ('getterCall', access.getterCall),
        ('operatorUpdates', access.operatorUpdates),
        ('explicitOperators', access.explicitOperators),
        ('patterns', access.patterns),
        ('lexicalAccess', access.lexicalAccess),
        ('setterOnly', access.setterOnly),
        ('patternReuse', access.patternReuse),
        ('implicitSetterStatement', access.implicitSetterStatement),
        ('repeatedOperator', access.repeatedOperator),
        ('implicitGenericOperators', access.implicitGenericOperators),
        ('recordMembers', access.recordMembers),
      ]) {
        for (final seed in [-1, 0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final absent in [false, true]) {
        observe(
          'optionalRecordCall',
          () => access.optionalRecordCall(absent, 3),
          absent,
        );
        observe('ifNullIndex', () => access.ifNullIndex(absent), absent);
        observe('receiverCheck', () => access.receiverCheck(absent), absent);
        observe(
          'operatorReceiverCheck',
          () => access.operatorReceiverCheck(absent),
          absent,
        );
        for (final empty in [false, true]) {
          observe(
            'nullableAssignments',
            () => access.nullableAssignments(absent, empty),
            [absent, empty],
          );
        }
      }
      for (final seed in <int?>[null, 0, 3]) {
        observe('nullableGetter', () => access.nullableGetter(seed), seed);
        observe('nullablePattern', () => access.nullablePattern(seed), seed);
      }
      for (final input in <Object?>[null, 0, 'bad']) {
        observe('indexCheck', () => access.indexCheck(input), input);
        observe(
          'explicitIndexCheck',
          () => access.explicitIndexCheck(input),
          input,
        );
        observe('explicitDynamic', () => access.explicitDynamic(input), input);
      }
      for (final stage in [0, 1, 2, 3, 5]) {
        observe(
          'exceptionalUpdate',
          () => access.exceptionalUpdate(stage),
          stage,
        );
      }
      observe('patternSelection', access.patternSelection);
    case 'call':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('direct', call.direct),
        ('virtualGetter', call.virtualGetter),
        ('parenthesizedGetter', call.parenthesizedGetter),
        ('extensionGetter', call.extensionGetter),
        ('explicitGetter', call.explicitGetter),
        ('explicit', call.explicit),
        ('lexical', call.lexical),
        ('generic', call.generic),
        ('genericGetters', call.genericGetters),
        ('retainedType', call.retainedType),
      ]) {
        for (final seed in [0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final seed in <int?>[null, 0, 3]) {
        observe('nullable', () => call.nullable(seed), seed);
      }
      for (final absent in [false, true]) {
        observe('nullAwareGetter', () => call.nullAwareGetter(absent), absent);
        observe(
          'nullAwareGenericGetter',
          () => call.nullAwareGenericGetter(absent),
          absent,
        );
        observe(
          'genericReceiverCheck',
          () => call.genericReceiverCheck(absent),
          absent,
        );
      }
      for (final input in <Object?>[null, 1, 'bad']) {
        observe('checkedReceiver', () => call.checkedReceiver(input), input);
        observe('checkedArgument', () => call.checkedArgument(input), input);
      }
      for (final stage in [0, 1, 3]) {
        observe('failure', () => call.failure(stage), stage);
      }
      for (final stage in [0, 1, 2, 3]) {
        for (final form in [0, 1, 2, 3]) {
          observe('getterFailure', () => call.getterFailure(stage, form), [
            stage,
            form,
          ]);
        }
      }
      observe('topGetter', call.topGetter);
      observe('realMember', call.realMember);
      observe('dynamicMiss', call.dynamicMiss);
    case 'tearoffs':
      for (final (name, run) in <(String, Object? Function(int))>[
        ('extractedDefaults', tearoffs.extractedDefaults),
        ('capturedReceiver', tearoffs.capturedReceiver),
        ('cleanupTearOff', tearoffs.cleanupTearOff),
        ('chainedTearOffs', tearoffs.chainedTearOffs),
        ('nonClassReceivers', tearoffs.nonClassReceivers),
        ('extractedLexical', tearoffs.extractedLexical),
        ('extractedCallMethod', tearoffs.extractedCallMethod),
        ('objectPatternTearOff', tearoffs.objectPatternTearOff),
        ('extractedIdentity', tearoffs.extractedIdentity),
        ('escapedTypeEnvironment', tearoffs.escapedTypeEnvironment),
        ('extractionEffects', tearoffs.extractionEffects),
        ('extractedNever', tearoffs.extractedNever),
        ('extractedVoid', tearoffs.extractedVoid),
        ('extractedVoidResult', tearoffs.extractedVoidResult),
        ('patternReuse', tearoffs.patternReuse),
      ]) {
        for (final seed in [-1, 0, 3]) {
          observe(name, () => run(seed), seed);
        }
      }
      for (final seed in <int?>[null, 0, 3]) {
        observe('nullableTearOff', () => tearoffs.nullableTearOff(seed), seed);
        observe(
          'nullAwareTearOff',
          () => tearoffs.nullAwareTearOff(seed),
          seed,
        );
      }
      for (final input in <Object?>[null, 1, 'bad']) {
        observe(
          'checkedExtraction',
          () => tearoffs.checkedExtraction(input),
          input,
        );
      }
      for (final (name, run) in <(String, Object? Function())>[
        ('genericIdentity', tearoffs.genericIdentity),
        ('genericTearOff', tearoffs.genericTearOff),
        ('dependentDynamicDefault', tearoffs.dependentDynamicDefault),
        ('recursiveBinderIdentity', tearoffs.recursiveBinderIdentity),
        ('globalTearOff', tearoffs.globalTearOff),
        ('independentTearOffDefault', tearoffs.independentTearOffDefault),
        ('coupledTearOffDefaults', tearoffs.coupledTearOffDefaults),
        ('boundedTearOffDefault', tearoffs.boundedTearOffDefault),
        ('boundedCovariantDefault', tearoffs.boundedCovariantDefault),
        ('boundedContravariantDefault', tearoffs.boundedContravariantDefault),
        ('covariantTearOffDefault', tearoffs.covariantTearOffDefault),
        ('contravariantTearOffDefault', tearoffs.contravariantTearOffDefault),
        ('recursiveTearOffDefault', tearoffs.recursiveTearOffDefault),
        (
          'recursiveContraTearOffDefault',
          tearoffs.recursiveContraTearOffDefault,
        ),
        ('dependentPairTearOffDefault', tearoffs.dependentPairTearOffDefault),
        ('explicitTearOffDefault', tearoffs.explicitTearOffDefault),
        ('patternTearOffDefault', tearoffs.patternTearOffDefault),
        ('patternIndependentDefault', tearoffs.patternIndependentDefault),
        ('boundedSuccessfulDefault', tearoffs.boundedSuccessfulDefault),
      ]) {
        observe(name, run);
      }
    case 'order':
      observe('implicitSetterValue', () => access.implicitSetterValue(3), 3);
      observe('explicitIndexValue', () => access.explicitIndexValue(3), 3);
      for (final stage in [0, 1, 2, 3, 4, 5]) {
        observe(
          'explicitIndexFailure',
          () => access.explicitIndexFailure(stage),
          stage,
        );
      }
      for (final stage in [0, 1, 3, 5]) {
        observe(
          'implicitSetterFailure',
          () => access.implicitSetterFailure(stage),
          stage,
        );
      }
  }
}
