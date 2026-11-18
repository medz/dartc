import 'dart:ffi';

import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

void main() {
  final signature = NativeSignature(Int64, [Int64]);
  for (final isLeaf in [false, true]) {
    for (final critical in [false, true]) {
      test(
        'native effects and their promises survive prepare ($isLeaf, $critical)',
        () {
          final foreign = FunctionTarget(null, 'read', .integer, [.integer]);
          final consumer = FunctionTarget(null, 'consumer', .integer, [
            .integer,
          ]);
          final block = Block(consumer.parameterTypes);
          block.finish(
            Return(block.emit(DirectCall(foreign, block.parameters))),
          );
          final source = IrExternal(
            foreign,
            effects: {
              Effect.readsStorage,
              Effect.allocates,
              Effect.callsUserCode,
              Effect.mayThrow,
            },
            memory: const .unchanged(),
            capturesArguments: false,
          );
          final program = IrProgram(
            [],
            [
              IrFunction(consumer, [block]),
            ],
            externals: [source],
          );
          final compiler = Compiler(Target.host());
          final imports = {
            foreign: NativeImport(
              'read',
              signature,
              isLeaf: isLeaf,
              isNonAllocating: critical,
            ),
          };
          final prepared = compiler.prepare(
            program,
            roots: [consumer],
            imports: imports,
          );
          final bound = prepared.program.nativeBoundaries!.imports.entries
              .singleWhere((b) => b.value.source == foreign);
          final terminal =
              prepared.program.implementationOf(bound.key) as IrExternal;
          expect(terminal.effects, {
            Effect.readsStorage,
            if (!isLeaf && !critical) Effect.callsUserCode,
            if (!critical) ...[Effect.mayThrow, Effect.allocates],
          });
          expect(terminal.capturesArguments, isFalse);
          expect(terminal.terminates, isFalse);
          expect(terminal.memory, same(source.memory));
          expect(
            () => compiler.prepare(
              prepared.program,
              roots: [consumer],
              imports: {
                foreign: NativeImport(
                  'read',
                  signature,
                  isLeaf: isLeaf,
                  isNonAllocating: !critical,
                ),
              },
            ),
            throwsArgumentError,
          );
        },
      );
    }
  }
}
