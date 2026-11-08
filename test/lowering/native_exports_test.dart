import 'package:dartc/analyzer.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

void main() {
  test(
    'export aliases retain declaration identity without matching names',
    () async {
      final result = await AnalysisSession([
        'test/lowering/fixtures/native_exports.dart',
      ]).use(Lowering().lower);
      expect(result.exports, hasLength(1));
      final target = result.exports.keys.single;
      expect(
        target,
        same(
          result.program.functions
              .singleWhere((f) => f.target.name == 'add')
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
