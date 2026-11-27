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

  /// Whether executables and shared libraries name their functions for tools
  /// like profilers.
  final bool namesFunctions = false,
});

/// What this machine runs, if it is supported.
Target? get hostTarget => switch (Abi.current()) {
  .macosArm64 => .macosArm64,
  .linuxArm64 => .linuxArm64,
  .linuxX64 => .linuxX64,
  _ => null,
};

/// Compiles the program at [path], which uses [sdk], to an executable.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
Future<Uint8List> buildProgram(
  String path,
  SdkSources sdk,
  CompileOptions options,
) async {
  final target = options.target;
  final module = translateProgram(
    await loadProgram(path, sdk: sdk),
    target: target,
    checksAssertions: options.checksAssertions,
  );
  final code = _emit(module, options, entry: entrySymbol);
  return switch (target.system) {
    .macos => linkMacho(
      code,
      entry: entrySymbol,
      identifier: Uri.file(path).pathSegments.last,
      namesFunctions: options.namesFunctions,
    ),
    .linux => linkElf(
      code,
      entry: linuxEntrySymbol,
      namesFunctions: options.namesFunctions,
    ),
  };
}

/// What can be made of a library.
enum LibraryKind() {
  object,
  static,
  shared,
}

/// Compiles the library at [path], which uses [sdk]. Also gives a header of C
/// for the functions that it exports.
///
/// [name] is what the file will be called. On macOS, programs load a shared
/// library from where that is.
///
/// Throws [CompileFailure] if the library has an error or is not supported yet.
Future<({Uint8List bytes, String header})> buildLibrary(
  String path,
  LibraryKind kind,
  SdkSources sdk, {
  required String name,
  required CompileOptions options,
}) async {
  final (:module, :header) = translateLibrary(
    await loadProgram(path, sdk: sdk),
    target: options.target,
    checksAssertions: options.checksAssertions,
  );
  final code = _emit(module, options);
  final bytes = switch (options.target.system) {
    .macos => _macosLibrary(code, kind, name, options.namesFunctions),
    .linux => _linuxLibrary(
      code,
      kind,
      Uri.file(name).pathSegments.last,
      options.namesFunctions,
    ),
  };
  return (bytes: bytes, header: header);
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

Uint8List _macosLibrary(
  EmittedCode code,
  LibraryKind kind,
  String name,
  bool namesFunctions,
) {
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
      namesFunctions: namesFunctions,
    ),
  };
}

Uint8List _linuxLibrary(
  EmittedCode code,
  LibraryKind kind,
  String name,
  bool namesFunctions,
) => switch (kind) {
  .object => writeElfObject(code),
  .static => writeElfArchive(
    writeElfObject(code),
    '$name.o',
    code.exports.keys,
  ),
  .shared => linkElfLibrary(code, name: name, namesFunctions: namesFunctions),
};
