import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/native.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';

/// Compiles the program at [path] to an executable for [target].
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
///
/// If [collectsAlways], the program collects before every allocation.
Future<Uint8List> compileProgram(
  String path, {
  Target target = .macosArm64,
  bool collectsAlways = false,
}) async {
  final program = translateProgram(
    await loadProgram(path, sdk: await packagedSdk(target)),
    target: target,
  );
  final lowered = lowerProgram(
    program,
    system: target.system,
    collectsAlways: collectsAlways,
  );
  final code = emitCode(lowered, target: target, entry: entrySymbol);
  return switch (target.system) {
    .macos => linkMacho(
      code,
      entry: entrySymbol,
      identifier: Uri.file(path).pathSegments.last,
    ),
    .linux => linkElf(code, entry: linuxEntrySymbol),
  };
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
  final code = emitCode(lowerProgram(module, collectsAlways: collectsAlways));
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

final _sdks = <Target, Future<SdkSources>>{};

/// The standard libraries that come with the compiler, for [target].
Future<SdkSources> packagedSdk([Target target = .macosArm64]) =>
    _sdks[target] ??= _findSdk(target);

Future<SdkSources> _findSdk(Target target) async {
  final package = Uri.parse('package:dartc/heap.dart');
  final file = await Isolate.resolvePackageUri(package);
  if (file == null) throw StateError('$package is missing.');
  return SdkSources(
    root: file.resolve('../sdk/std').toFilePath(),
    patches: file.resolve('../sdk/native').toFilePath(),
    runtime: file.resolve('src/heap').toFilePath(),
    systems: [target.system.name, target.label],
  );
}

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
