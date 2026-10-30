import 'code.dart';
import 'exports.dart';
import 'library_data.dart';
import 'library_elf.dart';
import 'format/archive.dart';
import 'format/image.dart';
import 'format/macho.dart';
import 'utf8.dart';
import 'ir.dart';
import 'sign.dart';
import 'target.dart';

class _LibraryExportNode {
  int name;
  int length;
  int address;
  int offset = 0;
  List<_LibraryExportNode> children;

  _LibraryExportNode(this.name, this.length, this.address, this.children);
}

void libraryHeader(int kind, int commands, int size, int flags) {
  image32(0xfeedfacf);
  image32(targetX64 ? 0x1000007 : 0x100000c);
  image32(targetX64 ? 3 : 0);
  image32(kind);
  image32(commands);
  image32(size);
  image32(flags);
  image32(0);
}

void libraryVersion() {
  image32(0x32);
  image32(24);
  image32(1);
  image32(0xb0000);
  image32(0x1a0000);
  image32(0);
}

void librarySymtab(int symbols, int names) {
  image32(2);
  image32(24);
  image32(symbols);
  image32(checkedExports.length);
  image32(names);
  image32(libraryNames.length);
}

void librarySymbols(int codeAddress, int dataAddress) {
  var i = 0;
  while (i < checkedExports.length) {
    image32(libraryNameOffsets[i]);
    image.add(15);
    image.add(checkedExports[i].function >= 0 ? 1 : 2);
    image.add(0);
    image.add(0);
    image64(librarySymbolAddress(i, codeAddress, dataAddress));
    i++;
  }
}

void libraryStringTable() {
  var i = 0;
  while (i < libraryNames.length) {
    image.add(libraryNames[i]);
    i++;
  }
}

void libraryUleb(List<int> bytes, int value) {
  while (true) {
    var byte = value & 127;
    value = value >> 7;
    if (value != 0) byte = byte | 128;
    bytes.add(byte);
    if (value == 0) return;
  }
}

List<int> libraryExportTrie(int codeAddress, int dataAddress) {
  final root = _LibraryExportNode(0, 0, -1, <_LibraryExportNode>[]);
  final nodes = <_LibraryExportNode>[root];
  var i = 0;
  while (i < checkedExports.length) {
    final name = libraryNameOffsets[i];
    var length = 0;
    while (libraryNames[name + length] != 0) length++;
    final address = librarySymbolAddress(i, codeAddress, dataAddress);
    var node = root;
    var at = 0;
    while (at < length) {
      var child = 0;
      while (child < node.children.length &&
          libraryNames[node.children[child].name] != libraryNames[name + at])
        child++;
      if (child == node.children.length) {
        final leaf = _LibraryExportNode(
          name + at,
          length - at,
          address,
          <_LibraryExportNode>[],
        );
        node.children.add(leaf);
        nodes.add(leaf);
        node = leaf;
        break;
      }
      final next = node.children[child];
      var common = 0;
      while (common < next.length &&
          at + common < length &&
          libraryNames[next.name + common] == libraryNames[name + at + common])
        common++;
      if (common < next.length) {
        final suffix = _LibraryExportNode(
          next.name + common,
          next.length - common,
          next.address,
          next.children,
        );
        nodes.add(suffix);
        next.length = common;
        next.address = -1;
        next.children = <_LibraryExportNode>[suffix];
      }
      at += common;
      node = next;
    }
    node.address = address;
    i++;
  }
  var bytes = <int>[];
  var changed = true;
  while (changed) {
    changed = false;
    bytes = <int>[];
    for (final node in nodes) {
      if (node.offset != bytes.length) {
        node.offset = bytes.length;
        changed = true;
      }
      final terminal = <int>[];
      if (node.address >= 0) {
        terminal.add(0);
        libraryUleb(terminal, node.address);
      }
      libraryUleb(bytes, terminal.length);
      var j = 0;
      while (j < terminal.length) {
        bytes.add(terminal[j]);
        j++;
      }
      bytes.add(node.children.length);
      for (final child in node.children) {
        j = 0;
        while (j < child.length) {
          bytes.add(libraryNames[child.name + j]);
          j++;
        }
        bytes.add(0);
        libraryUleb(bytes, child.offset);
      }
    }
  }
  return bytes;
}

List<int> libraryObject() {
  final sections = libraryData.isEmpty ? 1 : 2;
  final codeOffset = 152 + sections * 80;
  final dataAddress = alignImage(codeSize, 8);
  final size = libraryData.isEmpty
      ? codeSize
      : dataAddress + libraryData.length;
  final symbols = alignImage(codeOffset + size, 8);
  final names = symbols + checkedExports.length * 16;
  image = <int>[];
  libraryHeader(1, 3, codeOffset - 32, 0);
  imageSegment('', 0, size, codeOffset, size, 7, sections);
  imageSection('__text', '__TEXT', 0, codeOffset, codeSize, 0x80000400);
  if (libraryData.isNotEmpty)
    imageSection(
      '__const',
      '__TEXT',
      dataAddress,
      codeOffset + dataAddress,
      libraryData.length,
      0,
    );
  librarySymtab(symbols, names);
  libraryVersion();
  imageWords(codeWords, codeSize);
  if (libraryData.isNotEmpty) {
    imageZeros(codeOffset + dataAddress - image.length);
    for (final byte in libraryData) image.add(byte);
  }
  imageZeros(symbols - image.length);
  librarySymbols(0, dataAddress);
  libraryStringTable();
  return image;
}

List<int> libraryArchive() {
  var object = libraryObject();
  var tableLength = alignImage(
    8 + checkedExports.length * 8 + libraryNames.length,
    8,
  );
  var stringLength = tableLength - 8 - checkedExports.length * 8;
  var objectOffset = 8 + 60 + tableLength;
  image = <int>[];
  imageName('!<arch>\n', 8);
  imageArchiveHeader('__.SYMDEF', tableLength);
  image32(checkedExports.length * 8);
  var i = 0;
  while (i < checkedExports.length) {
    image32(libraryNameOffsets[i]);
    image32(objectOffset);
    i++;
  }
  image32(stringLength);
  libraryStringTable();
  imageZeros(stringLength - libraryNames.length);
  // Darwin archive members include padding to an eight-byte boundary.
  var objectLength = alignImage(object.length, 8);
  imageArchiveHeader('dartc.o', objectLength);
  i = 0;
  while (i < object.length) {
    image.add(object[i]);
    i++;
  }
  imageZeros(objectLength - object.length);
  return image;
}

List<int> libraryDylib(String outputPath) {
  var codeOffset = 1024;
  var pageShift = targetX64 ? 12 : 14;
  var page = 1 << pageShift;
  final dataAddress = codeOffset + alignImage(codeSize, 8);
  var textSize = alignImage(
    libraryData.isEmpty
        ? codeOffset + codeSize
        : dataAddress + libraryData.length,
    page,
  );
  var symbols = textSize;
  var names = symbols + checkedExports.length * 16;
  var trieOffset = alignImage(names + libraryNames.length, 8);
  var trie = libraryExportTrie(codeOffset, dataAddress);
  var signatureOffset = alignImage(trieOffset + trie.length, 16);
  image = <int>[];
  libraryHeader(6, 10, 0, 0x85);
  imageSegment(
    '__TEXT',
    0,
    textSize,
    0,
    textSize,
    5,
    libraryData.isEmpty ? 1 : 2,
  );
  imageSection(
    '__text',
    '__TEXT',
    codeOffset,
    codeOffset,
    codeSize,
    0x80000400,
  );
  if (libraryData.isNotEmpty)
    imageSection(
      '__const',
      '__TEXT',
      dataAddress,
      dataAddress,
      libraryData.length,
      0,
    );
  var linkeditCommand = image.length;
  imageSegment(
    '__LINKEDIT',
    textSize,
    page,
    textSize,
    signatureOffset - textSize,
    1,
    0,
  );
  var name = encodeUtf8(
    '@rpath/' + outputPath.substring(outputPath.lastIndexOf('/') + 1),
  );
  var idSize = alignImage(25 + name.length, 8);
  image32(0xd);
  image32(idSize);
  image32(24);
  image32(0);
  image32(0x10000);
  image32(0x10000);
  for (final byte in name) image.add(byte);
  imageZeros(idSize - 24 - name.length);
  image32(0xc);
  image32(56);
  image32(24);
  image32(0);
  image32(0x10000);
  image32(0x10000);
  imageName('/usr/lib/libSystem.B.dylib', 32);
  libraryVersion();
  var hash = 0x811c9dc5;
  var i = 0;
  while (i < codeWords.length) {
    hash = ((hash ^ codeWords[i]) * 0x01000193) & 0xffffffff;
    i++;
  }
  for (final byte in libraryData)
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  image32(0x1b);
  image32(24);
  image32(hash);
  image32((hash * 0x01000193) & 0xffffffff);
  image32((hash ^ codeSize) & 0xffffffff);
  image32((hash ^ libraryNames.length) & 0xffffffff);
  librarySymtab(symbols, names);
  image32(0xb);
  image32(80);
  image32(0);
  image32(0);
  image32(0);
  image32(checkedExports.length);
  image32(checkedExports.length);
  imageZeros(52);
  image32(0x80000022);
  image32(48);
  imageZeros(32);
  image32(trieOffset);
  image32(trie.length);
  var signatureCommand = image.length;
  image32(0x1d);
  image32(16);
  image32(0);
  image32(0);
  imagePatch32(20, image.length - 32);
  imageZeros(codeOffset - image.length);
  imageWords(codeWords, codeSize);
  if (libraryData.isNotEmpty) {
    imageZeros(dataAddress - image.length);
    for (final byte in libraryData) image.add(byte);
  }
  imageZeros(textSize - image.length);
  librarySymbols(codeOffset, dataAddress);
  libraryStringTable();
  imageZeros(trieOffset - image.length);
  i = 0;
  while (i < trie.length) {
    image.add(trie[i]);
    i++;
  }
  imageZeros(signatureOffset - image.length);
  signMachO(image, signatureCommand, linkeditCommand, textSize, 0, pageShift);
  return image;
}

List<int> createLibrary(String outputPath) {
  prepareLibraryData();
  if (targetOS == 1) return createElfLibrary(outputPath);
  if (imageKind == ImageKind.object) return libraryObject();
  if (imageKind == ImageKind.staticLibrary) return libraryArchive();
  return libraryDylib(outputPath);
}
