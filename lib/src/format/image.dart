List<int> image = <int>[];

void image16(int value) {
  image.add(value & 255);
  image.add((value >> 8) & 255);
}

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

void imageWords(List<int> words, int byteSize) {
  var offset = 0;
  while (offset + 4 <= byteSize) {
    image32(words[offset >> 2]);
    offset += 4;
  }
  while (offset < byteSize) {
    image.add((words[offset >> 2] >>> ((offset & 3) * 8)) & 255);
    offset++;
  }
}
