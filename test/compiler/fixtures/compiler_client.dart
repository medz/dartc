import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';

Future<void> main(List<String> arguments) async {
  final compiler = Compiler(
    Target.host(),
    resources: SourceArchive(File(arguments[0]).readAsBytesSync()),
  );
  final result = await compiler.compile([
    arguments[1],
  ], output: const .executable());
  await result.write(File(arguments[2]));
}
