import 'dart:io';

import 'package:dartc/compiler.dart';
import 'package:dartc/target.dart';

/// Compiles one benchmark input in its own VM using the public compiler API.
Future<void> main(List<String> arguments) async {
  final [source, kind, target, destination] = arguments;
  final file = File(destination);
  final output = switch (kind) {
    'executable' => const Output.executable(),
    'shared' => Output.sharedLibrary(file.uri.pathSegments.last),
    _ => throw ArgumentError.value(kind, 'kind'),
  };
  final product = await Compiler(Target.parse(target))
      .compile([source], output: output);
  await product.write(file);
}
