import 'dart:io';

import '../diagnostic.dart';

void prepareOutput(String path) {
  try {
    File(path).parent.createSync(recursive: true);
  } on FileSystemException {
    throw Diagnostic('Cannot create output directory: ' + path, exitCode: 74);
  }
}

bool identicalFiles(String first, String second) {
  try {
    return FileSystemEntity.identicalSync(
      File(first).resolveSymbolicLinksSync(),
      File(second).resolveSymbolicLinksSync(),
    );
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    if (code == 2 || code == 20) return false;
    throw Diagnostic(
      'Cannot inspect file: ' + (error.path ?? first),
      exitCode: 74,
    );
  }
}
