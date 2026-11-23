import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:dartc/driver.dart';
import 'package:test/test.dart';

import '../support/new_compiler.dart';

void main() {
  test('the patched libraries have no errors', () async {
    final sdk = await packagedSdk();
    final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    sdk.install(files);
    final directory = writeSources({'main.dart': ''});
    final path = '${directory.path}/main.dart';
    final contexts = AnalysisContextCollection(
      includedPaths: [path],
      sdkPath: sdk.root,
      resourceProvider: files,
    );
    addTearDown(contexts.dispose);
    final session = contexts.contextFor(path).currentSession;
    final found = <String>[];
    for (final uri in sdk.libraries) {
      final library = await session.getLibraryByUri(uri);
      final result = await session.getResolvedLibraryByElement(
        (library as LibraryElementResult).element,
      );
      for (final unit in (result as ResolvedLibraryResult).units) {
        for (final diagnostic in unit.diagnostics) {
          if (diagnostic.severity != Severity.error) continue;
          found.add('$uri: ${diagnostic.message}');
        }
      }
    }
    // Every enum gets this member from the compiler.
    expect(found, [
      "dart:core: Missing concrete implementation of 'getter Enum._name'.",
    ]);
  });

  test('programs see the libraries that are compiled', () async {
    final program = await load('void main() { print(1); }');
    final uris = {for (final library in program.sdk) '${library.element.uri}'};
    expect(uris, containsAll(['dart:core', 'dart:_heap/types.dart']));
    final core = program.sdk.firstWhere(
      (library) => library.element.isDartCore,
    );
    expect(
      program.main.element.typeProvider.objectElement.library,
      core.element,
    );
    expect(core.element.getClass('_GrowableList'), isNotNull);
  });

  test('the official sources are as they were', () async {
    final sdk = await packagedSdk();
    expect(File('${sdk.root}/version').readAsStringSync().trim(), '3.14.0');
  });
}
