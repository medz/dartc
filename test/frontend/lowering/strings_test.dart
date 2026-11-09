import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/strings.dart' as sdk;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/strings.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {});
    functions = {
      for (final f in program.functions)
        if (f.target.owner == null) f.target.name: f,
    };
  });

  void compare(String name, List<Object?> args, Function reference) {
    expect(
      runner.run(functions[name]!, args),
      Function.apply(reference, args),
      reason: '$name($args)',
    );
  }

  test('interpolation and adjacent strings match native scalar formatting', () {
    const values = <Object?>[
      null,
      false,
      true,
      -7,
      0,
      1,
      -0.0,
      2.5,
      double.nan,
      double.infinity,
      'hello',
      '🌈\n\u0000',
    ];
    for (final a in values) {
      compare('recordValue', [a], sdk.recordValue);
      for (final b in values) {
        compare('scalars', [a, b], sdk.scalars);
        compare('adjacent', [a, b], sdk.adjacent);
      }
    }
    compare('concat', ['a\n', '🌈'], sdk.concat);
    compare('compound', ['a', 'b'], sdk.compound);
  });

  test('conversion dispatch and effects follow SDK evaluation order', () {
    for (final fail in [false, true]) {
      compare('order', [fail], sdk.order);
      compare('adjacentOrder', [fail], sdk.adjacentOrder);
    }
    compare('nestedOrder', [], sdk.nestedOrder);
    compare('parenthesizedOrder', [], sdk.parenthesizedOrder);
    compare('conditionalOrder', [true], sdk.conditionalOrder);
    compare('conditionalOrder', [false], sdk.conditionalOrder);
    compare('recordOrder', [], sdk.recordOrder);
    compare('plainObject', [], sdk.plainObject);
    compare('virtualObject', [], sdk.virtualObject);
  });

  test('string IR carries typed operands and exception edges', () {
    final interpolation = Interpolate([const Constant.nullValue()]);
    expect(interpolation.type, ValueType.string);
    expect(interpolation.mayThrow, isTrue);
    expect(
      () => StringConcat(const Constant.integer(1), const Constant.string('a')),
      throwsArgumentError,
    );
  });
}
