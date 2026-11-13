import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/cascades.dart' as cascades;
import 'fixtures/dot_shorthand.dart' as shorthand;
import 'fixtures/effects.dart' as effects;
import 'fixtures/static_accessors.dart' as accessors;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    const dir = 'test/frontend/lowering/fixtures';
    final program = await AnalysisSession([
      '$dir/cascades.dart',
      '$dir/dot_shorthand.dart',
      '$dir/static_accessors.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    functions = {
      for (final f in program.functions)
        if (f.target.owner == null && f.target.enclosing == null)
          f.target.name: f,
    };
    runner = IrInterpreter(program, {
      (Uri.base.resolve('$dir/effects.dart'), 'tick'): effects.tick,
      (Uri.base.resolve('$dir/effects.dart'), 'probe'): effects.probe,
    });
  });
  void compare(String name, List<Object?> args, Object? Function() sdk) {
    effects.calls.clear();
    final expected = sdk();
    final trace = List.of(effects.calls);
    effects.calls.clear();
    expect(runner.run(functions[name]!, args), expected);
    expect(effects.calls, trace);
  }

  test('cascade receiver, updates, index, nesting and null shortening', () {
    for (final n in [-1, 0, 7]) {
      for (final missing in [false, true]) {
        compare('cascade', [n, missing], () => cascades.cascade(n, missing));
      }
    }
  });
  test('ordinary cascade returns receiver', () {
    compare('ordinaryCascade', [8], () => cascades.ordinaryCascade(8));
  });
  test('null cascade skips throws and non-null cascade propagates throws', () {
    for (final missing in [false, true]) {
      compare('cascadeThrow', [missing], () => cascades.cascadeThrow(missing));
    }
  });
  test('function and record cascades', () {
    compare('callableCascade', [8], () => cascades.callableCascade(8));
    compare('recordCascade', [9], () => cascades.recordCascade(9));
  });
  test('static and top-level getters, setters and updates', () {
    for (final n in [-1, 0, 7]) {
      for (var mode = 0; mode < 10; mode++) {
        compare('access', [n, mode], () => accessors.access(n, mode));
      }
    }
    compare('shorthandGetter', [], accessors.shorthandGetter);
    for (final n in [-1, 0, 7]) {
      compare('prefixedAccess', [n], () => cascades.prefixedAccess(n));
    }
  });
  test('dot shorthand constructors, factories and static methods', () {
    for (final n in [-1, 0, 7]) {
      for (var mode = 0; mode < 4; mode++) {
        compare('shorthand', [n, mode], () => shorthand.shorthand(n, mode));
      }
    }
  });
}
