import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';
import 'package:dartc/src/codegen/stack_maps.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sorted return PCs retain instruction references and variable root records',
    () {
      final maps = StackMaps();
      final roots = [
        StackRoots(64, 56, [0, 16]),
        StackRoots(0, 0, []),
        StackRoots(80, 72, [8, 24, 88]),
      ];
      maps.add(160, roots[2], 0, 8);
      maps.add(16, roots[0], 0, 0);
      maps.add(80, roots[1], null);
      maps.reference(4, .arm64Page21, 160);
      maps.reference(8, .arm64PageOffset12, 160);
      final sections = [
        Section.code(Uint8List(256)),
        Section.readOnlyData(Uint8List(8), alignment: 8),
      ];
      final symbols = [const Symbol('description', 1, 0, 8, kind: .data)];
      final relocations = <Relocation>[];
      final table = maps.finish(sections, symbols, relocations)!;
      final data = ByteData.sublistView(
        Uint8List.fromList(sections.last.bytes),
      );
      for (final relocation in relocations.whereType<AddressRelocation>()) {
        final symbol = symbols[relocation.symbol];
        data.setUint64(
          relocation.offset,
          (symbol.section + 1) * 0x10000 + symbol.offset,
          .little,
        );
      }
      expect(data.getUint64(StackMapTable.count, .little), 3);
      final offsets = <int>[];
      for (var i = 0; i < 3; i++) {
        final index = StackMapTable.entries + i * StackMapTable.entrySize;
        expect(
          data.getUint64(index + StackMapTable.pc, .little),
          0x10000 + [16, 80, 160][i],
        );
        final record = data.getUint64(index + StackMapTable.record, .little);
        offsets.add(record);
        expect(record % 8, 0);
        expect(
          record,
          greaterThanOrEqualTo(
            StackMapTable.entries + 3 * StackMapTable.entrySize,
          ),
        );
        final read = StackRoots.read(data, record + StackMapRecord.callerStack);
        expect(read.callerStackOffset, roots[i].callerStackOffset);
        expect(read.returnAddressOffset, roots[i].returnAddressOffset);
        expect(read.offsets, roots[i].offsets);
        expect(
          data.getUint64(record + StackMapRecord.description, .little),
          i == 1 ? 0 : 0x20000,
        );
        expect(
          data.getUint64(record + StackMapRecord.context, .little),
          [1, 0, 9][i],
        );
      }
      expect(offsets.toSet(), hasLength(3));
      expect(symbols[table].size, data.lengthInBytes);
      final references = relocations
          .whereType<InstructionRelocation>()
          .toList();
      expect(references.map((r) => r.offset), [4, 8]);
      expect(references.map((r) => r.encoding), [
        FixupEncoding.arm64Page21,
        FixupEncoding.arm64PageOffset12,
      ]);
      expect(references.map((r) => symbols[r.symbol].offset), [160, 160]);
    },
  );

  test('only complete frame records can share storage', () {
    final maps = StackMaps();
    maps.add(8, StackRoots(64, 56, [0, 8]), 0, 0);
    maps.add(16, StackRoots(64, 56, [0, 8]), 0, 0);
    maps.add(24, StackRoots(64, 56, [0, 8]), 1, 0);
    maps.add(32, StackRoots(64, 56, [0, 8]), 0, 8);
    maps.add(40, StackRoots(80, 56, [0, 8]), 0, 0);
    maps.add(48, StackRoots(64, 48, [0, 8]), 0, 0);
    maps.add(56, StackRoots(64, 56, [0, 16]), 0, 0);
    final sections = [
      Section.code(Uint8List(64)),
      Section.readOnlyData(Uint8List(16), alignment: 8),
    ];
    final symbols = [const Symbol('a', 1, 0, 8), const Symbol('b', 1, 8, 8)];
    final relocations = <Relocation>[];
    maps.finish(sections, symbols, relocations);
    final data = ByteData.sublistView(sections.last.bytes);
    final records = [
      for (var i = 0; i < 7; i++)
        data.getUint64(
          StackMapTable.entries +
              i * StackMapTable.entrySize +
              StackMapTable.record,
          .little,
        ),
    ];
    expect(records[0], records[1]);
    expect(records.toSet(), hasLength(6));
    expect(relocations.whereType<AddressRelocation>().length, 7 + 6);
  });

  test('large tables index every PC while sharing identical boundaries', () {
    const count = 32769;
    final maps = StackMaps();
    for (var i = count - 1; i >= 0; i--) {
      maps.add(i * 8, StackRoots(0, 0, []), null);
    }
    final sections = [Section.code(Uint8List(count * 8))];
    final symbols = <Symbol>[], relocations = <Relocation>[];
    maps.finish(sections, symbols, relocations);
    final data = ByteData.sublistView(sections.last.bytes);
    final record = StackMapTable.entries + count * StackMapTable.entrySize;
    expect(data.lengthInBytes, record + StackMapRecord.roots);
    expect(data.getUint64(StackMapTable.count, .little), count);
    for (final i in [0, 1, count ~/ 2, count - 2, count - 1]) {
      final index = StackMapTable.entries + i * StackMapTable.entrySize;
      final relocation = relocations[i];
      expect(relocation.offset, index + StackMapTable.pc);
      expect(symbols[relocation.symbol].offset, i * 8);
      expect(data.getUint64(index + StackMapTable.record, .little), record);
    }
  });

  test('empty tables emit nothing and duplicate PCs are rejected', () {
    final sections = <Section>[],
        symbols = <Symbol>[],
        relocations = <Relocation>[];
    expect(StackMaps().finish(sections, symbols, relocations), isNull);
    final maps = StackMaps()
      ..add(8, StackRoots(0, 0, []), null)
      ..add(8, StackRoots(16, 8, [0]), null);
    expect(() => maps.finish(sections, symbols, relocations), throwsStateError);
    expect(sections, isEmpty);
    expect(symbols, isEmpty);
    expect(relocations, isEmpty);
  });
}
