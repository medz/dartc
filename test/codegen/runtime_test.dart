import 'dart:ffi';

import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  final uri = Uri.parse('memory:runtime-calls');
  final entry = FunctionTarget(uri, 'entry', .integer, []);

  IrFunction mainBody({required bool managed}) {
    final block = Block();
    block.finish(
      Return(
        managed
            ? block.emit(
                CollectionLength(
                  block.emit(NewCollection(CoreTypes.listOf(.integer))),
                ),
              )
            : const Constant.integer(42),
      ),
    );
    return IrFunction(entry, [block]);
  }

  for (final CodeGenerator generator in [
    Arm64CodeGenerator(const Target(.linux, .arm64)),
    X64CodeGenerator(const Target(.linux, .x64)),
  ]) {
    test('${generator.target} rejects foreign runtime dependencies', () {
      final foreign = FunctionTarget(uri, 'foreign', .integer, [
        .integer,
        .integer,
      ]);
      final target = FunctionTarget(
        uri,
        'capacity',
        .integer,
        foreign.parameterTypes,
      );
      final block = Block(target.parameterTypes);
      block.finish(Return(block.emit(DirectCall(foreign, block.parameters))));
      expect(
        () => generator.generate(
          IrProgram(
            [],
            [mainBody(managed: true)],
            externals: [IrExternal(foreign)],
          ),
          definitions: [entry, foreign],
          imports: {
            foreign: NativeImport(
              'foreign',
              NativeSignature(Int64, [Int64, Int64]),
              isLeaf: true,
            ),
          },
          heapCapacity: IrFunction(target, [block]),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'contract',
            contains('foreign'),
          ),
        ),
      );
    });

    test(
      '${generator.target} retains source runtime only for managed code',
      () {
        for (final managed in [false, true]) {
          final program = IrProgram([], [mainBody(managed: managed)]);
          final module = generator.generate(
            program,
            definitions: [entry],
            heapCapacity: heapCapacity,
          );
          expect(module.symbols.any((s) => s.name == 'heapCapacity'), managed);
          if (managed) {
            expect(
              () => generator.generate(program, definitions: [entry]),
              throwsArgumentError,
            );
          }
        }
      },
    );

    test('${generator.target} checks transitive runtime effects', () {
      for (final allocates in [false, true]) {
        final target = FunctionTarget(uri, 'capacity', .integer, [
          .integer,
          .integer,
        ]);
        final dependency = FunctionTarget(uri, 'dependency', .integer, [
          .integer,
        ]);
        final call = Block(target.parameterTypes);
        call.finish(
          Return(call.emit(DirectCall(dependency, [call.parameters.first]))),
        );
        final helper = Block(dependency.parameterTypes);
        if (allocates) {
          final object = helper.emit(
            TypeView(helper.parameters.single, .object),
          );
          helper.finish(
            Return(helper.emit(ObjectHashCode(object, direct: true))),
          );
        } else {
          helper.finish(Throw(Constant.string('capacity failure')));
        }
        final program = IrProgram([], [
          mainBody(managed: true),
          IrFunction(dependency, [helper]),
        ]);
        expect(
          () => generator.generate(
            program,
            definitions: [entry],
            heapCapacity: IrFunction(target, [call]),
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'contract',
              contains('must not allocate'),
            ),
          ),
        );
      }
    });
  }
}
