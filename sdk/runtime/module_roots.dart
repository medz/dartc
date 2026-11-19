import 'dart:ffi';

import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Walks every mutable module object, including objects with no heap page.
final class ModuleRoots(final int context) {
  int _table = 0, _count = 0, _index = 0;

  void start() {
    final table = Pointer<Int64>.fromAddress(
      context + RuntimeContext.globalRoots,
    ).value;
    _table = table;
    _index = 0;
    if (table == 0) return;
    _count = Pointer<Int64>.fromAddress(table + ModuleRootTable.count).value;
    if (_count < 0) Memory.fail();
  }

  /// Returns the next module object address, or zero when exhausted.
  int nextAddress() {
    final table = _table;
    if (table == 0) return 0;
    final index = _index;
    if (index >= _count) return 0;
    final address = Pointer<Int64>.fromAddress(
      table + ModuleRootTable.entries + index * ModuleRootTable.entrySize,
    ).value;
    if (address == 0) Memory.fail();
    _index = index + 1;
    return address;
  }
}
