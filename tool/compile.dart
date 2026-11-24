import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

const _usage = '''
Usage: dart run tool/compile.dart [options] <source> <output>

  --kind <kind>      exe, which is the default, object, static or shared
  --target <target>  macos_arm64, which is the default, or linux_arm64
  --header <path>    where to write declarations for C
''';

Never _fail() {
  stderr.write(_usage);
  exit(64);
}

/// Compiles a Dart program or library with the new compiler.
Future<void> main(List<String> arguments) async {
  final paths = <String>[];
  var kind = 'exe';
  var target = Target.macosArm64;
  String? header;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--kind' when i + 1 < arguments.length:
        kind = arguments[++i];
      case '--target' when i + 1 < arguments.length:
        final label = arguments[++i];
        target = Target.values.firstWhere(
          (target) => target.label == label,
          orElse: _fail,
        );
      case '--header' when i + 1 < arguments.length:
        header = arguments[++i];
      case final option when option.startsWith('-'):
        _fail();
      case final path:
        paths.add(path);
    }
  }
  final library = LibraryKind.values
      .where((value) => value.name == kind)
      .firstOrNull;
  if (paths.length != 2 || library == null && kind != 'exe') _fail();
  if (library == null && header != null) _fail();
  final [source, output] = paths;
  try {
    if (library == null) {
      writeProgram(await compileProgram(source, target: target), output);
      return;
    }
    final made = await compileLibrary(source, library, name: output);
    writeProgram(made.bytes, output);
    if (header != null) File(header).writeAsStringSync(made.header);
  } on CompileFailure catch (failure) {
    stderr.writeln(failure);
    exit(1);
  }
}
