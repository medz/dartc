import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/sdk_calls.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async => fixture = await FixtureComparison.load('sdk_calls'));

  test('SDK calls retain declaration identity and available source bodies', () {
    final calls = fixture.program.functions.expand(
      (function) => function.callees.followedBy(function.virtualMembers),
    );
    expect(
      calls
          .where((target) => target.library == Uri.parse('dart:core'))
          .map((target) => target.name),
      containsAll([
        'join',
        'take',
        'toList',
        'compareByIndex',
        'compareByName',
        '<extension:EnumByName:method:byName>',
        '<extension:EnumByName:method:asNameMap>',
      ]),
    );
    final join = calls.firstWhere(
      (target) => target.name == 'join' && target.owner == CoreTypes.iterable,
    );
    expect(fixture.program.implementationOf(join), isA<IrFunction>());
  });

  test('SDK constants retain their declared field storage', () {
    final duration = fixture.program.functions
        .singleWhere((f) => f.target.name == 'duration')
        .objects
        .single;
    expect(
      duration.type,
      isA<ClassType>().having((type) => type.name, 'name', 'Duration'),
    );
    expect(
      duration.fields.values.single,
      isA<ScalarConstant>().having(
        (constant) => constant.value,
        'microseconds',
        const Duration(seconds: 2).inMicroseconds,
      ),
    );
  });

  test(
    'SDK interface calls preserve user overrides and evaluate arguments once',
    () {
      fixture.compare('virtualCalls', [], sdk.virtualCalls);
    },
  );
}
