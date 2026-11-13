import 'package:dartc/abi.dart';
import 'package:dartc/frontend.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/sdk.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ABI integer declarations retain mappings until target selection',
    () async {
      final result = await AnalysisSession([
        'test/compiler/fixtures/abi_integers.dart',
      ], sources: await SdkSources.load()).use(Lowering().lower);
      final exports = {
        for (final export in result.exports.values) export.symbol: export,
      };
      final integer =
          exports['identity']!.signature.result as NativeAbiIntegerType;
      for (final (target, bytes, signed, cType) in [
        (const Target(.macos, .arm64), 1, true, 'int8_t'),
        (const Target(.macos, .x64), 2, true, 'int16_t'),
        (const Target(.linux, .arm64), 2, false, 'uint16_t'),
        (const Target(.linux, .x64), 4, true, 'int32_t'),
      ]) {
        expect(NativeLayout(target).of(integer).size, bytes);
        expect(integer.resolveAbi(target.abi).integerLayout!.signed, signed);
        final header = StringBuffer();
        NativeExports(exports.values).writeHeader(header, abi: target.abi);
        expect(header.toString(), contains('$cType identity($cType);'));
        expect(header.toString(), contains('  $cType value;'));
        expect(header.toString(), contains('  $cType values[3];'));
      }
      final instructions = result.program.functions
          .expand((f) => f.blocks)
          .expand((b) => b.instructions);
      expect(
        instructions.whereType<LoadNative>().any(
          (op) => identical(op.nativeType, integer),
        ),
        isTrue,
      );
      expect(
        instructions.whereType<StoreNative>().any(
          (op) => identical(op.nativeType, integer),
        ),
        isTrue,
      );
    },
  );
}
