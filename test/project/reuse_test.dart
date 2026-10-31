import 'dart:async';

import 'package:dartc/project.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
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
      final next = await projectLoader.load(uri('main.dart'));
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
