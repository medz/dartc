import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';
import 'package:test/test.dart';

/// The `exit` argument observed by running lowered code.
int? runLowered(HirModule module) {
  try {
    final result = LirInterpreter(
      lowerProgram(module),
      externals: {
        'exit': (_, arguments) => throw _Exit(arguments.single as int),
      },
    ).call(entrySymbol);
    expect(result, 0);
    return null;
  } on _Exit catch (exit) {
    return exit.code;
  }
}

final class _Exit(final int code) implements Exception;

HirModule _module(HirTerminator Function(HirBlock block) build) {
  final block = HirBlock();
  block.end(build(block));
  return HirModule(HirFunction('main', block));
}

void main() {
  const values = [0, 1, -1, 5, 0x7fffffffffffffff, -0x8000000000000000];

  test('operators agree with the Dart-level interpreter', () {
    void check(HirModule module) =>
        expect(runLowered(module), HirInterpreter(module).run());
    for (final a in values) {
      for (final operator in HirIntPrefix.values) {
        check(
          _module((block) {
            final operand = block.add(HirInt(a));
            return HirExit(block.add(HirIntUnary(operator, operand)));
          }),
        );
      }
      for (final b in values) {
        for (final operator in HirIntOperator.values) {
          check(
            _module((block) {
              final left = block.add(HirInt(a)), right = block.add(HirInt(b));
              return HirExit(block.add(HirIntBinary(operator, left, right)));
            }),
          );
        }
      }
    }
  });

  test('a program that returns ends with 0', () {
    expect(runLowered(_module((_) => HirReturn())), isNull);
  });

  test('a function named like a system function keeps its own symbol', () {
    final block = HirBlock()..end(HirReturn());
    final module = lowerProgram(HirModule(HirFunction('exit', block)));
    verifyModule(module);
  });

  test('refuses an invalid program', () {
    final module = HirModule(HirFunction('main', HirBlock()));
    expect(() => lowerProgram(module), throwsA(isA<HirError>()));
  });
}
