import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:test/test.dart';

void main() {
  test('export symbols and aliases use exact constant comparisons', () async {
    for (final suffix in ['', '_alias']) {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/native_exports_numeric$suffix.dart',
      ]).use(Lowering().lower);
      expect(result.exports.values.single.symbol, 'right');
    }
  });

  test(
    'export aliases retain declaration identity without matching names',
    () async {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/native_exports.dart',
      ]).use(Lowering().lower);
      expect(result.exports, hasLength(1));
      final target = result.exports.keys.single;
      expect(
        target,
        same(
          result.program.functions
              .singleWhere(
                (f) =>
                    f.target.library == target.library &&
                    f.target.owner == null &&
                    f.target.name == 'add',
              )
              .target,
        ),
      );
      expect(result.exports.values.single.symbol, 'bound_add');
      expect(() => result.exports.clear(), throwsUnsupportedError);
      final output = StringBuffer();
      NativeExports(result.exports.values).writeHeader(output);
      expect(
        output.toString(),
        contains('int64_t bound_add(int64_t, int64_t);'),
      );
      expect(output.toString(), isNot(contains('not_native')));
    },
  );
}
