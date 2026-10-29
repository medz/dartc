import 'code.dart';
import 'exports.dart';
import 'library_abi.dart';
import 'target.dart';
import 'utf8.dart';

List<int> libraryNames = <int>[];
List<int> libraryNameOffsets = <int>[];
List<int> libraryData = <int>[];
List<int> libraryDataOffsets = <int>[];

int librarySymbolAddress(int index, int codeAddress, int dataAddress) =>
    checkedExports[index].function >= 0
    ? codeAddress + exportOffsets[index]
    : dataAddress + libraryDataOffsets[index];

void prepareLibraryData() {
  libraryNames = <int>[0];
  libraryNameOffsets = <int>[];
  libraryData = <int>[];
  libraryDataOffsets = <int>[];
  for (final declaration in checkedExports) {
    if (declaration.function >= 0) {
      libraryDataOffsets.add(-1);
    } else {
      final width = libraryTypeSize(declaration.signature);
      while (libraryData.length % width != 0) libraryData.add(0);
      libraryDataOffsets.add(libraryData.length);
      final bits = libraryConstantBits(declaration);
      for (var byte = 0; byte < width; byte++)
        libraryData.add((bits >>> (byte * 8)) & 255);
    }
    libraryNameOffsets.add(libraryNames.length);
    if (targetOS == 0) libraryNames.add(95);
    for (final byte in encodeUtf8(declaration.symbol)) libraryNames.add(byte);
    libraryNames.add(0);
  }
}
