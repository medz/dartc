import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/dynamic_dispatch.dart' as sdk;
import 'fixtures/dynamic_dispatch_private_use.dart' as private_sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('dynamic_dispatch');
  });
  test(
    'dynamic named arguments retain source order',
    () => fixture.compare('named', [], sdk.named),
  );
  test('getter invocation preserves syntax-dependent evaluation order', () {
    for (var i = 0; i < 5; i++) {
      fixture.compare('getterOrder', [i], () => sdk.getterOrder(i));
    }
  });
  test('dynamic and Function calls, extraction and private lookup', () {
    for (var i = 0; i < 7; i++) {
      fixture.compare('calls', [i], () => sdk.calls(i));
    }
  });
  test('shared updates, cascades and null shortening', () {
    for (final missing in [false, true]) {
      fixture.compare('updates', [missing], () => sdk.updates(missing));
      fixture.compare('nullChain', [missing], () => sdk.nullChain(missing));
    }
  });
  test('dynamic operators and equality null rule', () {
    for (final n in [0, 2, 7]) {
      fixture.compare('operators', [n], () => sdk.operators(n));
      fixture.compare('equality', [n], () => sdk.equality(n));
    }
    fixture.compare('equality', [null], () => sdk.equality(null));
    fixture.compare('userOperators', [], sdk.userOperators);
    fixture.compare('customEquality', [], sdk.customEquality);
  });
  test('generic calls use explicit or declaration default types', () {
    for (var i = 0; i < 3; i++) {
      fixture.compare('genericCalls', [i], () => sdk.genericCalls(i));
    }
  });
  test('shape, type, bound and argument failures unwind after effects', () {
    for (var i = 0; i < 5; i++) {
      fixture.compare('failures', [i], () => sdk.failures(i));
    }
  });
  test('missing members preserve assignment expression values', () {
    for (var i = 0; i < 4; i++) {
      fixture.compare('fallback', [i], () => sdk.fallback(i));
    }
  });
  test(
    'dynamic null supports Object members',
    () => fixture.compare('objectMembers', [], sdk.objectMembers),
  );
  test('Function-bounded variables preserve all invocation forms', () {
    for (var i = 0; i < 6; i++) {
      fixture.compare('boundedCalls', [i], () => sdk.boundedCalls(i));
    }
  });
  test('known getters check after all arguments', () {
    for (var i = 0; i < 4; i++) {
      fixture.compare('getterFailures', [i], () => sdk.getterFailures(i));
    }
  });
  test(
    'private dynamic selectors retain each calling library identity',
    () async {
      final program = await CheckedLibraries.read([
        'test/lowering/fixtures/dynamic_dispatch_private.dart',
        'test/lowering/fixtures/dynamic_dispatch_private_use.dart',
      ], Lowering.lower);
      FixtureComparison(program)
          .compare('privateLibraries', [], private_sdk.privateLibraries);
    },
  );
  test('remaining scalar operators and null-aware lvalues', () {
    for (var form = 0; form < 14; form++) {
      fixture.compare('binary', [7, form], () => sdk.binary(7, form));
    }
    for (final missing in [false, true]) {
      fixture.compare('nullAssignments', [
        missing,
      ], () => sdk.nullAssignments(missing));
      fixture.compare('nullIndex', [missing], () => sdk.nullIndex(missing));
      fixture.compare('functionCascade', [
        missing,
      ], () => sdk.functionCascade(missing));
    }
    fixture.compare('objectTearoffs', [], sdk.objectTearoffs);
  });
  test('runtime generic defaults retain owner and captured environments', () {
    fixture.compare('genericEnvironments', [], sdk.genericEnvironments);
  });
  test('shape errors precede defaults and bounds, including instantiated callables', () {
    // SDK 3.13.7 JIT and AOT differ for this invalid call shape. Supply the
    // prescribed mirrors explicitly, retaining the same SDK noSuchMethod body.
    final receiver = sdk.ShapeReceiver();
    final missingX = Invocation.method(#f, const []);
    final missingY = Invocation.genericMethod(#g, [String], ['bad']);
    final first = receiver.noSuchMethod(missingX) as int;
    final second = receiver.noSuchMethod(missingY) as int;
    fixture.compare('shapeBeforeBounds', [], () => first + second + 100);
  });
  test(
    'runtime Invocation preserves kinds, names, types and sorted named values',
    () {
      fixture.compare('invocationData', [], sdk.invocationData);
    },
  );
}
