import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';
import 'package:dartc/lower.dart';

/// Lowered code running with a simulated operating system.
final class LoweredRun(
  HirModule module, {

  /// How many of the bytes offered to each write are accepted; a negative
  /// answer fails with that error number.
  final int Function(int count)? accept,
  int maxSteps = 10000000,
}) {
  final _written = BytesBuilder(), _errors = BytesBuilder();

  /// The calls made to the system, in order.
  final List<String> calls = [];

  /// The argument of `exit`, or null if the program returned.
  int? code;
  String get output => utf8.decode(_written.toBytes());
  List<int> get errorBytes => _errors.toBytes();
  String get errors => utf8.decode(errorBytes);

  this {
    int? errorAddress;
    var error = 0;
    int address(LirMemory memory) => errorAddress ??= memory.map(Uint8List(4));
    final interpreter = LirInterpreter(
      lowerProgram(module),
      maxSteps: maxSteps,
      externals: {
        'exit': (_, arguments) => throw _Exit(arguments.single as int),
        'fmod': (_, arguments) =>
            (arguments[0] as double).remainder(arguments[1] as double),
        'signal': (_, arguments) {
          calls.add('signal$arguments');
          return 0;
        },
        'pthread_self': (_, _) => 1,
        'pthread_get_stackaddr_np': (_, _) => 1 << 40,
        'pthread_get_stacksize_np': (_, _) => 1 << 23,
        '__error': (memory, _) {
          final at = address(memory);
          memory.store(.i32, at, 0, error);
          return at;
        },
        'write': (memory, arguments) {
          final [descriptor as int, from as int, count as int] = arguments;
          calls.add('write$descriptor');
          final accepted = accept?.call(count) ?? count;
          if (accepted < 0) {
            error = -accepted;
            return -1;
          }
          (descriptor == 1 ? _written : _errors).add(
            memory.read(from, min(accepted, count)),
          );
          return min(accepted, count);
        },
      },
    );
    try {
      final result = interpreter.call(entrySymbol);
      if (result != 0) throw StateError('The program ended with $result.');
    } on _Exit catch (exit) {
      code = exit.code;
    }
  }
}

/// The `exit` argument observed by running lowered code.
int? runLowered(HirModule module) => LoweredRun(module).code;

final class _Exit(final int code) implements Exception;
