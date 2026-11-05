import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_methods.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_methods');
  });

  test('direct extension calls preserve receivers, arguments and closures', () {
    for (final (name, function) in <(String, Object? Function(int))>[
      ('directExtension', sdk.directExtension),
      ('implicitExtension', sdk.implicitExtension),
      ('recordExtension', sdk.recordExtension),
      ('functionExtension', sdk.functionExtension),
      ('typeVariableExtension', sdk.typeVariableExtension),
      ('capturedExtension', sdk.capturedExtension),
      ('genericExtension', sdk.genericExtension),
      ('receiverOrder', sdk.receiverOrder),
      ('cascadeExtension', sdk.cascadeExtension),
    ]) {
      for (final seed in [-1, 0, 3]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    }
  });

  test('nullable receivers and null-aware selectors match SDK', () {
    for (final seed in <int?>[null, 0, 3]) {
      for (final (name, function) in <(String, Object? Function(int?))>[
        ('nullableExtension', sdk.nullableExtension),
        ('nestedCascadeExtension', sdk.nestedCascadeExtension),
        ('overrideArgumentBoundary', sdk.overrideArgumentBoundary),
        ('nullAwareExtension', sdk.nullAwareExtension),
        ('explicitNullAwareExtension', sdk.explicitNullAwareExtension),
      ]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    }
  });

  test(
    'extension inference preserves static views and escaped type binders',
    () {
      for (final value in <Object?>[null, 1, 1.5, 'x']) {
        for (final (name, function) in <(String, Object? Function(Object?))>[
          ('staticViewExtension', sdk.staticViewExtension),
          ('classLexicalExtension', sdk.classLexicalExtension),
          ('enumLexicalExtension', sdk.enumLexicalExtension),
          ('phantomExtension', sdk.phantomExtension),
          ('escapedExtension', sdk.escapedExtension),
          ('extensionClosureDefaults', sdk.extensionClosureDefaults),
          ('explicitReceiverCheck', sdk.explicitReceiverCheck),
          ('explicitDynamicNullAware', sdk.explicitDynamicNullAware),
        ]) {
          fixture.compare(name, [value], () => function(value));
        }
      }
    },
  );

  test('nullable generic receivers preserve inferred extension arguments', () {
    for (final absent in [false, true]) {
      for (final value in <Object?>[null, 1, 1.5, 'x']) {
        fixture.compare('nullableGeneric', [
          absent,
          value,
        ], () => sdk.nullableGeneric(absent, value));
      }
    }
  });

  test('dependent and static runtime generic defaults match SDK', () {
    for (final (name, function) in <(String, Object? Function())>[
      ('extensionDependentDefaults', sdk.extensionDependentDefaults),
      ('extensionStaticRecursiveDefault', sdk.extensionStaticRecursiveDefault),
      ('extensionStaticContraDefault', sdk.extensionStaticContraDefault),
    ]) {
      fixture.compare(name, [], function);
    }
  });

  test('extension static storage and names remain distinct', () {
    fixture.compare('staticExtension', [], sdk.staticExtension);
    expect(fixture.program.globals, hasLength(2));
    expect(fixture.program.globals.map((g) => g.name).toSet(), hasLength(2));
  });

  test('extension bodies use direct targets, not nominal receiver objects', () {
    expect(fixture.program.classes.map((c) => c.type.name).toSet(), {
      'LexicalHost',
      'LexicalChild',
      'LexicalEnum',
    });
    final entry = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'directExtension',
    );
    final operations = entry.blocks.expand((b) => b.instructions).toList();
    final calls = operations.whereType<DirectCall>().toList();
    expect(calls, hasLength(3));
    expect(calls.every((c) => c.target.owner == null), isTrue);
    expect(calls.every((c) => c.target.kind == FunctionKind.function), isTrue);
    expect(calls.map((c) => c.target).toSet(), hasLength(2));
    expect(operations.whereType<InstanceCall>(), isEmpty);
    expect(operations.whereType<DynamicDispatch>(), isEmpty);
    final body = fixture.program.functions.singleWhere(
      (f) => f.target == calls.first.target,
    );
    expect(body.target.parameterTypes, hasLength(3));
    expect(body.defaults.keys, [2]);
  });
}
