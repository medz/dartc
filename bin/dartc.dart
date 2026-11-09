import 'dart:io';

import 'package:dartc/src/compiler/cli/command.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await CompilerCommand(stdout, stderr).run(arguments);
}
