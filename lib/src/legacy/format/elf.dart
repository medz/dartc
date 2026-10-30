import '../target.dart';
import 'image.dart';

void imageElfHeader(
  int type,
  int entry,
  int programs,
  int sections,
  int programCount,
  int sectionCount,
  int sectionNames,
) {
  image.add(127);
  imageName('ELF', 3);
  image.add(2); // ELF64
  image.add(1); // little endian
  image.add(1);
  imageZeros(9);
  image16(type);
  image16(targetX64 ? 62 : 183);
  image32(1);
  image64(entry);
  image64(programs);
  image64(sections);
  image32(0);
  image16(64);
  image16(programCount == 0 ? 0 : 56);
  image16(programCount);
  image16(sectionCount == 0 ? 0 : 64);
  image16(sectionCount);
  image16(sectionNames);
}

void imageElfSegment(
  int type,
  int flags,
  int offset,
  int address,
  int fileSize,
  int memorySize,
  int alignment,
) {
  image32(type);
  image32(flags);
  image64(offset);
  image64(address);
  image64(address);
  image64(fileSize);
  image64(memorySize);
  image64(alignment);
}

void imageElfSection(
  int name,
  int type,
  int flags,
  int address,
  int offset,
  int size,
  int link,
  int info,
  int alignment,
  int entrySize,
) {
  image32(name);
  image32(type);
  image64(flags);
  image64(address);
  image64(offset);
  image64(size);
  image32(link);
  image32(info);
  image64(alignment);
  image64(entrySize);
}
