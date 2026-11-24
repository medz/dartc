import 'dart:io';
import 'dart:isolate';

import 'package:dartc/native.dart';
import 'package:dartc/source.dart';

final Future<SdkFiles> _packaged = _readPackaged();
final _sources = <Target, Future<SdkSources>>{};

Future<SdkFiles> _readPackaged() async {
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
Future<SdkFiles> packagedSdkFiles() => _packaged;

/// The standard libraries that come with the compiler, for [target].
Future<SdkSources> packagedSdk([Target target = .macosArm64]) =>
    _sources[target] ??= sdkFor(target);

/// The standard libraries for [target], made of [files] or those of this
/// package. [environment] is what programs can ask for, besides what the
/// compiler tells them.
Future<SdkSources> sdkFor(
  Target target, {
  SdkFiles? files,
  Map<String, String> environment = const {},
}) async => SdkSources(
  files ?? await _packaged,
  systems: [target.system.name, target.label],
  declared: environment,
);
