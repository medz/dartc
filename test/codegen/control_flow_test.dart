import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/control_flow.dart';
import 'fixtures/control_flow_ffi.dart';

void main() {
  final native = ControlFlowGraphs();
  tearDownAll(native.close);

  test(
    'parallel edges retain distinct argument assignments to the same block',
    () {
      const values = [-0x8000000000000000, -1, 0, 42, 0x7fffffffffffffff];
      for (final a in values) {
        expect(native.scrambled(a), a + 7 + a);
        expect(native.unusedResult(a, 2, 3, 4, 5, 6), a);
        for (final b in values) {
          expect(native.sameTarget(a, b), a < b ? a - b : b - a);
        }
      }
    },
  );

  test(
    'an infinite graph emits backward control flow without inventing a return',
    () {
      for (final arch in Architecture.values) {
        final module = controlFlow(Target(.linux, arch));
        final symbol = module.symbols.last;
        final bytes = Uint8List.sublistView(
          module.code,
          symbol.offset,
          symbol.offset + symbol.size,
        );
        final data = ByteData.sublistView(bytes);
        if (arch == .arm64) {
          expect(bytes.length, 8);
          expect(data.getUint32(0, .little), 0x14000001);
          expect(data.getUint32(4, .little), 0x14000000);
        } else {
          expect(bytes, [0xe9, 0, 0, 0, 0, 0xe9, 0xfb, 0xff, 0xff, 0xff]);
        }
      }
    },
  );

  test(
    'internal boolean representation does not authorize an Int64 export',
    () {
      final target = FunctionTarget(
        .parse('memory:boolean'),
        'predicate',
        .boolean,
        [],
      );
      final entry = Block()..finish(Return(const Constant.boolean(true)));
      final program = IrProgram([], [
        IrFunction(target, [entry]),
      ]);
      for (final CodeGenerator generator in [
        Arm64CodeGenerator(const Target(.linux, .arm64)),
        X64CodeGenerator(const Target(.linux, .x64)),
      ]) {
        expect(
          () => generator.generate(
            program,
            definitions: [target],
            exports: {
              target: NativeExport('predicate', NativeSignature.int64(0)),
            },
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
