import 'dart:ffi';

import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import 'fixtures/control_flow.dart';

void main() {
  test('throw generation supplies trace capture and managed frame records', () {
    final target = FunctionTarget(.parse('memory:throw'), 'fail', .voidType, [
      .object,
    ]);
    final body = Block(target.parameterTypes);
    body.finish(Throw(body.parameters.single));
    final program = IrProgram([], [
      IrFunction(target, [body]),
    ]);
    for (final CodeGenerator generator in [
      Arm64CodeGenerator(const Target(.linux, .arm64)),
      X64CodeGenerator(const Target(.linux, .x64)),
    ]) {
      final module = generator.generate(program, definitions: [target]);
      expect(module.imports, isEmpty);
      expect(
        module.symbols.map((s) => s.name),
        containsAll(['capture', 'captureFrames', '.dartc.roots']),
      );
    }
  });

  test(
    'an infinite graph emits backward control flow without inventing a return',
    () {
      for (final arch in Architecture.values) {
        final module = controlFlow(Target(.linux, arch));
        final symbol = module.symbols.last;
        final bytes = Uint8List.sublistView(
          module.sections.single.bytes,
          symbol.offset,
          symbol.offset + symbol.size!,
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
              target: NativeExport(
                'predicate',
                NativeSignature(Int64, List.filled(0, Int64)),
              ),
            },
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
