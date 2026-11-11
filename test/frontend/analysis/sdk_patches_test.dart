import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:dartc/src/frontend/analysis/sdk_patches.dart';
import 'package:test/test.dart';

void main() {
  test(
    'top-level patches and private externals keep checked SDK signatures',
    () {
      final files = MemoryResourceProvider();
      files.newFile(
        '/sdk/async.dart',
        "library dart.async; part 'hooks.dart';",
      );
      files.newFile(
        '/sdk/hooks.dart',
        "part of 'async.dart'; "
            'external int get current; external set current(int value); '
            'class Hooks { external static void _run(void Function() callback); }',
      );
      files.newFile(
        '/runtime/async.dart',
        'int _current = 0; @patch int get current => _current; '
            '@patch set current(int value) => _current = value; '
            '@patch class Hooks { static void _run(void Function() callback) => callback(); }',
      );
      final overlay = OverlayResourceProvider(files);
      SdkPatches(overlay)
          .apply('/sdk/async.dart', '/sdk/hooks.dart', '/runtime/async.dart');
      final source = overlay.getFile('/sdk/hooks.dart').readAsStringSync();
      expect(source, isNot(contains('external')));
      expect(RegExp(r'void _run').allMatches(source), hasLength(1));
      expect(
        source,
        matches(r'set current\(int value\)\s*=> _current = value;'),
      );
    },
  );

  test('SDK patches require a matching external factory signature', () {
    for (final declaration in [
      'external factory Box(int value);',
      'factory Box(Object value) => throw 0;',
      'external Box(Object value);',
    ]) {
      final files = MemoryResourceProvider();
      files.newFile('/sdk/core.dart', "library dart.core; part 'box.dart';");
      files.newFile(
        '/sdk/box.dart',
        "part of 'core.dart'; abstract final class Box { $declaration }",
      );
      files.newFile(
        '/runtime/core.dart',
        '@patch class Box { factory Box(Object value) => _Box(); } '
            'final class _Box implements Box {}',
      );
      final overlay = OverlayResourceProvider(files);
      expect(
        () =>
            SdkPatches(overlay)
                .apply('/sdk/core.dart', '/sdk/box.dart', '/runtime/core.dart'),
        throwsFormatException,
      );
      expect(
        overlay.getFile('/sdk/box.dart').readAsStringSync(),
        contains(declaration),
      );
    }
  });

  test('SDK member patches preserve public types and private field order', () {
    final files = MemoryResourceProvider();
    files.newFile('/sdk/core.dart', "library dart.core; part 'box.dart';");
    files.newFile(
      '/sdk/box.dart',
      "part of 'core.dart'; class Box { "
          'external Box(int value); external int read(); }',
    );
    files.newFile(
      '/runtime/core.dart',
      '@patch class Box { '
          'new(int value) : _first = value; '
          'final int _first; final int _second = 2; '
          'String read() => "wrong"; }',
    );
    final overlay = OverlayResourceProvider(files);
    expect(
      () =>
          SdkPatches(overlay)
              .apply('/sdk/core.dart', '/sdk/box.dart', '/runtime/core.dart'),
      throwsFormatException,
    );
    overlay.setOverlay(
      '/runtime/core.dart',
      content: files
          .getFile('/runtime/core.dart')
          .readAsStringSync()
          .replaceFirst(
            'String read() => "wrong"',
            'int read() => _first + _second',
          ),
      modificationStamp: 0,
    );
    SdkPatches(overlay)
        .apply('/sdk/core.dart', '/sdk/box.dart', '/runtime/core.dart');
    final source = overlay.getFile('/sdk/box.dart').readAsStringSync();
    expect(source, isNot(contains('external')));
    expect(source.indexOf('final int _first'), isNonNegative);
    expect(
      source.indexOf('final int _first'),
      lessThan(source.indexOf('final int _second')),
    );
  });
}
