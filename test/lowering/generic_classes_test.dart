import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/generic_classes.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('generic_classes');
  });

  test('generic instances share one declaration and method body', () {
    final declarations = fixture.program.classes
        .where((c) => c.type.name == 'Box')
        .toList();
    expect(declarations, hasLength(1));
    final declaration = declarations.single.type;
    expect(declaration.typeParameters, hasLength(1));
    expect(
      fixture.program.functions.where(
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
          fixture.compare(name, [seed], () => function(seed));
        }
      }
    },
  );

  test('applied constructor tearoffs have distinct identity', () {
    fixture.compare(
      'genericConstructorIdentity',
      [],
      sdk.genericConstructorIdentity,
    );
    fixture.compare('genericVariance', [], sdk.genericVariance);
    fixture.compare('genericRecursiveBound', [], sdk.genericRecursiveBound);
    fixture.compare('genericSelfHierarchy', [], sdk.genericSelfHierarchy);
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
        fixture.compare(name, [candidate], () => function(candidate));
      }
    }
  });
}
