import 'dart:io';

import 'package:dartc/lowering.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !File(args.single).existsSync()) {
    stderr.writeln('Usage: dart run tool/print_ir.dart <library.dart>');
    exitCode = 64;
    return;
  }
  try {
    for (final function in await CheckedLibraries.read(args, Lowering.lower)) {
      function.writeTo(stdout);
    }
  } on FormatException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on UnsupportedError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
