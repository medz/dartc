import 'code.dart';

void armMove(int target, int source) {
  codeWord(0xaa0003e0 | (source << 16) | target);
}

void armConstant(int register, int value) {
  codeWord(0xd2800000 | ((value & 65535) << 5) | register);
  var shift = 16;
  while (shift < 64) {
    var part = (value >>> shift) & 65535;
    if (part != 0) {
      codeWord(0xf2800000 | ((shift ~/ 16) << 21) | (part << 5) | register);
    }
    shift = shift + 16;
  }
}

// One word occupies a 16-byte evaluation slot, preserving platform SP alignment.
void armPush(int register) {
  codeWord(0xf81f0fe0 | register);
}

void armPop(int register) {
  codeWord(0xf84107e0 | register);
}

void armAddress(int kind, int target) {
  codeAddresses.add(CodeAddress(codeSize, kind, target));
  codeWord(0x90000000);
  codeWord(0x91000000);
}

void armLoadLocal(int slot, int register) {
  var offset = (slot + 1) * 8;
  if (offset <= 256) {
    codeWord(0xf84003a0 | (((-offset) & 511) << 12) | register);
    return;
  }
  armConstant(10, offset);
  codeWord(0xcb0a03a9);
  codeWord(0xf9400120 | register);
}

void armStoreLocal(int slot, int register) {
  var offset = (slot + 1) * 8;
  if (offset <= 256) {
    codeWord(0xf80003a0 | (((-offset) & 511) << 12) | register);
    return;
  }
  armConstant(10, offset);
  codeWord(0xcb0a03a9);
  codeWord(0xf9000120 | register);
}

void armCall(int target) {
  codeCalls.add(CodeCall(codeSize, target));
  codeWord(0x94000000);
}

void armPatchAddress(int offset, int pc, int target) {
  final pages = ((target >> 12) - (pc >> 12)) & 0x1fffff;
  codePatchWord(offset, 0x90000000 | ((pages & 3) << 29) | ((pages >> 2) << 5));
  codePatchWord(offset + 4, 0x91000000 | ((target & 0xfff) << 10));
}
