@Tags(['assets', 'native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartc/linker.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('packaged executable contains the exact source archive', () {
    final file = NativeAssets(Target.host()).file('compiler/dartc');
    final resources = ExecutableResources(file);
    final expected = SourceArchive.encode(SourceDirectory(Directory.current));
    final bytes = resources.read();
    expect(sha256.convert(bytes), sha256.convert(expected));
    expect(
      DartSdk(SourceArchive(bytes)).sources
          .contains('sdk/std/lib/core/core.dart'),
      isTrue,
    );
    expect(
      () => resources.embed(Uint8List.fromList([1])),
      throwsFormatException,
    );
  });

  test('truncated executable is rejected without modifying its input', () {
    final file = NativeAssets(Target.host()).file('compiler/dartc');
    final work = file.parent.createTempSync('damaged-');
    addTearDown(() => work.deleteSync(recursive: true));
    final copy = file.copySync('${work.path}/dartc');
    final original = copy.lengthSync();
    final handle = copy.openSync(mode: .append);
    handle.truncateSync(original - 1);
    handle.closeSync();
    expect(() => ExecutableResources(copy).read(), throwsFormatException);
    expect(copy.lengthSync(), original - 1);
    expect(file.lengthSync(), original);
  });
}
