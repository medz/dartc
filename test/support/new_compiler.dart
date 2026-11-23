import 'dart:io';

import 'package:dartc/hir.dart';
import 'package:dartc/source.dart';
import 'package:dartc/translate.dart';
import 'package:test/test.dart';

/// The SDK running the tests.
final String hostSdk = File(Platform.resolvedExecutable).parent.parent.path;

/// Writes [files] to a fresh directory, removed after the test.
Directory writeSources(Map<String, String> files) {
  final directory = Directory(
    Directory.systemTemp
        .createTempSync('dartc-source-')
        .resolveSymbolicLinksSync(),
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  files.forEach((name, text) {
    File('${directory.path}/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  });
  return directory;
}

Future<SourceLibrary> load(String source) {
  final directory = writeSources({'main.dart': source});
  return loadLibrary('${directory.path}/main.dart', sdk: hostSdk);
}

Future<HirModule> translate(String source) async =>
    translateProgram(await load(source));

/// Matches a failure whose problems print as [problems] after their file name.
Matcher failsWith(List<String> problems) => throwsA(
  isA<CompileFailure>().having(
    (failure) => [
      for (final problem in failure.problems)
        '$problem'.substring(problem.path.lastIndexOf('/') + 1),
    ],
    'problems',
    problems,
  ),
);
