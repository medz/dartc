import 'dart:io';

import 'package:dartc/driver.dart';

const _usage = '''
Usage: dart run tool/size.dart <program> [function] [--top=<n>]

Tells what the bytes of the program are made of: each part of the file, the
largest functions and the bytes of each library and class. With a function,
named by its symbol or by what follows the number in it, tells why each one
that matches is part of the program.''';

/// What the bytes of a program are made of, and why functions are in it.
Future<void> main(List<String> arguments) async {
  final top = arguments.where((argument) => argument.startsWith('--top='));
  final rest = [
    for (final argument in arguments)
      if (!argument.startsWith('--top=')) argument,
  ];
  final count = top.isEmpty ? 30 : int.tryParse(top.last.substring(6));
  if (rest.isEmpty || rest.length > 2 || count == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final sizes = await measureProgram(rest.first);
  if (rest case [_, final name]) {
    _why(sizes, name);
  } else {
    _summary(rest.first, sizes, count);
  }
}

void _summary(String path, ProgramSizes sizes, int count) {
  final total = sizes.fileBytes;
  print('$path: ${_bytes(total)} bytes\n');
  _table(
    'part',
    [
      for (final MapEntry(:key, :value) in sizes.parts.entries)
        (key, value, null),
    ]..sort((a, b) => b.$2.compareTo(a.$2)),
    total,
  );
  final functions = sizes.functions;
  _table('function', [
    for (final function in functions.take(count))
      (function.name, function.bytes, null),
  ], total);
  _table(
    'library',
    _sum(functions, (f) => '${f.library ?? '(compiler)'}'),
    total,
  );
  _table(
    'class',
    _sum(
      functions,
      (f) => switch (f.owner) {
        final owner? => '$owner (${f.library})',
        null => '(none)',
      },
    ).take(count),
    total,
  );
}

/// The bytes and number of functions of each key, largest first.
List<(String, int, int?)> _sum(
  List<FunctionSize> functions,
  String Function(FunctionSize function) keyOf,
) {
  final bytes = <String, int>{}, counts = <String, int>{};
  for (final function in functions) {
    final key = keyOf(function);
    bytes[key] = (bytes[key] ?? 0) + function.bytes;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return [
    for (final MapEntry(:key, :value) in bytes.entries)
      (key, value, counts[key]),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
}

void _table(String what, Iterable<(String, int, int?)> rows, int total) {
  final hasCounts = rows.any((row) => row.$3 != null);
  print(
    '${what.padRight(60)}      bytes      %${hasCounts ? '  functions' : ''}',
  );
  for (final (name, bytes, count) in rows) {
    final share = (100 * bytes / total).toStringAsFixed(1);
    final shown = name.length > 60 ? '${name.substring(0, 57)}...' : name;
    print(
      '${shown.padRight(60)} ${_bytes(bytes).padLeft(10)} ${share.padLeft(6)}'
      '${count == null ? '' : '$count'.padLeft(11)}',
    );
  }
  print('');
}

void _why(ProgramSizes sizes, String name) {
  final found = [
    for (final function in sizes.functions)
      if (function.name == name ||
          function.name.replaceFirst(RegExp(r'^dart\.\d+\.'), '') == name)
        function,
  ];
  if (found.isEmpty) {
    stderr.writeln('No function of the program is called $name.');
    exitCode = 1;
  }
  for (final function in found) {
    final from = function.library ?? 'the compiler';
    print('${function.name}: ${_bytes(function.bytes)} bytes, from $from');
    if (function.why.isEmpty) {
      print('  made while lowering, for what the program needs of the machine');
    }
    for (final (i, (:name, :how, :createdBy)) in function.why.indexed) {
      final created = createdBy == null ? '' : ' (objects made in $createdBy)';
      final next = i + 1 < function.why.length ? ' in' : '';
      print('  $name: $how$created$next');
    }
    print('');
  }
}

/// [value] with commas between thousands.
String _bytes(int value) =>
    '$value'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
