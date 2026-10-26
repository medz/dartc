import 'arm64.dart';
import 'ir.dart';

List<int> image = <int>[];

void image32(int value) {
  image.add(value & 255);
  image.add((value >> 8) & 255);
  image.add((value >> 16) & 255);
  image.add((value >> 24) & 255);
}

void image64(int value) {
  image32(value & 0xffffffff);
  image32(value >> 32);
}

void imageName(String name, int width) {
  int i = 0;
  while (i < width) {
    if (i < name.length) {
      image.add(name.codeUnitAt(i));
    } else {
      image.add(0);
    }
    i = i + 1;
  }
}

void imageZeros(int count) {
  int i = 0;
  while (i < count) {
    image.add(0);
    i = i + 1;
  }
}

void imagePatch32(int offset, int value) {
  image[offset] = value & 255;
  image[offset + 1] = (value >> 8) & 255;
  image[offset + 2] = (value >> 16) & 255;
  image[offset + 3] = (value >> 24) & 255;
}

int alignImage(int value, int alignment) {
  return (value + alignment - 1) & ~(alignment - 1);
}

void imageSegment(
  String name,
  int address,
  int memorySize,
  int offset,
  int fileSize,
  int protection,
  int sections,
) {
  image32(0x19);
  image32(72 + sections * 80);
  imageName(name, 16);
  image64(address);
  image64(memorySize);
  image64(offset);
  image64(fileSize);
  image32(protection);
  image32(protection);
  image32(sections);
  image32(0);
}

void imageSection(
  String name,
  String segment,
  int address,
  int offset,
  int size,
  int flags,
) {
  imageName(name, 16);
  imageName(segment, 16);
  image64(address);
  image64(size);
  image32(offset);
  image32(3);
  image32(0);
  image32(0);
  image32(flags);
  image32(0);
  image32(0);
  image32(0);
}

List<int> createExecutable() {
  int base = 0x100000000;
  int dataBase = 0x110000000;
  int page = 0x4000;
  int codeOffset = 0x1000;
  int constantOffset = alignImage(codeOffset + machineCode.length * 4, 8);
  List<int> stringOffsets = <int>[];
  int payloadEnd = constantOffset;
  int s = 0;
  while (s < strings.length) {
    stringOffsets.add(payloadEnd);
    payloadEnd = payloadEnd + 8 + strings[s].length * 8;
    s = s + 1;
  }
  int textSize = alignImage(payloadEnd, page);
  int dataSize = alignImage(globalNames.length * 8, page);
  int site = 0;
  while (site < addressSites.length) {
    int target = 0;
    if (addressKinds[site] == 0) {
      target = base + stringOffsets[addressTargets[site]];
    } else {
      target = dataBase + addressTargets[site] * 8;
    }
    int word = addressSites[site];
    int pc = base + codeOffset + word * 4;
    int pages = ((target >> 12) - (pc >> 12)) & 0x1fffff;
    machineCode[word] = 0x90000000 | ((pages & 3) << 29) | ((pages >> 2) << 5);
    machineCode[word + 1] = 0x91000000 | ((target & 0xfff) << 10);
    site = site + 1;
  }

  image = <int>[];
  image32(0xfeedfacf);
  image32(0x100000c);
  image32(0);
  image32(2);
  image32(12);
  image32(0);
  image32(0x200085);
  image32(0);
  imageSegment('__PAGEZERO', 0, base, 0, 0, 0, 0);
  imageSegment('__TEXT', base, textSize, 0, textSize, 5, 2);
  imageSection(
    '__text',
    '__TEXT',
    base + codeOffset,
    codeOffset,
    machineCode.length * 4,
    0x80000400,
  );
  imageSection(
    '__const',
    '__TEXT',
    base + constantOffset,
    constantOffset,
    payloadEnd - constantOffset,
    0,
  );
  imageSegment('__DATA', dataBase, dataSize, textSize, 0, 3, 1);
  imageSection('__bss', '__DATA', dataBase, 0, globalNames.length * 8, 1);
  imageSegment('__LINKEDIT', dataBase + dataSize, page, textSize, 16, 1, 0);

  image32(0xe);
  image32(32);
  image32(12);
  imageName('/usr/lib/dyld', 20);
  image32(0xc);
  image32(56);
  image32(24);
  image32(0);
  image32(0x10000);
  image32(0x10000);
  imageName('/usr/lib/libSystem.B.dylib', 32);

  image32(0x32);
  image32(24);
  image32(1);
  image32(0xb0000);
  image32(0x1a0000);
  image32(0);

  int hash = 0x811c9dc5;
  int h = 0;
  while (h < machineCode.length) {
    hash = ((hash ^ machineCode[h]) * 0x01000193) & 0xffffffff;
    h = h + 1;
  }
  image32(0x1b);
  image32(24);
  image32(hash);
  image32((hash * 0x01000193) & 0xffffffff);
  image32((hash ^ payloadEnd) & 0xffffffff);
  image32((hash ^ globalNames.length) & 0xffffffff);

  image32(0x80000028);
  image32(24);
  image64(codeOffset);
  image64(0);
  image32(0x2);
  image32(24);
  image32(textSize);
  image32(0);
  image32(textSize);
  image32(1);
  image32(0xb);
  image32(80);
  imageZeros(72);
  image32(0x80000022);
  image32(48);
  imageZeros(40);
  imagePatch32(20, image.length - 32);
  imageZeros(codeOffset - image.length);
  int instruction = 0;
  while (instruction < machineCode.length) {
    image32(machineCode[instruction]);
    instruction = instruction + 1;
  }
  imageZeros(constantOffset - image.length);
  int stringIndex = 0;
  while (stringIndex < strings.length) {
    String value = strings[stringIndex];
    image64(value.length);
    int character = 0;
    while (character < value.length) {
      image64(value.codeUnitAt(character));
      character = character + 1;
    }
    stringIndex = stringIndex + 1;
  }
  imageZeros(textSize + 16 - image.length);
  return image;
}
