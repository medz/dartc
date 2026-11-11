import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_types_generic.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_types_generic');
  });
  test(
    'generic extension types preserve source type arguments and erased values',
    () {
      for (final (name, function) in <(String, int Function(int))>[
        ('shorthand', sdk.shorthand),
        ('functionRepresentation', sdk.functionRepresentation),
        ('direct', sdk.direct),
        ('pair', sdk.pair),
        ('genericMethod', sdk.genericMethod),
        ('escaped', sdk.escaped),
        ('boundedReceiver', sdk.boundedReceiver),
        ('constructors', sdk.constructors),
        ('dynamicConstructor', sdk.dynamicConstructor),
      ]) {
        for (final seed in [0, 3, 7]) {
          fixture.compare(name, [seed], () => function(seed));
        }
      }
      for (final seed in [0, 3, 7]) {
        fixture.compare('operators', [seed], () => sdk.operators(seed));
        fixture.compare('dependentConstructor', [
          seed,
        ], () => sdk.dependentConstructor(seed));
      }
      for (final value in <int?>[null, 2]) {
        fixture.compare('nullable', [value], () => sdk.nullable(value));
        fixture.compare('nullAware', [value], () => sdk.nullAware(value));
      }
      for (final value in <Object?>[null, 2, 'bad']) {
        fixture.compare('phantom', [value], () => sdk.phantom(value));
        fixture.compare('phantomCast', [value], () => sdk.phantomCast(value));
        fixture.compare('operatorChecks', [
          value,
        ], () => sdk.operatorChecks(value));
        fixture.compare('dynamicArgument', [
          value,
        ], () => sdk.dynamicArgument(value));
        fixture.compare('typeChecks', [value], () => sdk.typeChecks(value));
        fixture.compare('pattern', [value], () => sdk.pattern(value));
      }
      for (final valid in [true, false]) {
        fixture.compare('dynamicBound', [valid], () => sdk.dynamicBound(valid));
      }
      for (final (name, function) in <(String, Object? Function())>[
        ('dynamicMethodDefault', sdk.dynamicMethodDefault),
        ('dynamicListDefault', sdk.dynamicListDefault),
        ('phantomInference', sdk.phantomInference),
        ('escapedConstructor', sdk.escapedConstructor),
        ('nullableRepresentation', sdk.nullableRepresentation),
        ('widenedView', sdk.widenedView),
        ('genericOwnerAliasIdentity', sdk.genericOwnerAliasIdentity),
        ('constructorEquality', sdk.constructorEquality),
        ('constPhantomConstructors', sdk.constPhantomConstructors),
        ('rawConstructorIdentity', sdk.rawConstructorIdentity),
        (
          'instantiatedConstructorIdentity',
          sdk.instantiatedConstructorIdentity,
        ),
        ('phantomConstructorIdentity', sdk.phantomConstructorIdentity),
        ('appliedConstructorIdentity', sdk.appliedConstructorIdentity),
        ('methodIdentity', sdk.methodIdentity),
        ('patternPhantom', sdk.patternPhantom),
        ('defaultIndependent', sdk.defaultIndependent),
        ('defaultDependent', sdk.defaultDependent),
        ('defaultCovariant', sdk.defaultCovariant),
        ('defaultContravariant', sdk.defaultContravariant),
        ('defaultRecursive', sdk.defaultRecursive),
        ('defaultRecursiveContra', sdk.defaultRecursiveContra),
        ('defaultPair', sdk.defaultPair),
        ('defaultBounded', sdk.defaultBounded),
        ('defaultBoundedSuccess', sdk.defaultBoundedSuccess),
        ('defaultBoundedContra', sdk.defaultBoundedContra),
        ('neverConstructor', sdk.neverConstructor),
        ('recursiveConstructorDefault', sdk.recursiveConstructorDefault),
        ('recursive', sdk.recursive),
        ('constructorIdentity', sdk.constructorIdentity),
        ('constIdentity', sdk.constIdentity),
        ('constants', sdk.constants),
        ('erasedPhantomType', sdk.erasedPhantomType),
        ('reification', sdk.reification),
      ]) {
        fixture.compare(name, [], function);
      }
    },
  );
  test(
    'analyzer 14.7 rejects a source type-parameter extension-type member',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-extension-type-bound-',
      );
      try {
        final file = File('${directory.path}/entry.dart')
          ..writeAsStringSync("""
extension type E<T>(T value) { T get() => value; }
int read<B extends E<int>>(B value) => value.get();
void main() { print(read(E<int>(3))); }
""");
        await expectLater(
          AnalysisSession([file.path])
              .use((input) async => (await Lowering().lower(input)).program),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'diagnostic',
              contains("receiver can be 'null'"),
            ),
          ),
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
  test('generic representation erasure adds no nominal storage', () {
    expect(
      fixture.program.classes.where((c) => c.type.library.scheme != 'dart'),
      isEmpty,
    );
    final ops = fixture.program.functions
        .where((f) => f.target.library.scheme != 'dart')
        .expand((f) => f.blocks)
        .expand((b) => b.instructions);
    expect(ops.whereType<Construct>(), isEmpty);
    expect(ops.whereType<LoadField>(), isEmpty);
  });
}
