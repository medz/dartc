import 'code.dart';
import 'exports.dart';
import 'format/archive.dart';
import 'format/elf.dart';
import 'format/image.dart';
import 'ir.dart';
import 'library_abi.dart';
import 'library_data.dart';
import 'target.dart';
import 'utf8.dart';

void _symbols(int codeAddress, int dataAddress) {
  imageZeros(24); // STN_UNDEF
  for (var i = 0; i < checkedExports.length; i++) {
    final declaration = checkedExports[i];
    final function = declaration.function >= 0;
    image32(libraryNameOffsets[i]);
    image.add(function ? 0x12 : 0x11); // GLOBAL FUNC / OBJECT
    image.add(0);
    image16(function ? 1 : 2);
    image64(librarySymbolAddress(i, codeAddress, dataAddress));
    image64(function ? 0 : libraryTypeSize(declaration.signature));
  }
}

List<int> _object() {
  const sectionNames =
      '\x00.text\x00.rodata\x00.symtab\x00.strtab\x00.shstrtab\x00.note.GNU-stack\x00';
  const text = 64;
  final data = alignImage(text + codeSize, 8);
  final symbols = alignImage(data + libraryData.length, 8);
  final symbolBytes = (checkedExports.length + 1) * 24;
  final names = symbols + symbolBytes;
  final sectionStrings = names + libraryNames.length;
  final sections = alignImage(sectionStrings + sectionNames.length, 8);
  image = <int>[];
  imageElfHeader(1, 0, 0, sections, 0, 7, 5);
  imageWords(codeWords, codeSize);
  imageZeros(data - image.length);
  for (final byte in libraryData) image.add(byte);
  imageZeros(symbols - image.length);
  _symbols(0, 0);
  for (final byte in libraryNames) image.add(byte);
  imageName(sectionNames, sectionNames.length);
  imageZeros(sections - image.length);
  imageZeros(64);
  imageElfSection(1, 1, 6, 0, text, codeSize, 0, 0, 16, 0);
  imageElfSection(7, 1, 2, 0, data, libraryData.length, 0, 0, 8, 0);
  imageElfSection(15, 2, 0, 0, symbols, symbolBytes, 4, 1, 8, 24);
  imageElfSection(23, 3, 0, 0, names, libraryNames.length, 0, 0, 1, 0);
  imageElfSection(31, 3, 0, 0, sectionStrings, sectionNames.length, 0, 0, 1, 0);
  imageElfSection(41, 1, 0, 0, sectionStrings, 0, 0, 0, 1, 0);
  return image;
}

void _big32(int value) {
  image.add((value >>> 24) & 255);
  image.add((value >>> 16) & 255);
  image.add((value >>> 8) & 255);
  image.add(value & 255);
}

List<int> _archive() {
  final object = _object();
  final tableLength = 4 + checkedExports.length * 4 + libraryNames.length - 1;
  final objectOffset = 8 + 60 + alignImage(tableLength, 2);
  image = <int>[];
  imageName('!<arch>\n', 8);
  imageArchiveHeader('/', tableLength);
  _big32(checkedExports.length);
  for (var i = 0; i < checkedExports.length; i++) _big32(objectOffset);
  for (var i = 1; i < libraryNames.length; i++) image.add(libraryNames[i]);
  if ((image.length & 1) != 0) image.add(10);
  imageArchiveHeader('dartc.o/', object.length);
  for (final byte in object) image.add(byte);
  if ((image.length & 1) != 0) image.add(10);
  return image;
}

List<int> _hashTable() {
  final count = checkedExports.length;
  final bucketCount = count | 1;
  final buckets = List<int>.filled(bucketCount, 0);
  final chains = List<int>.filled(count + 1, 0);
  for (var symbol = 0; symbol < count; symbol++) {
    var hash = 0;
    var i = libraryNameOffsets[symbol];
    while (libraryNames[i] != 0) {
      hash = (hash << 4) + libraryNames[i++];
      final high = hash & 0xf0000000;
      hash = (hash ^ (high >>> 24)) & ~high;
    }
    final bucket = hash % bucketCount;
    chains[symbol + 1] = buckets[bucket];
    buckets[bucket] = symbol + 1;
  }
  return <int>[bucketCount, count + 1, ...buckets, ...chains];
}

void _dynamic(int tag, int value) {
  image64(tag);
  image64(value);
}

List<int> _shared(String outputPath) {
  const sectionNames =
      '\x00.text\x00.rodata\x00.dynsym\x00.dynstr\x00.hash\x00.dynamic\x00.shstrtab\x00';
  const text = 240; // ELF64 header and three program headers, aligned to 16.
  final data = alignImage(text + codeSize, 8);
  final symbols = alignImage(data + libraryData.length, 8);
  final symbolBytes = (checkedExports.length + 1) * 24;
  final names = symbols + symbolBytes;
  final soname = encodeUtf8(
    outputPath.substring(outputPath.lastIndexOf('/') + 1),
  );
  final nameBytes = libraryNames.length + soname.length + 1;
  final hash = alignImage(names + nameBytes, 8);
  final hashWords = _hashTable();
  final hashBytes = hashWords.length * 4;
  final dynamicOffset = alignImage(hash + hashBytes, 8);
  const dynamicBytes = 7 * 16;
  final payload = dynamicOffset + dynamicBytes;
  final sections = alignImage(payload + sectionNames.length, 8);
  image = <int>[];
  imageElfHeader(3, 0, 64, sections, 3, 8, 7);
  imageElfSegment(1, 5, 0, 0, payload, payload, targetX64 ? 4096 : 65536);
  imageElfSegment(
    2,
    4,
    dynamicOffset,
    dynamicOffset,
    dynamicBytes,
    dynamicBytes,
    8,
  );
  imageElfSegment(0x6474e551, 6, 0, 0, 0, 0, 16); // non-executable stack
  imageZeros(text - image.length);
  imageWords(codeWords, codeSize);
  imageZeros(data - image.length);
  for (final byte in libraryData) image.add(byte);
  imageZeros(symbols - image.length);
  _symbols(text, data);
  for (final byte in libraryNames) image.add(byte);
  for (final byte in soname) image.add(byte);
  image.add(0);
  imageZeros(hash - image.length);
  for (final word in hashWords) image32(word);
  imageZeros(dynamicOffset - image.length);
  _dynamic(4, hash);
  _dynamic(5, names);
  _dynamic(6, symbols);
  _dynamic(10, nameBytes);
  _dynamic(11, 24);
  _dynamic(14, libraryNames.length);
  _dynamic(0, 0);
  imageName(sectionNames, sectionNames.length);
  imageZeros(sections - image.length);
  imageZeros(64);
  imageElfSection(1, 1, 6, text, text, codeSize, 0, 0, 16, 0);
  imageElfSection(7, 1, 2, data, data, libraryData.length, 0, 0, 8, 0);
  imageElfSection(15, 11, 2, symbols, symbols, symbolBytes, 4, 1, 8, 24);
  imageElfSection(23, 3, 2, names, names, nameBytes, 0, 0, 1, 0);
  imageElfSection(31, 5, 2, hash, hash, hashBytes, 3, 0, 8, 4);
  imageElfSection(
    37,
    6,
    2,
    dynamicOffset,
    dynamicOffset,
    dynamicBytes,
    4,
    0,
    8,
    16,
  );
  imageElfSection(46, 3, 0, 0, payload, sectionNames.length, 0, 0, 1, 0);
  return image;
}

List<int> createElfLibrary(String outputPath) {
  if (imageKind == ImageKind.object) return _object();
  if (imageKind == ImageKind.staticLibrary) return _archive();
  return _shared(outputPath);
}
