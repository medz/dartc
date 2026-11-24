import 'dart:io';

import 'package:dartc/driver.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCommand(arguments, output: stdout, errors: stderr);
}
