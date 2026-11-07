import 'dart:io';

import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/late_locals.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  group('local late SDK comparison', () {
    setUpAll(() async => fixture = await FixtureComparison.load('late_locals'));

    for (final (name, reference) in <(String, Object? Function())>[
      ('unusedInitializer', sdk.unusedInitializer),
      ('lazyFirstRead', sdk.lazyFirstRead),
      ('earlierMutableLatestValue', sdk.earlierMutableLatestValue),
      ('earlierClosureSharesLatestValue', sdk.earlierClosureSharesLatestValue),
      ('multipleDeclaratorsReadEarlier', sdk.multipleDeclaratorsReadEarlier),
      ('captureUnboundWithoutRead', sdk.captureUnboundWithoutRead),
      ('assignmentBypassesInitializer', sdk.assignmentBypassesInitializer),
      (
        'closureAssignmentBypassesInitializer',
        sdk.closureAssignmentBypassesInitializer,
      ),
      ('nullableBoundAndUnbound', sdk.nullableBoundAndUnbound),
      ('lazyNullIsBound', sdk.lazyNullIsBound),
      ('finalNullIsFirstWrite', sdk.finalNullIsFirstWrite),
      ('unboundCoalescingReadsBeforeRhs', sdk.unboundCoalescingReadsBeforeRhs),
      ('compoundAndCoalescingUpdates', sdk.compoundAndCoalescingUpdates),
      ('finalSecondWriteEvaluatesRhs', sdk.finalSecondWriteEvaluatesRhs),
      ('finalCastPrecedesBoundCheck', sdk.finalCastPrecedesBoundCheck),
      ('failedFirstCastLeavesUnbound', sdk.failedFirstCastLeavesUnbound),
      ('failedInitializerRetries', sdk.failedInitializerRetries),
      ('finalInitializerRetries', sdk.finalInitializerRetries),
      (
        'initializerPreservesThrowAndTrace',
        sdk.initializerPreservesThrowAndTrace,
      ),
      ('initializerFailureRetainsWrite', sdk.initializerFailureRetainsWrite),
      ('initializerReturnReplacesWrite', sdk.initializerReturnReplacesWrite),
      (
        'initializerCastFailureRetainsWrite',
        sdk.initializerCastFailureRetainsWrite,
      ),
      ('initializerCastFailureRetries', sdk.initializerCastFailureRetries),
      ('boundedMutableRecursion', sdk.boundedMutableRecursion),
      ('boundedFinalRecursion', sdk.boundedFinalRecursion),
      (
        'recursiveFinalCastPrecedesBoundCheck',
        sdk.recursiveFinalCastPrecedesBoundCheck,
      ),
      ('genericLocalEnvironment', sdk.genericLocalEnvironment),
      ('genericFinalWriteCheck', sdk.genericFinalWriteCheck),
      ('receiverAndGenericCaptures', sdk.receiverAndGenericCaptures),
      ('nestedClosuresShareBinding', sdk.nestedClosuresShareBinding),
      ('lazyFunctionValue', sdk.lazyFunctionValue),
      ('functionReadBeforeArguments', sdk.functionReadBeforeArguments),
      ('mutualFunctionCalls', sdk.mutualFunctionCalls),
      (
        'initializerReadsAfterReturnFinally',
        sdk.initializerReadsAfterReturnFinally,
      ),
      ('returnReadRunsBeforeFinally', sdk.returnReadRunsBeforeFinally),
      ('initializerFailureFinallyReturn', sdk.initializerFailureFinallyReturn),
      ('nestedUnwindPreservesTrace', sdk.nestedUnwindPreservesTrace),
      ('forInBodyClosures', sdk.forInBodyClosures),
      ('outerLateSurvivesContinue', sdk.outerLateSurvivesContinue),
      ('unusedNeverInitializer', sdk.unusedNeverInitializer),
      ('throwingNeverInitializer', sdk.throwingNeverInitializer),
      ('throwingFinalNeverInitializer', sdk.throwingFinalNeverInitializer),
      ('unboundNeverRead', sdk.unboundNeverRead),
      ('neverInitializerRetries', sdk.neverInitializerRetries),
      ('lateInsideGlobalInitializer', sdk.lateInsideGlobalInitializer),
      ('lateInsideFieldInitializers', sdk.lateInsideFieldInitializers),
      ('lateInsideConstructorBody', sdk.lateInsideConstructorBody),
      ('switchPatternInitializerClosure', sdk.switchPatternInitializerClosure),
      (
        'collectionForInitializerClosures',
        sdk.collectionForInitializerClosures,
      ),
      (
        'initializerNestedClosureEnvironment',
        sdk.initializerNestedClosureEnvironment,
      ),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }

    for (final bind in [false, true]) {
      for (final (name, reference) in <(String, Object? Function(bool))>[
        ('unboundCapturedRead', sdk.unboundCapturedRead),
        ('unboundFinalCapturedRead', sdk.unboundFinalCapturedRead),
        (
          'unboundFunctionReadBeforeArguments',
          sdk.unboundFunctionReadBeforeArguments,
        ),
      ]) {
        test('$name($bind) matches the SDK', () {
          fixture.compare(name, [bind], () => reference(bind));
        });
      }
    }

    for (final first in [false, true]) {
      test(
        'joined switch-pattern initializer with first=$first matches the SDK',
        () {
          fixture.compare('joinedPatternInitializerClosure', [
            first,
          ], () => sdk.joinedPatternInitializerClosure(first));
        },
      );
    }

    for (final skip in [false, true]) {
      test('loop-body late closures with continue=$skip match the SDK', () {
        fixture.compare('loopBodyClosures', [
          skip,
        ], () => sdk.loopBodyClosures(skip));
      });
    }
  });

  group('local late language checks', () {
    for (final (name, source) in <(String, String)>[
      (
        'direct local self-reference',
        'int f() { late int value = value; return value; }',
      ),
      (
        'self-reference in initializer closure',
        'int f() { late int value = (() => value)(); return value; }',
      ),
      (
        'self-reference in lazy function value',
        'void f() { late int Function() value = () => value(); }',
      ),
      (
        'self-reference shadowing a top-level variable',
        'int value = 9; int f() { late int value = value; return value; }',
      ),
      (
        'self-reference shadowing an enclosing local',
        'int f() { int value = 9; { late int value = value; return value; } }',
      ),
      (
        'future local variable',
        'int f() { late int value = later; int later = 2; return value; }',
      ),
      (
        'future local variable in initializer closure',
        'int f() { late int value = (() => later)(); int later = 2; return value; }',
      ),
      (
        'future variable shadowing a top-level variable',
        'int later = 9; int f() { late int value = later; int later = 2; return value; }',
      ),
      (
        'future local function',
        'int f() { late int value = later(); int later() => 2; return value; }',
      ),
      (
        'future local function in initializer closure',
        'int f() { late int value = (() => later())(); int later() => 2; return value; }',
      ),
      (
        'future declarator in the same statement',
        'int f() { late int first = second, second = 2; return first; }',
      ),
      (
        'late declaration in a for initializer',
        'void f() { for (late int i = 0; i < 2; i++) {} }',
      ),
      (
        'late-final declaration in a for initializer',
        'void f() { for (late final int i = 0; i < 2;) {} }',
      ),
      (
        'late declaration in for-in',
        'void f() { for (late int i in [1, 2]) {} }',
      ),
      (
        'late-final declaration in for-in',
        'void f() { for (late final int i in [1, 2]) {} }',
      ),
      (
        'assignment to initialized late final',
        'void f() { late final int value = 1; value = 2; }',
      ),
      (
        'captured assignment to initialized late final',
        'void f() { late final int value = 1; void write() { value = 2; } }',
      ),
      (
        'definitely repeated late-final assignment',
        'void f() { late final int value; value = 1; value = 2; }',
      ),
      (
        'late-final assignment after both branches assign',
        'void f(bool b) { late final int value; if (b) { value = 1; } else { value = 2; } value = 3; }',
      ),
      (
        'definitely unassigned local read',
        'int f() { late int value; return value; }',
      ),
      (
        'definitely unassigned final local read',
        'int f() { late final int value; return value; }',
      ),
    ]) {
      test('$name is rejected before lowering', () async {
        final directory = Directory.systemTemp.createTempSync(
          'dartc-late-local-invalid-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync(source);
        var lowered = false;
        await expectLater(
          CheckedLibraries.read([file.path], (input) {
            lowered = true;
            return Lowering.lower(input);
          }),
          throwsFormatException,
        );
        expect(lowered, isFalse);
      });
    }
  });
}
