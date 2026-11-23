import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';

/// The `exit` argument observed by running lowered code.
int? runLowered(HirModule module) {
  try {
    final result = LirInterpreter(
      lowerProgram(module),
      externals: {
        'exit': (_, arguments) => throw _Exit(arguments.single as int),
        'fmod': (_, arguments) =>
            (arguments[0] as double).remainder(arguments[1] as double),
      },
    ).call(entrySymbol);
    if (result != 0) throw StateError('The program ended with $result.');
    return null;
  } on _Exit catch (exit) {
    return exit.code;
  }
}

final class _Exit(final int code) implements Exception;
