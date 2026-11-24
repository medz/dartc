import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';

/// Compiles the program at [path] to a macOS ARM64 executable.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
///
/// If [collectsAlways], the program collects before every allocation.
Future<Uint8List> compileProgram(
  String path, {
  bool collectsAlways = false,
}) async {
  final program = translateProgram(
    await loadProgram(path, sdk: await packagedSdk()),
  );
  final code = emitArm64(lowerProgram(program, collectsAlways: collectsAlways));
  final name = Uri.file(path).pathSegments.last;
  return linkMacho(code, entry: entrySymbol, identifier: name);
}

/// What can be made of a library.
enum LibraryKind() {
  object,
  static,
  shared,
}

/// Compiles the library at [path] for macOS ARM64. Also gives a header of C for
/// the functions that it exports.
///
/// [name] is what the file will be called. Programs load a shared library from
/// where that is.
///
/// Throws [CompileFailure] if the library has an error or is not supported yet.
Future<({Uint8List bytes, String header})> compileLibrary(
  String path,
  LibraryKind kind, {
  required String name,
  bool collectsAlways = false,
}) async {
  final (:module, :header) = translateLibrary(
    await loadProgram(path, sdk: await packagedSdk()),
  );
  final code = emitArm64(lowerProgram(module, collectsAlways: collectsAlways));
  final file = Uri.file(name).pathSegments.last;
  return (
    bytes: switch (kind) {
      .object => writeMachoObject(code),
      .static => writeArchive(
        writeMachoObject(code),
        '$file.o',
        code.exports.keys,
      ),
      .shared => linkMachoLibrary(
        code,
        name: File(name).absolute.path,
        identifier: file,
      ),
    },
    header: header,
  );
}

Future<SdkSources>? _sdk;

/// The standard libraries that come with the compiler.
Future<SdkSources> packagedSdk() => _sdk ??= () async {
  final package = Uri.parse('package:dartc/heap.dart');
  final file = await Isolate.resolvePackageUri(package);
  if (file == null) throw StateError('$package is missing.');
  return SdkSources(
    root: file.resolve('../sdk/std').toFilePath(),
    patches: file.resolve('../sdk/native').toFilePath(),
    runtime: file.resolve('src/heap').toFilePath(),
  );
}();

/// Writes an executable file, replacing [output] only once it is complete.
void writeProgram(Uint8List program, String output) {
  final staged = File('$output.tmp-$pid');
  try {
    staged.writeAsBytesSync(program, flush: true);
    final result = Process.runSync('/bin/chmod', ['+x', staged.path]);
    if (result.exitCode != 0) {
      throw FileSystemException('${result.stderr}', staged.path);
    }
    staged.renameSync(output);
  } finally {
    if (staged.existsSync()) staged.deleteSync();
  }
}
