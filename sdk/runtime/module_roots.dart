import 'dart:ffi';

import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Walks every mutable module object, including objects with no heap page.
final class ModuleRoots(final int context) {
  int _cursor = 0, _remaining = 0;
  int address = 0;

  void start() {
    address = 0;
    final table = Pointer<Int64>.fromAddress(
      context + RuntimeContext.globalRoots,
    ).value;
    if (table == 0) {
      _cursor = 0;
      _remaining = 0;
      return;
    }
    _remaining = Pointer<Int64>.fromAddress(table + ModuleRootTable.count)
        .value;
    if (_remaining < 0) Memory.fail();
    _cursor = table + ModuleRootTable.entries;
  }

  bool moveNext() {
    if (_remaining == 0) {
      address = 0;
      return false;
    }
    address = Pointer<Int64>.fromAddress(_cursor).value;
    if (address == 0) Memory.fail();
    _cursor += ModuleRootTable.entrySize;
    _remaining--;
    return true;
  }
}
