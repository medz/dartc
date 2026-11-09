import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import '../../support/numeric_order.dart';
import 'fixtures/numeric.dart' as sdk;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/numeric.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {});
    functions = {for (final f in program.functions) f.target.name: f};
  });

  void compare(String name, List<num> args, Function reference) {
    Object? expected;
    try {
      expected = switch (name) {
        'less' => (numericOrder(args[0], args[1]) ?? 1) < 0,
        'lessEqual' => (numericOrder(args[0], args[1]) ?? 1) <= 0,
        'greater' => (numericOrder(args[0], args[1]) ?? -1) > 0,
        'greaterEqual' => (numericOrder(args[0], args[1]) ?? -1) >= 0,
        _ => Function.apply(reference, args),
      };
    } catch (e) {
      expect(
        () => runner.run(functions[name]!, args),
        throwsA(
          predicate((Object actual) => actual.runtimeType == e.runtimeType),
        ),
        reason: '$name($args)',
      );
      return;
    }
    final actual = runner.run(functions[name]!, args);
    expect(actual.runtimeType, expected.runtimeType, reason: '$name($args)');
    if (expected is double && expected.isNaN) {
      expect(actual, isNaN);
    } else {
      expect(actual, expected, reason: '$name($args)');
      if (expected is double && expected == 0) {
        expect((actual as double).isNegative, expected.isNegative);
      }
    }
  }

  test('numeric operations preserve specified values, representations and exceptions', () {
    const values = <num>[
      -0x8000000000000000,
      -9007199254740993,
      -7,
      -1,
      0,
      1,
      7,
      9007199254740993,
      0x7fffffffffffffff,
      -double.infinity,
      -7.5,
      -1.0,
      -0.0,
      0.0,
      1.0,
      2.5,
      9007199254740992.0,
      double.infinity,
      double.nan,
    ];
    final binary = <String, Function>{
      'add': sdk.add,
      'subtract': sdk.subtract,
      'multiply': sdk.multiply,
      'divide': sdk.divide,
      'truncate': sdk.truncate,
      'modulo': sdk.modulo,
      'less': sdk.less,
      'lessEqual': sdk.lessEqual,
      'greater': sdk.greater,
      'greaterEqual': sdk.greaterEqual,
      'compound': sdk.compound,
      'caughtTruncate': sdk.caughtTruncate,
      'caughtModulo': sdk.caughtModulo,
    };
    for (final a in values) {
      compare('negate', [a], sdk.negate);
      compare('increment', [a], sdk.increment);
      compare('convertNumber', [a], sdk.convertNumber);
      if (a is double) compare('negateDouble', [a], sdk.negateDouble);
      for (final b in values) {
        for (final entry in binary.entries) {
          compare(entry.key, [a, b], entry.value);
        }
        if (a is int && b is double) {
          compare('mixedAdd', [a, b], sdk.mixedAdd);
        }
        if (a is double) compare('doubleModulo', [a, b], sdk.doubleModulo);
      }
    }
  });

  test('numeric conversion only binds the resolved SDK declaration', () {
    expect(runner.run(functions['userConversion']!, []), 7.5);
    expect(runner.run(functions['extensionConversion']!, []), 8.5);
    expect(
      functions['convertNumber']!.blocks
          .expand((b) => b.instructions)
          .whereType<NumericToDouble>(),
      hasLength(1),
    );
  });

  test('numeric IR validates operands, types and exceptional behavior', () {
    const integer = Constant.integer(1);
    const floating = Constant.floating(1);
    final number = Block([ValueType.number]).parameters.single;
    expect(NumericBinary(.add, integer, floating).type, ValueType.floating);
    expect(NumericBinary(.add, number, integer).type, ValueType.number);
    expect(NumericBinary(.divide, number, integer).type, ValueType.floating);
    expect(
      NumericBinary(.truncateDivide, number, floating).type,
      ValueType.integer,
    );
    expect(NumericBinary(.lessThan, number, floating).type, ValueType.boolean);
    expect(NumericBinary(.modulo, number, integer).mayThrow, isTrue);
    expect(NumericBinary(.modulo, number, floating).mayThrow, isFalse);
    expect(NumericBinary(.truncateDivide, floating, floating).mayThrow, isTrue);
    expect(NumericBinary(.divide, number, integer).mayThrow, isFalse);
    expect(NumericNegate(floating).mayThrow, isFalse);
    expect(
      () => NumericBinary(.add, integer, const Constant.nullValue()),
      throwsArgumentError,
    );
    expect(
      () => NumericNegate(const Constant.boolean(false)),
      throwsArgumentError,
    );
  });
}
