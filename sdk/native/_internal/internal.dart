import 'dart:_heap/machine.dart' show classNumber, outputBuffer, store8, write;
import 'dart:_heap/objects.dart' as objects;

@patch
T unsafeCast<T>(dynamic v) => objects.unsafeCast<T>(v);

@patch
void reachabilityFence(Object? object) {}

@patch
bool get has63BitSmis => true;

@patch
String allocateOneByteString(int length) => objects.newCoreArray(
  '_OneByteString',
  length,
);

@patch
void writeIntoOneByteString(String string, int index, int codePoint) =>
    objects.storeUint8(string, index, codePoint);

@patch
String allocateTwoByteString(int length) => objects.newCoreArray(
  '_TwoByteString',
  length * 2,
);

@patch
void writeIntoTwoByteString(String string, int index, int codePoint) =>
    objects.storeUint16(string, index * 2, codePoint);

@patch
List<T> makeListFixedLength<T>(List<T> growableList) =>
    growableList.toList(growable: false);

@patch
List<T> makeFixedListUnmodifiable<T>(List<T> fixedLengthList) {
  final length = fixedLengthList.length;
  final result = objects.newCoreArray<List<T>>('_ImmutableList', length);
  for (var i = 0; i < length; i++) {
    objects.storeReference(result, i, fixedLengthList[i]);
  }
  return result;
}

@patch
class ClassID {
  @patch
  static int getID(Object? value) => value == null ? -2 : classNumber(value);
  @patch
  static int get cidArray => objects.coreClassNumber('_List');
  @patch
  static int get cidGrowableObjectArray =>
      objects.coreClassNumber('_GrowableList');
  @patch
  static int get cidImmutableArray => objects.coreClassNumber('_ImmutableList');
  @patch
  static int get cidOneByteString => objects.coreClassNumber('_OneByteString');
  @patch
  static int get cidTwoByteString => objects.coreClassNumber('_TwoByteString');
}

const _bufferBytes = 4096;

/// Writes [text] to [file] as UTF-8, with a newline if [isLine].
///
/// It creates no objects, as there may be no memory left.
void writeText(int file, String text, bool isLine) {
  final buffer = outputBuffer(), length = text.length;
  var count = 0;
  for (var i = 0; i < length; i++) {
    var point = text.codeUnitAt(i);
    if (point >= 0xd800 && point < 0xe000) {
      final next = i + 1 < length ? text.codeUnitAt(i + 1) : 0;
      if (point < 0xdc00 && next >= 0xdc00 && next < 0xe000) {
        point = ((point - 0xd7c0) << 10) + (next & 0x3ff);
        i++;
      } else {
        point = 0xfffd;
      }
    }
    if (point < 0x80) {
      store8(buffer + count++, point);
    } else {
      if (point < 0x800) {
        store8(buffer + count++, 0xc0 | point >> 6);
      } else {
        if (point < 0x10000) {
          store8(buffer + count++, 0xe0 | point >> 12);
        } else {
          store8(buffer + count++, 0xf0 | point >> 18);
          store8(buffer + count++, 0x80 | point >> 12 & 0x3f);
        }
        store8(buffer + count++, 0x80 | point >> 6 & 0x3f);
      }
      store8(buffer + count++, 0x80 | point & 0x3f);
    }
    if (count > _bufferBytes - 8) {
      write(file, buffer, count);
      count = 0;
    }
  }
  if (isLine) store8(buffer + count++, 10);
  write(file, buffer, count);
}

@patch
void printToConsole(String line) => writeText(1, line, true);

void Function(String)? _zonePrint;

@patch
void Function(String)? get printToZone => _zonePrint;

@patch
set printToZone(void Function(String)? value) {
  _zonePrint = value;
}
