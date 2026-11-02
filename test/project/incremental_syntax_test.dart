import 'package:dartc/ast.dart';
import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'repairs one body while keeping diagnostics from other reachable units',
    () async {
      final entry = uri('main.dart'), dep = uri('dep.dart');
      final files = sources({
        'main.dart': "import 'dep.dart'; int main() => 1;",
        'dep.dart': 'int dep() => 2;',
      });
      final incremental = loader(files);
      var project = await incremental.load(entry);
      for (final (file, text, errors) in [
        (dep, 'int dep() => ;', [dep]),
        (entry, "import 'dep.dart'; int main() => ;", [entry, dep]),
        (dep, 'int dep() => 3;', [entry]),
        (entry, "import 'dep.dart'; int main() => 4;", <Uri>[]),
      ]) {
        final old = project, oldDiagnostics = old.diagnostics.toList();
        files[file] = text;
        project = await incremental.update(old, changedSources: [file]);
        expect(project.diagnostics.map((d) => d.span?.source.uri), errors);
        final fresh = await loader(files).load(entry);
        expect(
          project.diagnostics.map((d) => (d.code, d.span?.start, d.span?.end)),
          fresh.diagnostics.map((d) => (d.code, d.span?.start, d.span?.end)),
        );
        expect(old.diagnostics, oldDiagnostics);
      }
    },
  );

  test(
    'body and boundary edits agree with a fresh tree and its diagnostics',
    () async {
      final entry = uri('main.dart');
      const original =
          '#!/usr/bin/env dart\n// @dart=3.12\nlibrary app;\n'
          'class C { int f(int n) { return n + 1; } }\n'
          'int tail(int? n) => (n ?? 0) + 1;\n';
      final files = sources({'main.dart': original});
      final projectLoader = loader(files);
      final base = await projectLoader.load(entry);
      var previous = base;
      for (final text in [
        original.replaceFirst('n + 1', 'n * 3'),
        original.replaceFirst('n + 1', 'n.isEven ? n + 1 : 0'),
        original.replaceFirst('n + 1', 'n /*}*/ + 1'),
        original.replaceFirst('return n + 1;', 'return ; } /*'),
        original.replaceFirst('3.12', '3.13'),
        original.replaceFirst('library app;', 'library app; // 🐦'),
        original.replaceFirst('int tail', "import 'late.dart'; int tail"),
        '$original\nint? last() => null;',
      ]) {
        files[entry] = text;
        final next = await projectLoader.update(
          previous,
          changedSources: [entry],
        );
        final fresh = await loader(files).load(entry);
        final unit = next.libraries[entry]!.unit,
            other = fresh.libraries[entry]!.unit;
        List<Object> rows(LibraryUnit file) => [
          for (final i in file.tree.walk())
            (
              file.tree.kind(i),
              file.tree.start(i),
              file.tree.end(i),
              file.tree.childCount(i),
              switch (file.tree.view(i)) {
                BinaryExpression(:final op) => op,
                NamedTypeAnnotation(:final questionOffset) => questionOffset,
                _ => null,
              },
            ),
        ];
        expect(rows(unit), rows(other), reason: text);
        expect(
          unit.tree.walk().every(
            (i) => identical(unit.tree.view(i).source, unit.source),
          ),
          isTrue,
        );
        expect(unit.node.scriptTag?.text, other.node.scriptTag?.text);
        expect(unit.versionMarker?.source, same(unit.source));
        expect(unit.languageVersion, other.languageVersion);
        expect(
          next.diagnostics.map((d) => (d.code, d.span?.start, d.span?.end)),
          fresh.diagnostics.map((d) => (d.code, d.span?.start, d.span?.end)),
          reason: text,
        );
        expect(base.libraries[entry]!.unit.source.text, original);
        previous = next;
      }
    },
  );

  test(
    'reports both current inclusion spans when an owner was reused',
    () async {
      final entry = uri('main.dart'), a = uri('a.dart'), b = uri('b.dart');
      for (final first in [a, b]) {
        final files = sources({
          'main.dart': "import 'a.dart'; import 'b.dart';",
          'a.dart': 'library shared;',
          'b.dart': 'library shared;',
          'p.dart': 'part of shared;',
        });
        files[first] = "library shared; part 'p.dart';";
        final loader = ProjectLoader(readSource: (uri) => files[uri]);
        final original = await loader.load(entry);
        files[first] = "// moved\n${files[first]} int f() => 1;";
        final moved = await loader.update(original, changedSources: [first]);
        final other = first == a ? b : a;
        files[other] = "library shared; part 'p.dart';";
        final conflict = await loader.update(moved, changedSources: [other]);
        final error = conflict.diagnostics.single;
        expect(error.code, 'project.shared_part');
        expect(error.span!.source, same(conflict.libraries[b]!.unit.source));
        final note = error.notes.single.span;
        expect(note.source, same(conflict.libraries[a]!.unit.source));
        expect(note.start, files[a]!.indexOf('part '));
        expect(original.hasErrors, isFalse);
      }
    },
  );
}
