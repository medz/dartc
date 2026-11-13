import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/object.dart';

/// Relocates return addresses to the stack records of suspended callers.
///
/// A count precedes records containing a return address, optional name and roots.
final class StackMaps() {
  final _entries = <(int, StackRoots, int?)>[];
  final _addresses = <int, List<(int, FixupEncoding)>>{};

  /// Adds roots and the optional constant String symbol naming their function.
  void add(int returnAddress, StackRoots roots, int? functionName) {
    _entries.add((returnAddress, roots, functionName));
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
    for (final (address, roots, functionName) in _entries) {
      for (final (position, encoding)
          in _addresses[address] ?? const <(int, FixupEncoding)>[]) {
        relocations.add(.instruction(0, position, encoding, symbols.length));
      }
      relocations.add(.address(sections.length, offset, symbols.length));
      symbols.add(.new('.dartc.return', 0, address, null, binding: .local));
      if (functionName != null) {
        relocations.add(
          .address(
            sections.length,
            offset + StackMapRecord.functionName,
            functionName,
          ),
        );
      }
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
