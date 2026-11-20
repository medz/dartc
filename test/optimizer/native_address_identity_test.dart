import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/codegen.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/src/optimizer/flow_memory.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const zero = Constant.integer(0);
  const bytes = Constant.integer(16);
  for (final compareAdjacent in [false, true]) {
    test(
      'two live mappings from a repeated site (compare=$compareAdjacent)',
      () {
        final reserve = FunctionTarget(null, 'reserve', .integer, [.integer]);
        final target = FunctionTarget(null, 'calculate', .integer, []);
        final start = Block(),
            loop = Block([.integer]),
            valid = Block(),
            first = Block(),
            second = Block(),
            failed = Block();
        start.finish(Jump(loop, [zero]));
        final previous = loop.parameters.single;
        final current = loop.emit(DirectCall(reserve, [bytes]));
        loop.finish(
          Branch(loop.emit(Equals(current, zero)), Jump(failed), Jump(valid)),
        );
        valid.finish(
          Branch(valid.emit(Equals(previous, zero)), Jump(first), Jump(second)),
        );
        first.finish(Jump(loop, [current]));
        failed.finish(const Return(Constant.integer(-1)));
        final blocks = [start, loop, valid, first, second, failed];
        if (compareAdjacent) {
          final adjacent = Block(), far = Block();
          final end = second.emit(IntBinary(.add, previous, bytes));
          second.finish(
            Branch(
              second.emit(Equals(end, current)),
              Jump(adjacent),
              Jump(far),
            ),
          );
          adjacent.finish(const Return(Constant.integer(91)));
          far.finish(const Return(Constant.integer(17)));
          blocks.addAll([adjacent, far]);
        } else {
          second.finish(
            Return(second.emit(IntBinary(.subtract, current, previous))),
          );
        }
        final entry = IrFunction(target, blocks);
        final graph = IrProgram(
          [],
          [entry],
          externals: [
            IrExternal(
              reserve,
              effects: {},
              memory: const ExternalMemory.zeroed(0),
            ),
          ],
        );
        final flow = ProgramFlow(
          graph,
          [(target: target, arguments: [])],
          memoryLayout: ProgramLayout(
            [],
            nativeLayout: NativeLayout(Target.host()),
          ),
        );
        final simplified = const ProgramSimplification().run(flow.facts);
        for (final program in [graph, simplified]) {
          for (final (a, b) in [
            (0x8000, 0x8010),
            (0x8000, 0x4020),
            (0x8000, 0),
          ]) {
            final leases = [a, b].iterator;
            final ir = IrInterpreter(
              program,
              {},
              externalCalls: {
                reserve: (_) {
                  expect(leases.moveNext(), isTrue);
                  return leases.current;
                },
              },
            );
            expect(
              ir.run(program.functions.single, []),
              b == 0
                  ? -1
                  : compareAdjacent
                  ? (b == a + 16 ? 91 : 17)
                  : b - a,
            );
          }
        }
      },
    );
  }

  test('joining static addresses preserves word equality and attached capabilities', () {
    final descriptor = ClassType(null, 'Header');
    final entry = FunctionTarget(null, 'identity', .integer, []);
    final callback = StaticCallbackTarget(
      entry,
      FunctionType(FfiTypes.int64, []),
      exceptionalReturn: zero,
    );
    final inputs = Block([.integer, .integer]).parameters;
    final word = NativeScalarType(Int64);
    final layout = NativeLayout(Target.host());
    for (final base in [descriptor, entry, callback]) {
      final address = FlowValue.address(FlowAddress(base, 8));
      for (final v in [
        address,
        address.withReferences([FlowValue.address(FlowAddress(callback, 0))]),
      ]) {
        final a = v.withSource(inputs.first, entry);
        final b = v.withSource(inputs.last, entry);
        final merged = a.join(b).withSources([]);
        expect(merged, v);
        expect(merged.hashCode, v.hashCode);
        final memory = FlowMemory(0, 16)
            .write(0, word, a, layout)
            .join(FlowMemory(0, 16).write(0, word, b, layout));
        expect(memory.read(0, word, layout).withSources([]), v);
      }
    }
  });
}
