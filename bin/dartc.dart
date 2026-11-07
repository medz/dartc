import 'dart:io';

import 'package:dartc/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await CompilerCommand(stdout, stderr).run(arguments);
}
