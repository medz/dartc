import 'dart:collection';
import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

/// Relocates a sorted return-PC index and its shared suspended-frame records.
final class StackMaps() {
  final _entries = <(int, StackRoots, int?, int?)>[];
  final _addresses = <int, List<(int, FixupEncoding)>>{};

  /// Adds roots and the optional immutable source-frame metadata symbol.
  void add(
    int returnAddress,
    StackRoots roots,
    int? description, [
    int? context,
  ]) {
    _entries.add((returnAddress, roots, description, context));
  }

  void reference(int offset, FixupEncoding encoding, int returnAddress) {
    (_addresses[returnAddress] ??= []).add((offset, encoding));
  }

  int? finish(
    List<Section> sections,
    List<Symbol> symbols,
    List<Relocation> relocations,
  ) {
    if (_entries.isEmpty) return null;
    _entries.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < _entries.length; i++) {
      if (_entries[i - 1].$1 == _entries[i].$1) {
        throw StateError(
          'Duplicate stack-map return address: ${_entries[i].$1}',
        );
      }
    }
    final records = HashMap<(StackRoots, int?, int?), int>(
      equals: (a, b) =>
          a.$2 == b.$2 &&
          a.$3 == b.$3 &&
          a.$1.callerStackOffset == b.$1.callerStackOffset &&
          a.$1.returnAddressOffset == b.$1.returnAddressOffset &&
          a.$1.offsets.length == b.$1.offsets.length &&
          a.$1.offsets.indexed.every((e) => e.$2 == b.$1.offsets[e.$1]),
      hashCode: (entry) => Object.hash(
        entry.$2,
        entry.$3,
        entry.$1.callerStackOffset,
        entry.$1.returnAddressOffset,
        Object.hashAll(entry.$1.offsets),
      ),
    );
    var offset =
        StackMapTable.entries + _entries.length * StackMapTable.entrySize;
    final data = ByteData(
      _entries.fold(
        offset,
        (size, entry) => size + StackMapRecord.callerStack + entry.$2.size,
      ),
    );
    data.setUint64(StackMapTable.count, _entries.length, .little);
    for (final (i, (address, roots, description, context))
        in _entries.indexed) {
      final index = StackMapTable.entries + i * StackMapTable.entrySize;
      for (final (position, encoding)
          in _addresses[address] ?? const <(int, FixupEncoding)>[]) {
        relocations.add(.instruction(0, position, encoding, symbols.length));
      }
      relocations.add(
        .address(sections.length, index + StackMapTable.pc, symbols.length),
      );
      symbols.add(.new('.dartc.return', 0, address, null, binding: .local));
      final record = records.putIfAbsent((roots, description, context), () {
        final record = offset;
        if (description != null) {
          relocations.add(
            .address(
              sections.length,
              record + StackMapRecord.description,
              description,
            ),
          );
        }
        data.setUint64(
          record + StackMapRecord.context,
          context == null ? 0 : context + 1,
          .little,
        );
        roots.writeTo(data, record + StackMapRecord.callerStack);
        offset += StackMapRecord.callerStack + roots.size;
        return record;
      });
      data.setUint64(index + StackMapTable.record, record, .little);
    }
    final table = symbols.length;
    symbols.add(
      .new(
        '.dartc.roots',
        sections.length,
        0,
        offset,
        kind: .data,
        binding: .local,
      ),
    );
    sections.add(
      .readOnlyData(data.buffer.asUint8List(0, offset), alignment: 8),
    );
    return table;
  }
}
