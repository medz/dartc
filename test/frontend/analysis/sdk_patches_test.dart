import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:dartc/src/frontend/analysis/sdk_patches.dart';
import 'package:test/test.dart';

void main() {
  test('SDK patches require a matching external factory signature', () {
    for (final declaration in [
      'external factory Box(int value);',
      'factory Box(Object value) => throw 0;',
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
}
