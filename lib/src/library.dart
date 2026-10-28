import 'arm64.dart';
import 'format.dart';
import 'ir.dart';
import 'sign.dart';

List<int> libraryNames = <int>[];
List<int> libraryNameOffsets = <int>[];

void libraryHeader(int kind, int commands, int size, int flags) {
  image32(0xfeedfacf);
  image32(0x100000c);
  image32(0);
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
    image64(codeAddress + armFunctionOffsets[exportFunctions[i]] * 4);
    i++;
  }
}

void libraryCode() {
  var i = 0;
  while (i < machineCode.length) {
    image32(machineCode[i]);
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
  var leaves = <int>[];
  var leafOffsets = <int>[];
  var i = 0;
  while (i < exportNames.length) {
    var terminal = <int>[0];
    libraryUleb(
      terminal,
      codeAddress + armFunctionOffsets[exportFunctions[i]] * 4,
    );
    leafOffsets.add(leaves.length);
    libraryUleb(leaves, terminal.length);
    var j = 0;
    while (j < terminal.length) {
      leaves.add(terminal[j]);
      j++;
    }
    leaves.add(0);
    i++;
  }
  var rootSize = 2;
  i = 0;
  while (i < exportNames.length) {
    rootSize = rootSize + exportNames[i].length + 3;
    i++;
  }
  var root = <int>[];
  while (true) {
    root = <int>[0];
    root.add(exportNames.length);
    i = 0;
    while (i < exportNames.length) {
      root.add(95);
      var name = exportNames[i];
      var j = 0;
      while (j < name.length) {
        root.add(name.codeUnitAt(j));
        j++;
      }
      root.add(0);
      libraryUleb(root, rootSize + leafOffsets[i]);
      i++;
    }
    if (root.length == rootSize) break;
    rootSize = root.length;
  }
  i = 0;
  while (i < leaves.length) {
    root.add(leaves[i]);
    i++;
  }
  return root;
}

List<int> libraryObject() {
  var codeSize = machineCode.length * 4;
  var codeOffset = 232;
  var symbols = alignImage(codeOffset + codeSize, 8);
  var names = symbols + exportNames.length * 16;
  image = <int>[];
  libraryHeader(1, 3, 200, 0);
  imageSegment('', 0, codeSize, codeOffset, codeSize, 7, 1);
  imageSection('__text', '__TEXT', 0, codeOffset, codeSize, 0x80000400);
  librarySymtab(symbols, names);
  libraryVersion();
  libraryCode();
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
  libraryArchiveHeader('dartc.o', object.length);
  i = 0;
  while (i < object.length) {
    image.add(object[i]);
    i++;
  }
  if ((object.length & 1) != 0) image.add(10);
  return image;
}

List<int> libraryDylib(String outputPath) {
  var codeOffset = 1024;
  var codeSize = machineCode.length * 4;
  var textSize = alignImage(codeOffset + codeSize, 16384);
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
    16384,
    textSize,
    signatureOffset - textSize,
    1,
    0,
  );
  var name = '@rpath/' + outputPath.substring(outputPath.lastIndexOf('/') + 1);
  var idSize = alignImage(25 + name.length, 8);
  image32(0xd);
  image32(idSize);
  image32(24);
  image32(0);
  image32(0x10000);
  image32(0x10000);
  imageName(name, idSize - 24);
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
  while (i < machineCode.length) {
    hash = ((hash ^ machineCode[i]) * 0x01000193) & 0xffffffff;
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
  libraryCode();
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
  signMachO(image, signatureCommand, linkeditCommand, textSize, 0);
  return image;
}

List<int> createLibrary(String outputPath) {
  libraryNames = <int>[0];
  libraryNameOffsets = <int>[];
  var i = 0;
  while (i < exportNames.length) {
    libraryNameOffsets.add(libraryNames.length);
    libraryNames.add(95);
    var name = exportNames[i];
    var j = 0;
    while (j < name.length) {
      libraryNames.add(name.codeUnitAt(j));
      j++;
    }
    libraryNames.add(0);
    i++;
  }
  if (imageKind == ImageKind.object) return libraryObject();
  if (imageKind == ImageKind.staticLibrary) return libraryArchive();
  return libraryDylib(outputPath);
}
