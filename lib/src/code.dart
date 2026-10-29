// Code offsets are bytes. Packed words avoid allocating one list slot per byte
// while allowing both fixed-width and variable-length instruction encoders.
final List<int> codeWords = <int>[];
int codeSize = 0;

class CodeAddress(final int offset, final int kind, final int target);
class CodeCall(final int offset, final int function);

final List<CodeAddress> codeAddresses = <CodeAddress>[];
final List<CodeCall> codeCalls = <CodeCall>[];
final List<int> functionOffsets = <int>[];

void codeByte(int value) {
  final shift = (codeSize & 3) * 8;
  if (shift == 0)
    codeWords.add(value & 255);
  else
    codeWords[codeSize >> 2] |= (value & 255) << shift;
  codeSize++;
}

void codeWord(int value) {
  if ((codeSize & 3) == 0) {
    codeWords.add(value & 0xffffffff);
    codeSize += 4;
  } else {
    for (var i = 0; i < 4; i++) codeByte(value >>> (i * 8));
  }
}

void codePatchWord(int offset, int value) {
  if ((offset & 3) == 0) {
    codeWords[offset >> 2] = value & 0xffffffff;
  } else {
    for (var i = 0; i < 4; i++) {
      final at = offset + i;
      final shift = (at & 3) * 8;
      codeWords[at >> 2] =
          (codeWords[at >> 2] & ~(255 << shift)) |
          (((value >>> (i * 8)) & 255) << shift);
    }
  }
}
