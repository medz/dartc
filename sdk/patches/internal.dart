import '../runtime/string.dart';
import '../../lib/runtime/contracts.dart' as runtime;

@patch
@runtime.Primitive(.uncheckedCast)
external T unsafeCast<T>(dynamic value);

// The integer algorithms may use 63-bit chunks on dartc's 64-bit targets.
@patch
bool get has63BitSmis => true;

@patch
class Symbol {
  final String? _privateLibrary = null;
  @patch
  const Symbol(String name) : _name = name;
  @patch
  bool operator ==(Object other) =>
      other is Symbol &&
      _name == other._name &&
      _privateLibrary == other._privateLibrary;
  @patch
  int get hashCode => _name.hashCode ^ (_privateLibrary?.hashCode ?? 0);
  @patch
  String toString() => 'Symbol("$_name")';
  @patch
  static String computeUnmangledName(Symbol symbol) => symbol._name;
}

@patch
List<T> makeListFixedLength<T>(List<T> growableList) =>
    (growableList as NativeList<T>).toFixedLength();

@patch
List<T> makeFixedListUnmodifiable<T>(List<T> fixedLengthList) =>
    (fixedLengthList as NativeList<T>).toUnmodifiable();

@patch
void writeIntoOneByteString(String string, int index, int codePoint) =>
    // SDK decoders rely on byte stores truncating UTF-8 prefix bits.
    StringStorage.write(string, index, codePoint & 0xff);

@patch
String allocateOneByteString(int length) => StringStorage.create(length);

@patch
String allocateTwoByteString(int length) => StringStorage.create(length);

@patch
void writeIntoTwoByteString(String string, int index, int codePoint) {
  assert(codePoint >= 0 && codePoint <= 0xffff);
  StringStorage.write(string, index, codePoint);
}
