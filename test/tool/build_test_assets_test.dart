import 'package:test/test.dart';

import '../../tool/build_test_assets.dart' as builder;

void main() {
  test('a selection excludes unrelated compiler fixtures', () {
    expect(builder.selectCompilerFixtures(['pointers', 'pointers']), {
      'pointers',
    });
  });

  test('native consumers include their provider without other fixtures', () {
    for (final consumer in ['native_imports', 'pointer_values']) {
      expect(builder.selectCompilerFixtures([consumer]), {
        consumer,
        'native_function_pointers',
      });
    }
  });

  test('no selection includes libraries and executable and IO groups', () {
    expect(
      builder.selectCompilerFixtures([]),
      containsAll(['arithmetic', 'pointers', 'entry', 'descriptor_write']),
    );
  });

  test('invalid selections fail before building any assets', () async {
    for (final name in ['', 'pointer', '../pointers']) {
      await expectLater(
        builder.main(['macos-arm64', '--fixture=$name']),
        throwsArgumentError,
      );
    }
  });
}
