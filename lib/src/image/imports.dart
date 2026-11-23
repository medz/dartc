import 'dart:typed_data';

import 'bytes.dart';
import 'relocate.dart';

/// The bytes of one import's stub.
const stubBytes = 12;

/// Code jumping through each import's slot.
///
/// Stub i is at [address] plus i times [stubBytes], and uses the 8-byte slot
/// i at [slots]. It changes only x16, which calls never preserve.
Uint8List importStubs(List<String> names, int address, int slots) {
  final out = ByteWriter(.little);
  for (final (i, name) in names.indexed) {
    final at = address + i * stubBytes, slot = slots + i * 8;
    out
      ..u32(0x90000010 | pageField(at, slot, name)) // adrp x16
      ..u32(0xf9400210 | ((slot & 0xfff) >> 3) << 10) // ldr x16, [x16, ..]
      ..u32(0xd61f0200); // br x16
  }
  return out.finish();
}
