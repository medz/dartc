import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

import 'compile.dart';
import 'sdk.dart';
import 'sizes.dart';

// What finds the standard libraries in this package. The standalone compiler
// has them inside and uses none of this.

final Future<SdkFiles> _files = _readFiles();
final _sources = <Target, Future<SdkSources>>{};

Future<SdkFiles> _readFiles() async {
  final package = Uri.parse('package:dartc/heap.dart');
  final file = await Isolate.resolvePackageUri(package);
  if (file == null) throw StateError('$package is missing.');
  return readSdkFiles(
    std: Directory.fromUri(file.resolve('../sdk/std/')),
    native: Directory.fromUri(file.resolve('../sdk/native/')),
    heap: Directory.fromUri(file.resolve('src/heap/')),
  );
}

/// The sources of the SDK that come with this package.
Future<SdkFiles> packagedSdkFiles() => _files;

/// The standard libraries that come with the compiler, for [target].
Future<SdkSources> packagedSdk([Target target = .macosArm64]) =>
    _sources[target] ??= _files.then((files) => sdkFor(target, files));

Future<SdkSources> _sdkOf(CompileOptions options) async =>
    options.environment.isEmpty
    ? packagedSdk(options.target)
    : sdkFor(options.target, await _files, environment: options.environment);

/// Compiles the program at [path] to an executable.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
Future<Uint8List> compileProgram(
  String path, [
  CompileOptions options = const CompileOptions(),
]) async => buildProgram(path, await _sdkOf(options), options);

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
}) async => buildLibrary(
  path,
  kind,
  await _sdkOf(options),
  name: name,
  options: options,
);

/// What the bytes of the program at [path] are made of, and why each function
/// is part of it.
///
/// Throws [CompileFailure] if the program has an error or is not supported
/// yet.
Future<ProgramSizes> measureProgram(
  String path, [
  CompileOptions options = const CompileOptions(),
]) async => measureSizes(path, await _sdkOf(options), options);
