import 'imports.dart';

/// The unit of memory protection.
const pageBytes = 0x4000;

int pageAlign(int value) => (value + pageBytes - 1) & ~(pageBytes - 1);
int align16(int value) => (value + 15) & ~15;

/// Where each part of an image is, in the file and from its base address.
///
/// The first segment holds the commands, code, import stubs and constants. The
/// second holds import slots and constant objects, and the third writable
/// objects; each exists only if it has contents. The loader's tables and the
/// signature follow.
final class MachoLayout({
  required final int textOffset,
  required final int codeBytes,
  required final int importCount,
  required final int constantBytes,
  required final int constObjectBytes,
  required final int dataBytes,
  required final bool hasFixups,

  /// Whether the first segment is an unmapped one.
  required final bool hasZeroPage,
}) {
  bool get hasConstants => constantBytes > 0;
  bool get hasDataConst => importCount > 0 || constObjectBytes > 0;
  bool get hasData => dataBytes > 0;

  int get stubsOffset => textOffset + codeBytes;
  int get textEnd => stubsOffset + importCount * arm64StubBytes;

  int get constantsOffset => hasConstants ? align16(textEnd) : textEnd;
  int get constantsEnd => constantsOffset + constantBytes;

  /// The second segment.
  int get dataConstOffset => pageAlign(constantsEnd);
  int get slotsBytes => importCount * 8;
  int get constObjectsOffset => align16(dataConstOffset + slotsBytes);
  int get dataConstBytes => hasDataConst
      ? constObjectsOffset + constObjectBytes - dataConstOffset
      : 0;

  /// The third segment.
  int get dataOffset => dataConstOffset + pageAlign(dataConstBytes);

  /// The last segment.
  int get linkOffset => dataOffset + pageAlign(dataBytes);

  /// The number of the first segment after that with the code.
  int get firstData => hasZeroPage ? 2 : 1;

  /// The number of segments.
  int get segments =>
      firstData + 1 + (hasDataConst ? 1 : 0) + (hasData ? 1 : 0);
}
