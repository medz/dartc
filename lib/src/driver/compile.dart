import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/emit.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/image.dart';
import 'package:dartc/lower.dart';
import 'package:dartc/native.dart';
import 'package:dartc/optimize.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';

import 'sdk.dart';

/// How to compile.
final class const CompileOptions({
  final Target target = .macosArm64,

  /// What is done to make programs fast.
  final Set<Optimization> optimizations = const {...Optimization.values},

  /// What `String.fromEnvironment` and the like know.
  final Map<String, String> environment = const {},

  /// Whether programs check assertions.
  final bool checksAssertions = false,

  /// Whether programs collect before every allocation.
  final bool collectsAlways = false,

  /// The sources of the SDK, if not those that come with this package.
  final SdkFiles? sdk,
});

/// What this machine runs, if it is supported.
Target? get hostTarget => switch (Abi.current()) {
  .macosArm64 => .macosArm64,
  .linuxArm64 => .linuxArm64,
  .linuxX64 => .linuxX64,
  _ => null,
};

/// Compiles the program at [path] to an executable.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
Future<Uint8List> compileProgram(
  String path, [
  CompileOptions options = const CompileOptions(),
]) async {
  final target = options.target;
  final module = translateProgram(
    await _load(path, options),
    target: target,
    checksAssertions: options.checksAssertions,
  );
  final code = _emit(module, options, entry: entrySymbol);
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

/// Compiles the library at [path]. Also gives a header of C for the functions
/// that it exports.
///
/// [name] is what the file will be called. On macOS, programs load a shared
/// library from where that is.
///
/// Throws [CompileFailure] if the library has an error or is not supported yet.
Future<({Uint8List bytes, String header})> compileLibrary(
  String path,
  LibraryKind kind, {
  required String name,
  CompileOptions options = const CompileOptions(),
}) async {
  final (:module, :header) = translateLibrary(
    await _load(path, options),
    target: options.target,
    checksAssertions: options.checksAssertions,
  );
  final code = _emit(module, options);
  final bytes = switch (options.target.system) {
    .macos => _macosLibrary(code, kind, name),
    .linux => _linuxLibrary(code, kind, Uri.file(name).pathSegments.last),
  };
  return (bytes: bytes, header: header);
}

Future<SourceProgram> _load(String path, CompileOptions options) async {
  final CompileOptions(:target, :sdk, :environment) = options;
  final isUsual = sdk == null && environment.isEmpty;
  return loadProgram(
    path,
    sdk: await (isUsual
        ? packagedSdk(target)
        : sdkFor(target, files: sdk, environment: environment)),
  );
}

EmittedCode _emit(HirModule module, CompileOptions options, {String? entry}) =>
    emitCode(
      lowerProgram(
        optimizeProgram(module, enabled: options.optimizations),
        system: options.target.system,
        collectsAlways: options.collectsAlways,
      ),
      target: options.target,
      entry: entry,
    );

Uint8List _macosLibrary(EmittedCode code, LibraryKind kind, String name) {
  final file = Uri.file(name).pathSegments.last;
  return switch (kind) {
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
  };
}

Uint8List _linuxLibrary(EmittedCode code, LibraryKind kind, String name) =>
    switch (kind) {
      .object => writeElfObject(code),
      .static => writeElfArchive(
        writeElfObject(code),
        '$name.o',
        code.exports.keys,
      ),
      .shared => linkElfLibrary(code, name: name),
    };

/// Writes a file, replacing [output] only once it is complete.
void writeOutput(Uint8List bytes, String output, {required bool isExecutable}) {
  final staged = File('$output.tmp-$pid');
  try {
    staged.writeAsBytesSync(bytes, flush: true);
    if (isExecutable) {
      final result = Process.runSync('/bin/chmod', ['+x', staged.path]);
      if (result.exitCode != 0) {
        throw FileSystemException('${result.stderr}', staged.path);
      }
    }
    staged.renameSync(output);
  } finally {
    if (staged.existsSync()) staged.deleteSync();
  }
}

/// Writes an executable file, replacing [output] only once it is complete.
void writeProgram(Uint8List program, String output) =>
    writeOutput(program, output, isExecutable: true);
