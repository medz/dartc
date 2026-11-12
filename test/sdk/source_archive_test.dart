import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dartc/sdk.dart';
import 'package:test/test.dart';

void main() {
  test('indexes both source roots and owns its compressed input', () {
    final bytes = bundle({
      'sdk/std/lib/core.dart': 'core',
      'sdk/runtime/heap.dart': 'heap',
    });
    final sources = SourceArchive(
      bytes,
      digest: sha256.convert(bytes).toString(),
    );
    bytes.fillRange(0, bytes.length, 0);
    expect(sources.paths, ['sdk/std/lib/core.dart', 'sdk/runtime/heap.dart']);
    expect(sources.contains('sdk/runtime/heap.dart'), isTrue);
    expect(sources.length('sdk/runtime/heap.dart'), 4);
    expect(utf8.decode(sources.read('sdk/runtime/heap.dart')), 'heap');
    expect(() => sources.read('missing'), throwsFormatException);
    expect(
      () => sources.read('sdk/std/lib/core.dart')[0] = 0,
      throwsUnsupportedError,
    );
  });

  test('verifies a requested file without decompressing unrelated content', () {
    final compressed = bundle({
      'sdk/std/lib/good.dart': 'good',
      'sdk/runtime/damaged.dart': 'original',
    });
    final index = ZipDirectory()
      ..read(InputMemoryStream(compressed), verify: true);
    final bad = index.fileHeaders.singleWhere(
      (entry) => entry.filename == 'sdk/runtime/damaged.dart',
    );
    final data = ByteData.sublistView(compressed);
    final start = bad.localHeaderOffset;
    compressed[start +
            30 +
            data.getUint16(start + 26, .little) +
            data.getUint16(start + 28, .little)] =
        7;
    final unread = SourceArchive(compressed);
    expect(utf8.decode(unread.read('sdk/std/lib/good.dart')), 'good');
    expect(
      () => unread.read('sdk/runtime/damaged.dart'),
      throwsFormatException,
    );
    final sources = SourceArchive(
      bundle(
        {
          'sdk/std/lib/good.dart': 'good',
          'sdk/runtime/damaged.dart': 'changed',
        },
        digests: {
          'sdk/runtime/damaged.dart': sha256
              .convert(utf8.encode('original'))
              .toString(),
        },
      ),
    );
    expect(utf8.decode(sources.read('sdk/std/lib/good.dart')), 'good');
    expect(
      () => sources.read('sdk/runtime/damaged.dart'),
      throwsFormatException,
    );
    expect(utf8.decode(sources.read('sdk/std/lib/good.dart')), 'good');
  });

  test('rejects a mismatched archive, SDK identity and manifest', () {
    final bytes = bundle({'sdk/std/version': 'wrong'});
    expect(() => SourceArchive(bytes, digest: '0' * 64), throwsFormatException);
    expect(() => DartSdk(SourceArchive(bytes)), throwsFormatException);
    expect(() => SourceArchive(Uint8List(0)), throwsFormatException);
    expect(
      () => SourceArchive(Uint8List.sublistView(bytes, 0, bytes.length - 8)),
      throwsFormatException,
    );
    expect(
      () => SourceArchive(ZipEncoder().encodeBytes(Archive())),
      throwsFormatException,
    );
  });

  for (final name in [
    '/root',
    '../root',
    'sdk/../root',
    'sdk//root',
    'sdk\\root',
    'sdk/root\u0000',
    'C:/root',
  ]) {
    test('rejects nonportable source path ${jsonEncode(name)}', () {
      expect(
        () => SourceArchive(bundle({name: 'data'})),
        throwsFormatException,
      );
    });
  }

  test('rejects duplicate names, file-directory conflicts and links', () {
    expect(
      () => SourceArchive(bundle({'sdk/a': 'a'}, duplicate: true)),
      throwsFormatException,
    );
    expect(
      () => SourceArchive(bundle({'sdk/a': 'a', 'sdk/a/b': 'b'})),
      throwsFormatException,
    );
    expect(
      () => SourceArchive(bundle({'sdk/a': 'a'}, mode: 0xa1ff)),
      throwsFormatException,
    );
  });
}

Uint8List bundle(
  Map<String, String> files, {
  Map<String, String> digests = const {},
  bool duplicate = false,
  int mode = 0x81a4,
}) {
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output);
  encoder.add(
    ArchiveFile.string(
      'manifest.json',
      jsonEncode({
        'format': 1,
        'files': {
          for (final MapEntry(:key, :value) in files.entries)
            key: digests[key] ?? sha256.convert(utf8.encode(value)).toString(),
        },
      }),
    ),
  );
  for (final MapEntry(:key, :value) in files.entries) {
    final entry = ArchiveFile.string(key, value)..mode = mode;
    encoder.add(entry);
    if (duplicate) encoder.add(entry);
  }
  encoder.endEncode();
  return output.getBytes();
}
