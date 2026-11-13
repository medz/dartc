import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

/// Relocates return addresses to the stack records of suspended callers.
///
/// A little-endian count precedes (absolute return address, StackRoots) entries.
final class StackMaps() {
  final _entries = <(int, StackRoots)>[];
  final _addresses = <int, List<(int, FixupEncoding)>>{};

  void add(int returnAddress, StackRoots roots) {
    _entries.add((returnAddress, roots));
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
    final data = ByteData(
      _entries.fold(
        StackMapRecord.tableHeader,
        (size, entry) => size + StackMapRecord.callerStack + entry.$2.size,
      ),
    );
    data.setUint64(0, _entries.length, .little);
    var offset = StackMapRecord.tableHeader;
    for (final (address, roots) in _entries) {
      for (final (position, encoding)
          in _addresses[address] ?? const <(int, FixupEncoding)>[]) {
        relocations.add(.instruction(0, position, encoding, symbols.length));
      }
      relocations.add(.address(sections.length, offset, symbols.length));
      symbols.add(.new('.dartc.return', 0, address, null, binding: .local));
      roots.writeTo(data, offset + StackMapRecord.callerStack);
      offset += StackMapRecord.callerStack + roots.size;
    }
    final table = symbols.length;
    symbols.add(
      .new(
        '.dartc.roots',
        sections.length,
        0,
        data.lengthInBytes,
        kind: .data,
        binding: .local,
      ),
    );
    sections.add(.readOnlyData(data.buffer.asUint8List(), alignment: 8));
    return table;
  }
}
