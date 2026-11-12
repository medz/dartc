import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'non-terminating loop backedges preserve finalizable parameters',
    () async {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/finalizable.dart',
      ]).use((input) => Lowering().lower(input));
      final body = result.program.functions.singleWhere(
        (f) => f.target.name == 'forever',
      );
      final loop = body.blocks.singleWhere(
        (b) => b.instructions.any(
          (op) => op is DirectCall && op.target.name == 'consume',
        ),
      );
      expect(
        loop.instructions.whereType<KeepAlive>().map((op) => op.value),
        contains(body.entry.parameters.single),
      );
      expect(
        FfiTypes.includesFinalizable(
          body.target.parameterTypes.single.nullable,
        ),
        isTrue,
      );
      expect(
        FfiTypes.includesFinalizable(
          ValueType.futureOr(body.target.parameterTypes.single),
        ),
        isTrue,
      );
      expect(FfiTypes.includesFinalizable(.never), isFalse);
    },
  );
}
