import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native references retain asset identity, defaults and inferred types',
    () async {
      final result = await AnalysisSession([
        'test/frontend/lowering/fixtures/native_imports.dart',
        'test/frontend/lowering/fixtures/native_imports_uri.dart',
      ]).use(Lowering().lower);
      final imports = {
        for (final MapEntry(:key, :value) in result.imports.entries)
          key.name: value,
      };
      expect(imports, hasLength(8));
      for (final name in ['aliased', 'fromPart', 'staticCall']) {
        final reference = imports[name]!;
        expect(reference.assetId, 'package:fixture/default');
        expect(reference.symbol, name);
        expect(reference.signature, NativeSignature(Int64, [Int8]));
        expect(reference.isLeaf, name == 'aliased');
      }
      expect(imports['redirected']!.assetId, 'other');
      expect(imports['redirected']!.symbol, 'step');
      expect(
        imports['libraryDefault']!.assetId,
        Uri.base
            .resolve('test/frontend/lowering/fixtures/native_imports_uri.dart')
            .toString(),
      );
      for (final name in ['inferred', 'widened']) {
        expect(
          imports[name]!.signature,
          NativeSignature(Pointer<Int64>, [Pointer<Int64>]),
        );
      }
      expect(
        imports['release']!.signature,
        NativeSignature(Void, [Pointer<Void>]),
      );
      for (final target in result.imports.keys) {
        expect(result.program.implementationOf(target), isA<IrExternal>());
      }
      expect(result.exports, isEmpty);
      expect(imports, isNot(contains('ordinary')));
      expect(() => result.imports.clear(), throwsUnsupportedError);
    },
  );

  test(
    'unused native declarations keep static obligations and unsupported kinds',
    () async {
      await expectLater(
        AnalysisSession([
          'test/frontend/lowering/fixtures/invalid_native_imports.dart',
        ]).use(Lowering().lower),
        throwsFormatException,
      );
      await expectLater(
        AnalysisSession(['test/frontend/lowering/fixtures/native_field.dart'])
            .use(Lowering().lower),
        throwsUnsupportedError,
      );
    },
  );
}
