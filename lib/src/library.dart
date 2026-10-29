import 'code.dart';
import 'format/image.dart';
import 'format/macho.dart';
import 'host.dart';
import 'ir.dart';
import 'sign.dart';
import 'target.dart';

List<int> libraryNames = <int>[];
List<int> libraryNameOffsets = <int>[];

List<int> _libraryUtf8(String value) {
  final bytes = <int>[];
  var i = 0;
  while (i < value.length) {
    var code = value.codeUnitAt(i++);
    if (code >= 0xd800 && code <= 0xdbff && i < value.length) {
      final low = value.codeUnitAt(i);
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00;
        i++;
      }
    }
    if (code >= 0xd800 && code <= 0xdfff) {
      print('Library name contains an unpaired UTF-16 surrogate.');
      hostExit(1);
    }
    if (code < 0x80) {
      bytes.add(code);
    } else {
      if (code < 0x800) {
        bytes.add(0xc0 | (code >> 6));
      } else if (code < 0x10000) {
        bytes.add(0xe0 | (code >> 12));
        bytes.add(0x80 | ((code >> 6) & 63));
      } else {
        bytes.add(0xf0 | (code >> 18));
        bytes.add(0x80 | ((code >> 12) & 63));
        bytes.add(0x80 | ((code >> 6) & 63));
      }
      bytes.add(0x80 | (code & 63));
    }
  }
  return bytes;
}

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
  image32(exportNames.length);
  image32(names);
  image32(libraryNames.length);
}

void librarySymbols(int codeAddress) {
  var i = 0;
  while (i < exportNames.length) {
    image32(libraryNameOffsets[i]);
    image.add(15);
    image.add(1);
    image.add(0);
    image.add(0);
    image64(codeAddress + functionOffsets[exportFunctions[i]]);
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

List<int> libraryExportTrie(int codeAddress) {
  final root = _LibraryExportNode(0, 0, -1, <_LibraryExportNode>[]);
  final nodes = <_LibraryExportNode>[root];
  var i = 0;
  while (i < exportNames.length) {
    final name = libraryNameOffsets[i];
    var length = 0;
    while (libraryNames[name + length] != 0) length++;
    final address = codeAddress + functionOffsets[exportFunctions[i]];
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
  var codeOffset = 232;
  var symbols = alignImage(codeOffset + codeSize, 8);
  var names = symbols + exportNames.length * 16;
  image = <int>[];
  libraryHeader(1, 3, 200, 0);
  imageSegment('', 0, codeSize, codeOffset, codeSize, 7, 1);
  imageSection('__text', '__TEXT', 0, codeOffset, codeSize, 0x80000400);
  librarySymtab(symbols, names);
  libraryVersion();
  imageWords(codeWords, codeSize);
  imageZeros(symbols - image.length);
  librarySymbols(0);
  libraryStringTable();
  return image;
}

void libraryArchiveField(String value, int width) {
  var i = 0;
  while (i < width) {
    if (i < value.length)
      image.add(value.codeUnitAt(i));
    else
      image.add(32);
    i++;
  }
}

void libraryArchiveHeader(String name, int length) {
  libraryArchiveField(name, 16);
  libraryArchiveField('0', 12);
  libraryArchiveField('0', 6);
  libraryArchiveField('0', 6);
  libraryArchiveField('100644', 8);
  libraryArchiveField(length.toString(), 10);
  image.add(96);
  image.add(10);
}

List<int> libraryArchive() {
  var object = libraryObject();
  var tableLength = alignImage(
    8 + exportNames.length * 8 + libraryNames.length,
    8,
  );
  var stringLength = tableLength - 8 - exportNames.length * 8;
  var objectOffset = 8 + 60 + tableLength;
  image = <int>[];
  imageName('!<arch>\n', 8);
  libraryArchiveHeader('__.SYMDEF', tableLength);
  image32(exportNames.length * 8);
  var i = 0;
  while (i < exportNames.length) {
    image32(libraryNameOffsets[i]);
    image32(objectOffset);
    i++;
  }
  image32(stringLength);
  libraryStringTable();
  imageZeros(stringLength - libraryNames.length);
  // Darwin archive members include padding to an eight-byte boundary.
  var objectLength = alignImage(object.length, 8);
  libraryArchiveHeader('dartc.o', objectLength);
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
  var textSize = alignImage(codeOffset + codeSize, page);
  var symbols = textSize;
  var names = symbols + exportNames.length * 16;
  var trieOffset = alignImage(names + libraryNames.length, 8);
  var trie = libraryExportTrie(codeOffset);
  var signatureOffset = alignImage(trieOffset + trie.length, 16);
  image = <int>[];
  libraryHeader(6, 10, 0, 0x85);
  imageSegment('__TEXT', 0, textSize, 0, textSize, 5, 1);
  imageSection(
    '__text',
    '__TEXT',
    codeOffset,
    codeOffset,
    codeSize,
    0x80000400,
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
  var name = _libraryUtf8(
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
  image32(exportNames.length);
  image32(exportNames.length);
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
  imageZeros(textSize - image.length);
  librarySymbols(codeOffset);
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
  libraryNames = <int>[0];
  libraryNameOffsets = <int>[];
  var i = 0;
  while (i < exportNames.length) {
    libraryNameOffsets.add(libraryNames.length);
    libraryNames.add(95);
    var name = _libraryUtf8(exportNames[i]);
    var j = 0;
    while (j < name.length) {
      libraryNames.add(name[j]);
      j++;
    }
    libraryNames.add(0);
    i++;
  }
  if (imageKind == ImageKind.object) return libraryObject();
  if (imageKind == ImageKind.staticLibrary) return libraryArchive();
  return libraryDylib(outputPath);
}
