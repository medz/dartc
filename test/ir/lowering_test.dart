import 'dart:io';

import 'package:dartc/src/_internal/checked_libraries.dart';
import 'package:dartc/src/_internal/ir/ir.dart';
import 'package:dartc/src/_internal/lowering/dart_lowering.dart';
import 'package:test/test.dart';

import 'fixtures/effects.dart' as effects;
import 'fixtures/functions.dart' as dart;

Future<List<IrFunction>> _lower(List<String> paths) =>
    CheckedLibraries.read(paths, DartLowering.lower);

void main() {
  late Map<String, IrFunction> functions;
  late Map<FunctionTarget, IrFunction> bodies;
  late Map<FunctionTarget, Object? Function(int)> imports;
  setUpAll(() async {
    final result = await _lower(['test/ir/fixtures/functions.dart']);
    functions = {for (final f in result) f.target.name: f};
    bodies = {for (final f in result) f.target: f};
    imports = {
      for (final f in result)
        for (final b in f.blocks)
          for (final call in b.instructions.whereType<DirectCall>())
            if (call.target.library.path.endsWith('/effects.dart'))
              call.target: switch (call.target.name) {
                'tick' => effects.tick,
                'probe' => effects.probe,
                _ => throw StateError('Unknown fixture import'),
              },
    };
  });

  Object? execute(IrFunction function, List<Object?> args) {
    final values = <Value, Object?>{};
    Object? read(Value v) => v is Constant ? v.value : values[v];
    var block = function.entry;
    for (var steps = 0; steps < 1000; steps++) {
      for (final (i, p) in block.parameters.indexed) {
        values[p] = args[i];
      }
      for (final op in block.instructions) {
        switch (op) {
          case IntBinary(:final operator, :final left, :final right):
            final a = read(left) as int, b = read(right) as int;
            values[op] = switch (operator) {
              .add => a + b,
              .subtract => a - b,
              .multiply => a * b,
              .lessThan => a < b,
            };
          case DirectCall(:final target, :final inputs):
            final arguments = inputs.map(read).toList();
            values[op] = bodies.containsKey(target)
                ? execute(bodies[target]!, arguments)
                : imports[target]!(arguments.single as int);
        }
      }
      final end = block.end;
      if (end is Return) return end.value == null ? null : read(end.value!);
      final edge = switch (end) {
        Jump() => end,
        Branch() => read(end.condition) as bool ? end.ifTrue : end.ifFalse,
        Return() => throw StateError('Already returned'),
      };
      args = edge.arguments.map(read).toList();
      block = edge.target;
    }
    fail(
      'Fixture did not return in 1000 block visits: ${function.target.name}',
    );
  }

  void compare(String name, List<Object?> args, Object? Function() sdk) {
    (Object?, List<int>) observe(Object? Function() run) {
      effects.calls.clear();
      try {
        return (run(), List.of(effects.calls));
      } on StateError catch (e) {
        return (e.message, List.of(effects.calls));
      }
    }

    final (expected, trace) = observe(sdk);
    final (actual, calls) = observe(() => execute(functions[name]!, args));
    expect(actual, expected);
    expect(calls, trace);
  }

  test(
    'short circuit skips calls and propagates exceptions from taken paths',
    () {
      for (final a in [false, true]) {
        for (final b in [false, true]) {
          for (final n in [-1, 0, 1]) {
            compare('gate', [a, b, n], () => dart.gate(a, b, n));
          }
        }
      }
    },
  );
  test(
    'named calls preserve evaluation order and discarded calls still run',
    () {
      for (final n in [-1, 3]) {
        compare('ordered', [n], () => dart.ordered(n));
        compare('discard', [n], () {
          dart.discard(n);
          return null;
        });
        for (final flag in [false, true]) {
          compare('nestedArguments', [
            n,
            flag,
          ], () => dart.nestedArguments(n, flag));
        }
      }
    },
  );
  test('void functions preserve observable return values through calls', () {
    compare('voidResult', [42], () => Function.apply(dart.voidResult, [42]));
    compare('forwardVoid', [42], () => Function.apply(dart.forwardVoid, [42]));
    compare('discard', [42], () => Function.apply(dart.discard, [42]));
  });
  test('loop-carried variables, branch joins and early returns match Dart', () {
    compare('literalBranch', [], dart.literalBranch);
    for (final flag in [false, true]) {
      for (final n in [0, 1, 6]) {
        compare('sum', [n, flag], () => dart.sum(n, flag));
      }
      compare('early', [flag], () => dart.early(flag));
    }
  });
  test('an unused invalid declaration in a part prevents lowering', () async {
    final dir = await Directory.systemTemp.createTemp('dartc_ir_');
    addTearDown(() => dir.delete(recursive: true));
    final entry = File('${dir.path}/entry.dart')
      ..writeAsStringSync("part 'other.dart'; int entry() => 1;");
    File('${dir.path}/analysis_options.yaml').writeAsStringSync(
      'analyzer:\n  errors:\n    return_of_invalid_type: ignore\n',
    );
    File('${dir.path}/other.dart').writeAsStringSync(
      "part of 'entry.dart';\n// ignore_for_file: return_of_invalid_type\nint unused() { return 1; return false; }",
    );
    await expectLater(
      _lower([entry.path]),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'diagnostic location',
          contains('other.dart'),
        ),
      ),
    );
  });
  test('same-named imports keep distinct declaration identities', () async {
    final dir = await Directory.systemTemp.createTemp('dartc_ir_imports_');
    addTearDown(() => dir.delete(recursive: true));
    final files = [
      File('${dir.path}/client.dart')..writeAsStringSync(
        "import 'a.dart' as a; import 'b.dart' as b; int both() => a.f() - b.f();",
      ),
      File('${dir.path}/a.dart')..writeAsStringSync('int f() => 10;'),
      File('${dir.path}/b.dart')..writeAsStringSync('int f() => 4;'),
    ];
    final paths = [for (final file in files) file.path];
    final [client, a, b] = await _lower(paths);
    expect(
      client.entry.instructions.whereType<DirectCall>().map((c) => c.target),
      [a.target, b.target],
    );
    await expectLater(_lower([paths.first, paths.first]), throwsArgumentError);
  });
  test('lazy locals remain an explicit gap with a source location', () async {
    final dir = await Directory.systemTemp.createTemp('dartc_ir_late_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/lazy.dart')
      ..writeAsStringSync('int f() {\n  late int v = 1;\n  return v;\n}');
    await expectLater(
      _lower([file.path]),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'source location',
          contains('lazy.dart:2:'),
        ),
      ),
    );
  });
  test(
    'analysis keeps the package language version and package URI bindings',
    () async {
      final dir = await Directory.systemTemp.createTemp('dartc_ir_package_');
      addTearDown(() => dir.delete(recursive: true));
      Directory('${dir.path}/.dart_tool').createSync();
      Directory('${dir.path}/lib').createSync();
      File('${dir.path}/.dart_tool/package_config.json').writeAsStringSync(
        '{"configVersion":2,"packages":[{"name":"demo","rootUri":"../","packageUri":"lib/","languageVersion":"3.5"}]}',
      );
      final other = File('${dir.path}/lib/other.dart')
        ..writeAsStringSync('int getValue() => 1;');
      final entry = File('${dir.path}/entry.dart')
        ..writeAsStringSync(
          "import 'package:demo/other.dart'; int f() => getValue();",
        );
      final [f, dependency] = await _lower([entry.path, other.path]);
      final call = f.entry.instructions.single as DirectCall;
      expect(call.target.library.toString(), 'package:demo/other.dart');
      expect(call.target, same(dependency.target));
      other.writeAsStringSync('int getValue() => 1_000;');
      await expectLater(
        _lower([entry.path, other.path]),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
