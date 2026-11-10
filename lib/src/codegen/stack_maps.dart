import 'dart:typed_data';

import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

/// Relocates return addresses to the stack records of suspended callers.
///
/// A little-endian count precedes (absolute return address, StackRoots) entries.
final class StackMaps() {
  final _entries = <(int, StackRoots)>[];

  void add(int returnAddress, StackRoots roots) {
    _entries.add((returnAddress, roots));
  }

  void finish(
    List<Section> sections,
    List<Symbol> symbols,
    List<Relocation> relocations,
  ) {
    if (_entries.isEmpty) return;
    final data = ByteData(
      _entries.fold(8, (size, entry) => size + 8 + entry.$2.size),
    );
    data.setUint64(0, _entries.length, .little);
    var offset = 8;
    for (final (address, roots) in _entries) {
      relocations.add(.address(sections.length, offset, symbols.length));
      symbols.add(.new('.dartc.return', 0, address, null, binding: .local));
      roots.writeTo(data, offset + 8);
      offset += 8 + roots.size;
    }
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
  }
}
