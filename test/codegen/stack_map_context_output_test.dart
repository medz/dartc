import 'dart:ffi' show Int64;
import 'dart:typed_data';

import 'package:dartc/codegen.dart';
import 'package:dartc/compiler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/runtime.dart';

void main() {
  setUpAll(prepareRuntime);
  for (final asynchronous in [false, true]) {
    test(
      'emitted return-PC slots agree with the table (async=$asynchronous)',
      () {
        final context = ClassType(
          null,
          'Frame',
          interfaces: [if (asynchronous) heapRuntime.stackContext!],
        );
        final method = FunctionTarget(
          null,
          'run',
          .integer,
          [],
          owner: context,
          kind: .method,
        );
        final entry = FunctionTarget(
          null,
          'entry',
          .integer,
          method.parameterTypes,
          executionSource: method,
        );
        final inspect = FunctionTarget(null, 'inspect', .integer, []);
        final body = Block(entry.parameterTypes);
        body.finish(Return(body.emit(DirectCall(inspect, []))));
        final maps = FunctionTarget(null, 'maps', .integer, []);
        final mapBody = Block();
        mapBody.finish(Return(mapBody.emit(StackMapAddress())));
        final query = FunctionTarget(null, 'contextFreeTable', .integer, []);
        final queryBody = Block();
        queryBody.finish(
          Return(queryBody.emit(StackMapAddress(contextFreeOnly: true))),
        );
        final graph = IrProgram(
          [IrClass(context, [])],
          [
            IrFunction(entry, [body]),
            IrFunction(maps, [mapBody]),
            IrFunction(query, [queryBody]),
          ],
          externals: [IrExternal(inspect)],
        );
        for (final architecture in Architecture.values) {
          final target = Target(.macos, architecture);
          final program = Compiler(target).prepare(
            graph,
            roots: [entry, maps, query],
            runtime: heapRuntime,
            imports: {
              inspect: NativeImport(
                'external_probe',
                NativeSignature(Int64, []),
                isLeaf: true,
                isNonAllocating: true,
              ),
            },
          );
          final generator = architecture == .arm64
              ? Arm64CodeGenerator(target)
              : X64CodeGenerator(target);
          final object = generator.generate(program);
          final table = object.symbols.singleWhere(
            (s) => s.name == '.dartc.roots',
          );
          final bytes = ByteData.sublistView(
            object.sections[table.section].bytes,
            table.offset,
            table.offset + table.size!,
          );
          final count = bytes.getUint64(StackMapTable.count, .little);
          expect(count, isPositive);
          final slot = object.symbols.singleWhere(
            (s) => s.name == '.dartc.contextFreeStackMap',
          );
          final references = object.relocations
              .whereType<AddressRelocation>()
              .where(
                (r) => r.section == slot.section && r.offset == slot.offset,
              )
              .map((r) => object.symbols[r.symbol])
              .toList();
          expect(references, asynchronous ? isEmpty : [table]);
          expect(
            ByteData.sublistView(object.sections[slot.section].bytes)
                .getUint64(slot.offset, .little),
            0,
          );
          final offsets = <int>[];
          for (var i = 0; i < count; i++) {
            final index = StackMapTable.entries + i * StackMapTable.entrySize;
            final record = bytes.getUint64(
              index + StackMapTable.record,
              .little,
            );
            final saved = bytes.getUint64(
              record + StackMapRecord.context,
              .little,
            );
            if (saved != 0) {
              final roots = StackRoots.read(
                bytes,
                record + StackMapRecord.callerStack,
              );
              expect(roots.offsets, contains(saved - 1));
              offsets.add(saved - 1);
            }
          }
          expect(offsets.isNotEmpty, asynchronous);
        }
      },
    );
  }
}
