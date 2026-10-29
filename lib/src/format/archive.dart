import 'image.dart';

void _field(String value, int width) {
  for (var i = 0; i < width; i++)
    image.add(i < value.length ? value.codeUnitAt(i) : 32);
}

void imageArchiveHeader(String name, int length) {
  _field(name, 16);
  _field('0', 12);
  _field('0', 6);
  _field('0', 6);
  _field('100644', 8);
  _field(length.toString(), 10);
  image.add(96);
  image.add(10);
}
