import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/async_functions.dart' as sdk;
import 'fixtures/effects.dart' as effects;

void main() {
  late IrProgram program;
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/frontend/lowering/fixtures/async_functions.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {
      (
        Uri.base.resolve('test/frontend/lowering/fixtures/effects.dart'),
        'tick',
      ): effects.tick,
    });
    functions = {
      for (final f in program.functions)
        if (f.target.owner == null) f.target.name: f,
    };
  });
  Future<void> compare(
    String name,
    List<Object?> args,
    Future<Object?> Function() reference,
  ) async {
    effects.calls.clear();
    final expected = await reference();
    final calls = List.of(effects.calls);
    effects.calls.clear();
    final actual = await runner.resolveAsync(
      runner.run(functions[name]!, args),
    );
    expect(actual, expected, reason: name);
    expect(effects.calls, calls, reason: '$name effects');
  }

  test(
    'native microtasks preserve synchronous start and scalar awaits',
    () async {
      for (final suspended in [false, true]) {
        await compare('ordering', [suspended], () => sdk.ordering(suspended));
        await compare('pendingCompletion', [
          suspended,
        ], () => sdk.pendingCompletion(suspended));
      }
      await compare('factories', [], sdk.factories);
      await compare('syncIdentity', [], sdk.syncIdentity);
    },
  );
  test('return adoption happens after finally and outside its catch', () async {
    for (final explicitAwait in [false, true]) {
      for (final failure in [false, true]) {
        await compare('returnOrAwait', [
          explicitAwait,
          failure,
        ], () => sdk.returnOrAwait(explicitAwait, failure));
      }
    }
    await compare('dynamicReturnCheck', [], sdk.dynamicReturnCheck);
    await compare('finalizerOverride', [], sdk.finalizerOverride);
    await compare('returnSnapshot', [], sdk.returnSnapshot);
  });
  test(
    'typed future value arms preserve identity and completion scheduling',
    () async {
      await compare('resultTypes', [], sdk.resultTypes);
      await compare('completionTypes', [], sdk.completionTypes);
      await compare('futureValueArm', [], sdk.futureValueArm);
      await compare('nestedAwait', [], sdk.nestedAwait);
      await compare('genericCases', [], sdk.genericCases);
      expect(functions['broad']!.completionType, ValueType.object.nullable);
      expect(functions['explicitFutureOr']!.completionType, ValueType.object);
    },
  );
  test('suspended exception and original trace survive rethrow', () async {
    await compare('resumedRethrow', [], sdk.resumedRethrow);
    await compare('neverAwait', [], sdk.neverAwait);
  });
  test(
    'Future APIs and dynamic calls retain native callback protocols',
    () async {
      for (final dynamicReceiver in [false, true]) {
        await compare('callbackProtocols', [
          dynamicReceiver,
        ], () => sdk.callbackProtocols(dynamicReceiver));
      }
      await compare('errorCallbacks', [], sdk.errorCallbacks);
      await compare('rejectedCompletion', [], sdk.rejectedCompletion);
      await compare('dynamicVoid', [], sdk.dynamicVoid);
      await compare('voidPayloads', [], sdk.voidPayloads);
      await compare('protocolErrors', [], sdk.protocolErrors);
    },
  );
  test(
    'await composes with expressions, exits, members and shared captures',
    () async {
      await compare('asynchronousErrors', [], sdk.asynchronousErrors);
      await compare('suspendedExpressions', [], sdk.suspendedExpressions);
      await compare('loopFinalizers', [], sdk.loopFinalizers);
      await compare('asynchronousMembers', [], sdk.asynchronousMembers);
      await compare('concurrentCaptures', [], sdk.concurrentCaptures);
    },
  );
  test('each resumed segment has an independent execution budget', () async {
    await compare('manyAwaits', [], sdk.manyAwaits);
  });
  test(
    'unmodeled user Future protocols cannot be swallowed by source catch',
    () async {
      for (final name in [
        'unsupportedFuture',
        'unsupportedCatch',
        'unsupportedThen',
      ]) {
        await expectLater(
          runner.resolveAsync(runner.run(functions[name]!, [])),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'feature',
              contains('User-defined Future'),
            ),
          ),
        );
      }
      for (final name in [
        'unsupportedCompletion',
        'unsupportedEventQueue',
        'unsupportedTearOff',
      ]) {
        await expectLater(
          runner.resolveAsync(runner.run(functions[name]!, [])),
          throwsUnsupportedError,
        );
      }
    },
  );
}
