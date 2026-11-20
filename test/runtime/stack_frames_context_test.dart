import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/src/codegen/stack_maps.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/stack_frames.dart';

void main() {
  test(
    'a context-free physical table still walks a suspended native reentry',
    () {
      final allocate = DynamicLibrary.process()
          .lookupFunction<
            Pointer<Int64> Function(Size, Size),
            Pointer<Int64> Function(int, int)
          >('calloc');
      final free = DynamicLibrary.process()
          .lookupFunction<
            Void Function(Pointer<Int64>),
            void Function(Pointer<Int64>)
          >('free');

      final maps = StackMaps()
        ..add(16, StackRoots(16, 8, []), null)
        ..add(32, StackRoots(0, 0, []), null);
      final sections = [Section.code(Uint8List(64))];
      final symbols = <Symbol>[], relocations = <Relocation>[];
      maps.finish(sections, symbols, relocations);
      final table = ByteData.sublistView(
        Uint8List.fromList(sections.last.bytes),
      );
      for (final fixup in relocations.whereType<AddressRelocation>()) {
        table.setUint64(fixup.offset, symbols[fixup.symbol].offset, .little);
      }
      final bytes =
          RuntimeContext.size +
          RuntimeContext.entrySize * 2 +
          64 +
          table.lengthInBytes;
      final storage = allocate(bytes ~/ 8, 8);
      expect(storage, isNot(nullptr));
      addTearDown(() => free(storage));
      final context = storage.address, inner = context + RuntimeContext.size;
      final outer = inner + RuntimeContext.entrySize,
          innerSp = outer + RuntimeContext.entrySize;
      final outerSp = innerSp + 32, base = outerSp + 32;
      Pointer<Uint8>.fromAddress(base)
          .asTypedList(table.lengthInBytes)
          .setAll(0, table.buffer.asUint8List());
      void set(int position, int value) =>
          Pointer<Int64>.fromAddress(position).value = value;
      set(context + RuntimeContext.maps, base);
      set(context + RuntimeContext.active, inner);
      set(inner + RuntimeContext.previousEntry, outer);
      set(outer + RuntimeContext.suspendedSp, outerSp);
      set(outer + RuntimeContext.suspendedPc, 16);
      set(innerSp + 8, 32);
      set(outerSp + 8, 32);

      final frames = StackFrames(context)..start(innerSp, 16);
      expect(frames.mayHaveContexts(base), isFalse);
      expect(frames.mayHaveContexts(0), isTrue);
      expect(frames.mayHaveContexts(outerSp), isTrue);
      final observed = <(int, bool)>[];
      while (frames.moveNext()) {
        observed.add((frames.pc, frames.isBoundary));
        expect(frames.continuation, isNull);
      }
      expect(observed, [(16, false), (32, true), (16, false), (32, true)]);
    },
  );
}
