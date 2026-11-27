import 'dart:io';

import 'package:dartc/driver.dart';
import 'package:dartc/source.dart';

/// Writes a program called [name] that has the sources of the SDK inside as
/// `sdkFiles`, with [imports] and [body] after them, and gives its file.
///
/// Such a program needs no other files, so it can be compiled to one
/// executable.
Future<File> writeEmbedded(String name, String imports, String body) async {
  // Generated files are found by the package's own configuration there.
  final directory = Directory('.dart_tool/dartc')..createSync(recursive: true);
  return File('${directory.path}/$name.dart')..writeAsStringSync('''
import 'package:dartc/source.dart';
$imports
const _sdk = '${packSdkFiles(await packagedSdkFiles())}';

/// The sources of the SDK.
SdkFiles get sdkFiles => unpackSdkFiles(_sdk);

$body''');
}
