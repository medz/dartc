import 'dart:ffi';

import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'unused address expressions retain position and storage restrictions',
    () async {
      for (final fixture in ['escaped', 'non_leaf', 'scalar']) {
        await expectLater(
          AnalysisSession([
            'test/frontend/lowering/fixtures/addresses/$fixture.dart',
          ]).use(Lowering().lower),
          throwsFormatException,
          reason: fixture,
        );
      }
    },
  );
  test('native storage accessors retain symbol types without reading an address argument', () async {
    final result = await AnalysisSession([
      'test/compiler/fixtures/native_symbols.dart',
    ], includeDependencies: true).use(Lowering().lower);
    for (final name in [
      'integerAddress',
      'doubleAddress',
      'pointerAddress',
      'pairAddress',
      'functionAddress',
    ]) {
      final body = result.program.functions.singleWhere(
        (f) => f.target.name == name,
      );
      final operations = body.blocks.expand((b) => b.instructions).toList();
      expect(operations.whereType<NativeSymbolAddress>(), hasLength(1));
      expect(operations.whereType<LoadNative>(), isEmpty);
      expect(operations.whereType<DirectCall>(), isEmpty);
    }
    final getter = result.program.functions.singleWhere(
      (f) => f.target.name == 'number' && f.target.parameterTypes.isEmpty,
    );
    expect(
      getter.blocks.single.instructions.whereType<LoadNative>(),
      hasLength(1),
    );
    expect(result.imports[getter.target]!.type, NativeTypeRef.of(Int16));
  });

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
        expect(
          reference.type,
          NativeFunctionType(NativeSignature(Int64, [Int8])),
        );
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
          imports[name]!.type,
          NativeFunctionType(NativeSignature(Pointer<Int64>, [Pointer<Int64>])),
        );
      }
      expect(
        imports['release']!.type,
        NativeFunctionType(NativeSignature(Void, [Pointer<Void>])),
      );
      for (final target in result.imports.keys) {
        expect(result.program.implementationOf(target), isA<IrExternal>());
      }
      expect(result.exports, isEmpty);
      expect(imports, isNot(contains('ordinary')));
      expect(() => result.imports.clear(), throwsUnsupportedError);
    },
  );

  test('unused native declarations keep static obligations', () async {
    await expectLater(
      AnalysisSession([
        'test/frontend/lowering/fixtures/invalid_native_imports.dart',
      ]).use(Lowering().lower),
      throwsFormatException,
    );
  });
}
