import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/sdk_functions.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('sdk_functions');
  });

  test('SDK constructors and inherited members use ordinary class bodies', () {
    final argument = fixture.program.classes.singleWhere(
      (c) => c.type == ValueType.argumentError,
    );
    expect(argument.type.superclass, ValueType.error);
    for (final name in ['new', 'value']) {
      expect(
        fixture.program.implementationOf(argument.constructors[name]!),
        isA<IrFunction>(),
      );
    }
    for (final value in [-0x8000000000000000, -1, 0, 0x7fffffffffffffff]) {
      fixture.compare('errorPayload', [value], () => sdk.errorPayload(value));
      fixture.compare('invalidArgument', [
        value,
      ], () => sdk.invalidArgument(value));
    }
  });

  test('SDK bodies retain identity through aliases and function values', () {
    final functions = fixture.program.functions;
    final check = functions.singleWhere(
      (f) =>
          f.target.library == Uri.parse('dart:core') &&
          f.target.name == 'checkNotNegative',
    );
    expect(check.target.owner!.name, 'RangeError');
    expect(check.defaults, hasLength(2));
    expect(
      check.blocks.expand((b) => b.instructions).whereType<Construct>(),
      isNotEmpty,
    );
    expect(check.blocks.map((b) => b.end).whereType<Throw>(), isNotEmpty);
    for (final value in [0, 1, 0x7fffffffffffffff]) {
      fixture.compare('nonnegative', [value], () => sdk.nonnegative(value));
      fixture.compare('aliasCheck', [value], () => sdk.aliasCheck(value));
      fixture.compare('sdkMixin', [value], () => sdk.sdkMixin(value));
      fixture.compare('throughValue', [value], () => sdk.throughValue(value));
      fixture.compare('local', [value], () => sdk.local(value));
    }
    expect(
      functions
          .where((f) => f.target.library == Uri.parse('dart:async'))
          .map((f) => f.target.name),
      ['unawaited'],
    );
    fixture.compare('ignoredFuture', [], sdk.ignoredFuture);
  });

  test('ordinary SDK branches and omitted arguments use the source body', () {
    for (final args in <(int, int?, int)>[
      (0, null, 0),
      (0, null, 10),
      (3, null, 10),
      (3, 3, 10),
      (3, 7, 10),
      (10, 10, 10),
    ]) {
      fixture.compare('range', [
        args.$1,
        args.$2,
        args.$3,
      ], () => sdk.range(args.$1, args.$2, args.$3));
    }
  });

  test('SDK bodies pull in further static calls with named arguments', () {
    final check = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'check' && f.target.owner?.name == 'IndexError',
    );
    final caller = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'checkValidIndex',
    );
    expect(caller.callees, contains(check.target));
    for (final (value, length) in [(0, 1), (3, 10), (9, 10)]) {
      fixture.compare('index', [value, length], () => sdk.index(value, length));
    }
  });
  test('non-numeric core operators retain their resolved member call', () {
    final function = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'subtractDuration',
    );
    expect(function.virtualMembers.single.owner!.name, 'Duration');
    expect(function.virtualMembers.single.name, '-');
  });
}
