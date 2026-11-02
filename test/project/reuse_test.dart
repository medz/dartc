import 'dart:async';

import 'package:dartc/ast.dart';
import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'updates the reachable graph and keeps the previous tree usable',
    () async {
      final entry = uri('main.dart'),
          old = uri('old.dart'),
          added = uri('new.dart');
      final files = sources({
        'main.dart': "export 'old.dart';",
        'old.dart': '',
        'new.dart': 'class Added {}',
      });
      final reads = <Uri>[];
      final projectLoader = ProjectLoader(
        readSource: (uri) {
          reads.add(uri);
          return files[uri];
        },
      );
      final first = await projectLoader.load(entry);
      reads.clear();
      expect(
        await projectLoader.update(first, changedSources: []),
        same(first),
      );
      expect(reads, isEmpty);

      files[entry] = "import 'new.dart';";
      files.remove(old);
      final next = await projectLoader.update(
        first,
        changedSources: [entry, old],
      );
      expect(reads, [entry, added]);
      expect(next.diagnostics, isEmpty);
      expect(next.libraries.keys, [entry, added, uri('dart:core')]);
      expect(next.libraries[entry]!.dependencies.first.isExport, isFalse);
      expect(first.libraries.keys, [entry, old, uri('dart:core')]);
      final original = first.libraries[entry]!.unit;
      final current = next.libraries[entry]!.unit;
      expect(original.tree.indexOf(original.node), original.tree.root);
      expect(
        original.tree.kind(original.tree.childAt(original.tree.root, 0)),
        SyntaxKind.exportDirective,
      );
      final cursor = current.tree.cursor(
        current.tree.indexOf(current.node.members.single),
      );
      expect(cursor.moveNext(), isTrue);
      expect(cursor.kind, SyntaxKind.importDirective);
      expect(() => current.tree.indexOf(original.node), throwsArgumentError);
    },
  );

  test(
    'retries a failed read and reports deletion at the referring directive',
    () async {
      final entry = uri('main.dart'), part = uri('p.dart');
      final files = sources({'main.dart': "part 'p.dart';"});
      final reads = <Uri>[];
      var fail = true;
      final projectLoader = ProjectLoader(
        readSource: (uri) {
          reads.add(uri);
          if (fail && uri == part) throw const FormatException('unreadable');
          return files[uri];
        },
      );
      final first = await projectLoader.load(entry);
      expect(first.diagnostics.single.code, 'project.source_read_failed');
      fail = false;
      files[part] = "part of 'main.dart';";
      reads.clear();
      final recovered = await projectLoader.update(first, changedSources: []);
      expect(reads, [part]);
      expect(recovered.diagnostics, isEmpty);
      expect(recovered.libraries[entry]!.parts.single.tree.source.uri, part);

      files.remove(part);
      reads.clear();
      final deleted = await projectLoader.update(
        recovered,
        changedSources: [part],
      );
      expect(reads, [part]);
      expect(deleted.libraries[entry]!.parts, isEmpty);
      final error = deleted.diagnostics.single;
      expect(error.code, 'project.source_not_found');
      expect(error.span!.text, "'p.dart'");
      expect(error.span!.source, same(first.libraries[entry]!.unit.source));
    },
  );

  test(
    'stale, foreign and cleared snapshots load through the current provider',
    () async {
      final entry = uri('main.dart'), core = uri('dart:core');
      final files = sources({'main.dart': 'int a = 1;'});
      final reads = <Uri>[];
      final projectLoader = ProjectLoader(
        readSource: (uri) {
          reads.add(uri);
          return files[uri];
        },
      );
      final foreign = await loader(sources({'main.dart': ''})).load(entry);
      final stale = await projectLoader.load(entry);
      files[entry] = 'int a = 2;';
      final current = await projectLoader.update(
        stale,
        changedSources: [entry],
      );
      projectLoader.clear();
      for (final base in [current, stale, foreign]) {
        reads.clear();
        final next = await projectLoader.update(base, changedSources: []);
        expect(reads, [entry, core]);
        expect(next.libraries[entry]!.unit.source.text, 'int a = 2;');
      }
      for (final invalid in [
        Uri.parse('relative.dart'),
        Uri.parse('package:unknown/a.dart'),
      ]) {
        await expectLater(
          projectLoader.update(current, changedSources: [invalid]),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'overlapping updates capture their change sets and publish only the newest',
    () async {
      final entry = uri('main.dart'), part = uri('p.dart');
      final files = sources({
        'main.dart': "part 'p.dart';",
        'p.dart': "part of 'main.dart';",
      });
      final reading = Completer<String?>();
      var delay = false;
      final projectLoader = ProjectLoader(
        readSource: (u) => u == entry && delay ? reading.future : files[u],
      );
      final first = await projectLoader.load(entry);
      delay = true;
      final changes = [entry, part];
      final older = projectLoader.update(first, changedSources: changes);
      changes.clear();
      delay = false;
      files[part] = "part of 'main.dart'; class C {}";
      final newer = await projectLoader.update(first, changedSources: [part]);
      reading.complete("part 'p.dart'; // older");
      final completed = await older;
      expect(completed.libraries[entry]!.parts.single.source.text, files[part]);
      expect(
        await projectLoader.update(newer, changedSources: []),
        same(newer),
      );
      expect(newer.libraries[entry]!.unit, same(first.libraries[entry]!.unit));
    },
  );

  test(
    'reuses unchanged units and replaces changed snapshots and diagnostics',
    () async {
      final files = sources({
        'main.dart': "import 'a.dart';",
        'a.dart': 'class A {}',
      });
      final projectLoader = loader(files);
      final first = await projectLoader.load(uri('main.dart'));
      final second = await projectLoader.load(uri('main.dart'));
      expect(
        second.libraries[uri('main.dart')]!.unit,
        same(first.libraries[uri('main.dart')]!.unit),
      );
      expect(
        second.libraries[uri('a.dart')]!.unit,
        same(first.libraries[uri('a.dart')]!.unit),
      );
      files[uri('a.dart')] = 'class A {';
      final changed = await projectLoader.load(uri('main.dart'));
      expect(changed.hasErrors, isTrue);
      expect(
        changed.libraries[uri('main.dart')]!.unit,
        same(first.libraries[uri('main.dart')]!.unit),
      );
      expect(
        changed.libraries[uri('a.dart')]!.unit.source,
        isNot(same(first.libraries[uri('a.dart')]!.unit.source)),
      );
      expect(first.libraries[uri('a.dart')]!.unit.source.text, 'class A {}');
      files[uri('a.dart')] = 'class A {}';
      expect((await projectLoader.load(uri('main.dart'))).diagnostics, isEmpty);
    },
  );

  test(
    'evicts unreachable files and clear releases all cached units',
    () async {
      final files = sources({'main.dart': "import 'a.dart';", 'a.dart': ''});
      final projectLoader = loader(files);
      final first = await projectLoader.load(uri('main.dart'));
      files[uri('main.dart')] = '';
      await projectLoader.load(uri('main.dart'));
      files[uri('main.dart')] = "import 'a.dart';";
      final returned = await projectLoader.load(uri('main.dart'));
      expect(
        returned.libraries[uri('a.dart')]!.unit,
        isNot(same(first.libraries[uri('a.dart')]!.unit)),
      );
      projectLoader.clear();
      final cleared = await projectLoader.load(uri('main.dart'));
      expect(
        cleared.libraries[uri('main.dart')]!.unit,
        isNot(same(returned.libraries[uri('main.dart')]!.unit)),
      );
    },
  );

  test('an older async completion cannot replace a newer load cache', () async {
    final firstRead = Completer<String?>();
    final secondRead = Completer<String?>();
    var calls = 0;
    final projectLoader = ProjectLoader(
      readSource: (source) {
        if (source == uri('dart:core')) return '';
        return switch (++calls) {
          1 => firstRead.future,
          2 => secondRead.future,
          _ => 'class New {}',
        };
      },
    );
    final first = projectLoader.load(uri('main.dart'));
    final second = projectLoader.load(uri('main.dart'));
    secondRead.complete('class New {}');
    final newer = await second;
    firstRead.complete('class Old {}');
    final older = await first;
    expect(older.libraries[uri('main.dart')]!.unit.source.text, 'class Old {}');
    final repeated = await projectLoader.load(uri('main.dart'));
    expect(
      repeated.libraries[uri('main.dart')]!.unit,
      same(newer.libraries[uri('main.dart')]!.unit),
    );
  });

  test('clear prevents in-flight loads from repopulating the cache', () async {
    final reading = Completer<String?>();
    var calls = 0;
    final projectLoader = ProjectLoader(
      readSource: (source) => source == uri('dart:core')
          ? ''
          : ++calls == 1
          ? reading.future
          : 'class C {}',
    );
    final pending = projectLoader.load(uri('main.dart'));
    projectLoader.clear();
    reading.complete('class C {}');
    final previous = await pending;
    final next = await projectLoader.load(uri('main.dart'));
    expect(
      next.libraries[uri('main.dart')]!.unit,
      isNot(same(previous.libraries[uri('main.dart')]!.unit)),
    );
  });

  test(
    'rechecks part version agreement while reusing unchanged file syntax',
    () async {
      final files = sources({
        'main.dart': "part 'p.dart';",
        'p.dart': "part of 'main.dart'; class C;",
      });
      final projectLoader = loader(files);
      final first = await projectLoader.load(uri('main.dart'));
      expect(first.diagnostics, isEmpty);
      files[uri('main.dart')] = "// @dart=3.12\npart 'p.dart';";
      final next = await projectLoader.update(
        first,
        changedSources: [uri('main.dart')],
      );
      expect(next.diagnostics.map((d) => d.code), [
        'project.part_language_version',
      ]);
      final previousPart = first.libraries[uri('main.dart')]!.parts.single;
      final nextPart = next.libraries[uri('main.dart')]!.parts.single;
      expect(nextPart, same(previousPart));
      expect(nextPart.source, same(previousPart.source));
    },
  );
}
