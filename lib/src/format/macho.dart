import 'image.dart';

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
