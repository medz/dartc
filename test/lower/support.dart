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
    var error = 0, waited = 0;
    int address(LirMemory memory) => errorAddress ??= memory.map(Uint8List(4));
    final lowered = lowerProgram(module);
    final interpreter = LirInterpreter(
      lowered,
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
        'mmap': (memory, arguments) =>
            memory.map(Uint8List(arguments[1] as int)),
        for (final MapEntry(key: name, value: function) in const {
          'sin': sin,
          'cos': cos,
          'tan': tan,
          'asin': asin,
          'acos': acos,
          'atan': atan,
          'exp': exp,
          'log': log,
        }.entries)
          name: (_, arguments) => function(arguments.single as double),
        'atan2': (_, arguments) =>
            atan2(arguments[0] as double, arguments[1] as double),
        'pow': (_, arguments) =>
            pow(arguments[0] as double, arguments[1] as double).toDouble(),
        'clock_gettime_nsec_np': (_, arguments) => arguments.single == 0
            ? DateTime.now().microsecondsSinceEpoch * 1000
            : ++waited * 1000,
        // Waiting takes no time here.
        'usleep': (_, arguments) {
          waited += arguments.single as int;
          return null;
        },
        'arc4random': (_, _) => Random().nextInt(1 << 32) | 1 << 40,
        'localtime_r': (memory, arguments) {
          final [from as int, to as int] = arguments;
          final seconds = memory.load(.i64, from, 0) as int;
          final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          final name = [...ascii.encode(time.timeZoneName), 0];
          memory
            ..store(.i64, to, 40, time.timeZoneOffset.inSeconds)
            ..store(.i64, to, 48, memory.map(Uint8List.fromList(name)));
          return to;
        },
        'gcvt': (memory, arguments) {
          final [value as double, digits as int, at as int] = arguments;
          final text = formatExactly(value, digits);
          for (final (i, byte) in [...ascii.encode(text), 0].indexed) {
            memory.store(.u8, at, i, byte);
          }
          return at;
        },
        'strtod': (memory, arguments) {
          final at = arguments.first as int;
          var count = 0;
          while (memory.load(.u8, at, count) != 0) {
            count++;
          }
          return double.parse(ascii.decode(memory.read(at, count)));
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
      final parameters = lowered.signatures[entrySymbol]!.parameters;
      final result = interpreter.call(entrySymbol, [
        for (final _ in parameters) 0,
      ]);
      if (result != 0) throw StateError('The program ended with $result.');
    } on _Exit catch (exit) {
      code = exit.code;
    }
  }
}

/// The `exit` argument observed by running lowered code.
int? runLowered(HirModule module) => LoweredRun(module).code;

final class _Exit(final int code) implements Exception;
