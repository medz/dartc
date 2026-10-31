import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('loads a deep cyclic graph without recursive traversal or duplicate reads', () async {
    const count = 5000;
    final files = sources({
      for (var i = 0; i < count; i++)
        '$i.dart':
            "import '${(i + 1) % count}.dart'; export '${(i + 2) % count}.dart';",
    });
    final result = await loader(files).load(uri('0.dart'));
    expect(result.diagnostics, isEmpty);
    expect(result.libraries, hasLength(count + 1));
    expect(
      result.libraries[uri('${count - 1}.dart')]!.dependencies.first.uri,
      uri('0.dart'),
    );
  });
}
