import 'dart:io';

import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_types_interfaces.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = FixtureComparison(
      await AnalysisSession([
        'test/frontend/lowering/fixtures/extension_types_interfaces.dart',
        'test/frontend/lowering/fixtures/extension_types_interfaces_other.dart',
      ]).use((input) async => (await Lowering().lower(input)).program),
    );
  });
  test('inherited extension members retain source owner type arguments', () {
    for (final seed in [0, 3, 7]) {
      fixture.compare('ordinaryView', [seed], () => sdk.ordinaryView(seed));
      fixture.compare('sourceBound', [seed], () => sdk.sourceBound(seed));
      fixture.compare('inherited', [seed], () => sdk.inherited(seed));
      fixture.compare('inheritedRepresentation', [
        seed,
      ], () => sdk.inheritedRepresentation(seed));
      fixture.compare('inheritedRecord', [
        seed,
      ], () => sdk.inheritedRecord(seed));
      fixture.compare('inheritedFunction', [
        seed,
      ], () => sdk.inheritedFunction(seed));
      fixture.compare('dispatched', [seed], () => sdk.dispatched(seed));
      fixture.compare('coreList', [seed], () => sdk.coreList(seed));
      fixture.compare('interfacePattern', [
        seed,
      ], () => sdk.interfacePattern(seed));
    }
    for (final value in <int?>[null, 3]) {
      fixture.compare('inheritedNullable', [
        value,
      ], () => sdk.inheritedNullable(value));
    }
    for (final value in <Object?>[2, 2.5, null]) {
      fixture.compare('covariantInterface', [
        value,
      ], () => sdk.covariantInterface(value));
      fixture.compare('covariantTearOff', [
        value,
      ], () => sdk.covariantTearOff(value));
    }
    for (final (name, function) in <(String, Object? Function())>[
      ('inheritedDefaults', sdk.inheritedDefaults),
      ('mostSpecific', sdk.mostSpecific),
      ('privateLibrary', sdk.privateLibrary),
      ('inheritedPatternViews', sdk.inheritedPatternViews),
      ('multiple', sdk.multiple),
      ('overridden', sdk.overridden),
      ('methods', sdk.methods),
      ('defaultMethod', sdk.defaultMethod),
      ('operators', sdk.operators),
      ('objectMember', sdk.objectMember),
      ('patterns', sdk.patterns),
    ]) {
      fixture.compare(name, [], function);
    }
  });
  test(
    'analyzer retains interface conflicts and representation constraints',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'dartc-extension-interface-errors-',
      );
      try {
        for (final source in [
          'extension type A(int value) { int m() => 1; } extension type B(int value) implements A { int m() => 2; } extension type C(int value) implements A, B {}',
          'extension type E(int value) implements String {}',
          'extension type E(int Function() value) implements Function {}',
        ]) {
          final file = File('${directory.path}/entry.dart')
            ..writeAsStringSync(source);
          await expectLater(
            AnalysisSession([file.path])
                .use((input) async => (await Lowering().lower(input)).program),
            throwsA(isA<FormatException>()),
          );
        }
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );
  test('extension interfaces do not create nominal classes', () {
    expect(
      fixture.program.classes
          .where((c) => c.type.library.scheme != 'dart')
          .map((c) => c.type.name)
          .toSet(),
      {'Interface', 'Representation', 'Specialized'},
    );
    final inherited = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'inherited',
    );
    expect(
      inherited.blocks.expand((b) => b.instructions).whereType<InstanceCall>(),
      isEmpty,
    );
  });
}
