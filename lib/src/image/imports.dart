import 'dart:typed_data';

import 'bytes.dart';
import 'relocate.dart';

/// The bytes of one import's stub.
const arm64StubBytes = 12, x64StubBytes = 8;

/// Code jumping through each import's slot.
///
/// Stub i is at [address] plus i times [arm64StubBytes], and uses the 8-byte slot
/// i at [slots]. It changes only x16, which calls never preserve.
Uint8List arm64Stubs(List<String> names, int address, int slots) {
  final out = ByteWriter(.little);
  for (final (i, name) in names.indexed) {
    final at = address + i * arm64StubBytes, slot = slots + i * 8;
    out
      ..u32(0x90000010 | pageField(at, slot, name)) // adrp x16
      ..u32(0xf9400210 | ((slot & 0xfff) >> 3) << 10) // ldr x16, [x16, ..]
      ..u32(0xd61f0200); // br x16
  }
  return out.finish();
}

/// The same for x64, where they change nothing.
Uint8List x64Stubs(List<String> names, int address, int slots) {
  final out = ByteWriter(.little);
  for (var i = 0; i < names.length; i++) {
    final at = address + i * x64StubBytes, slot = slots + i * 8;
    out
      ..u8(0xff) // jmp [rip + ..]
      ..u8(0x25)
      ..u32(slot - (at + 6))
      ..u16(0x9090); // nop
  }
  return out.finish();
}
