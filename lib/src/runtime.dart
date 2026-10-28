import 'layout.dart';
import 'binary64.dart';
import 'host.dart';

external int nativeLoad64(int p);
external int nativeStore64(int p, int value);
external int nativeLoad16(int p);
external int nativeStore16(int p, int value);
external int nativeLoad8(int p);
external int nativeStore8(int p, int value);
external int nativeSyscall(int n, int a, int b, int c, int d, int e, int f);
external int nativeTarget();
external int nativeMetadataAddress(int features);
external int nativeCall1(int function, int value);
external int nativeCall0(int function);
external int nativeFramePointer();
external int nativeValueBits(Object? value);
external Object? nativeValueFromBits(int value);

const int rtAbiVersion = 15;
const int rtArenaHeaderBytes = 48;

int rtArenaHead = 0;
int rtArenaNext = 0;
int rtArenaEnd = 0;

int rtHostTarget() {
  return nativeTarget();
}

int rtSyscall(int n, int a, int b, int c, int d, int e, int f) {
  if (nativeTarget() == 0) return nativeSyscall(n, a, b, c, d, e, f);
  if (n == 1) return nativeSyscall(93, a, b, c, d, e, f);
  if (n == 3) return nativeSyscall(63, a, b, c, d, e, f);
  if (n == 4) return nativeSyscall(64, a, b, c, d, e, f);
  if (n == 6) return nativeSyscall(57, a, b, c, d, e, f);
  if (n == 73) return nativeSyscall(215, a, b, c, d, e, f);
  if (n == 197) return nativeSyscall(222, a, b, c, 34, e, f);
  if (n == 5) {
    var flags = b;
    if (flags == 1537) flags = 577;
    return nativeSyscall(56, -100, a, flags, c, 0, 0);
  }
  if (n == 15) return nativeSyscall(53, -100, a, b, 0, 0, 0);
  return -38;
}

int rtHostExit(int code) {
  rtSyscall(1, code, 0, 0, 0, 0, 0);
  return 0;
}

int rtMap(int bytes) {
  if (bytes == 0) return 0;
  var memory = rtSyscall(197, 0, bytes, 3, 4098, -1, 0);
  if (memory < 0) rtHostExit(71);
  return memory;
}

int rtUnmap(int address, int bytes) {
  if (bytes == 0) return 0;
  return rtSyscall(73, address, bytes, 0, 0, 0, 0);
}

// Raw arena record: next0/mapBytes8/usedBytes16/bitmap24/bitmapBytes32.
@pragma('dartc:no-gc')
int rtArenaOpen(int size) {
  var capacity = 8388608;
  if (size + rtArenaHeaderBytes > capacity) {
    capacity = (size + rtArenaHeaderBytes + 16383) & -16384;
  }
  var arena = rtMap(capacity);
  var bitmapBytes = (((capacity - rtArenaHeaderBytes) ~/ 16 + 31) ~/ 32) * 8;
  var bitmap = rtMap(bitmapBytes);
  nativeStore64(arena, rtArenaHead);
  nativeStore64(arena + 8, capacity);
  nativeStore64(arena + 16, 0);
  nativeStore64(arena + 24, bitmap);
  nativeStore64(arena + 32, bitmapBytes);
  rtArenaHead = arena;
  rtArenaNext = arena + rtArenaHeaderBytes;
  rtArenaEnd = arena + capacity;
  return 0;
}

@pragma('dartc:managed-allocate')
@pragma('dartc:no-gc')
int rtAlloc(int bytes) {
  var size = (bytes + 15) & -16;
  if (rtArenaNext + size > rtArenaEnd || rtArenaNext == 0) rtArenaOpen(size);
  var result = rtArenaNext;
  var arena = rtArenaHead;
  var cell = (result - arena - rtArenaHeaderBytes) ~/ 16;
  var word = nativeLoad64(arena + 24) + (cell ~/ 32) * 8;
  nativeStore64(word, nativeLoad64(word) | (1 << ((cell * 2) & 63)));
  rtArenaNext = result + size;
  nativeStore64(arena + 16, rtArenaNext - arena - rtArenaHeaderBytes);
  return result;
}

int rtGrowBuffer(int address, int oldBytes, int newBytes) {
  var oldSize = (oldBytes + 15) & -16;
  var newSize = (newBytes + 15) & -16;
  if (address != 0 &&
      address + oldSize == rtArenaNext &&
      address + newSize <= rtArenaEnd) {
    rtArenaNext = address + newSize;
    nativeStore64(
      rtArenaHead + 16,
      rtArenaNext - rtArenaHead - rtArenaHeaderBytes,
    );
    return address;
  }
  var result = rtAlloc(newBytes);
  var offset = 0;
  while (offset + 8 <= oldBytes) {
    nativeStore64(result + offset, nativeLoad64(address + offset));
    offset = offset + 8;
  }
  while (offset < oldBytes) {
    nativeStore8(result + offset, nativeLoad8(address + offset));
    offset = offset + 1;
  }
  return result;
}

int rtCStringBytes = 0;
int rtCStringBusy = 0;

@pragma('dartc:no-gc')
int rtCStringAcquire(int a, int b, int c, int d) {
  if (rtCStringBusy != 0) {
    rtHostExit(70);
    return 0;
  }
  if (rtCStringBytes == 0) rtCStringBytes = rtMap(32);
  rtCStringBusy = 1;
  nativeStore64(rtCStringBytes, a);
  nativeStore64(rtCStringBytes + 8, b);
  nativeStore64(rtCStringBytes + 16, c);
  nativeStore64(rtCStringBytes + 24, d);
  return rtCStringBytes;
}

@pragma('dartc:no-gc')
int rtCStringRelease() {
  if (rtCStringBusy == 0) {
    rtHostExit(70);
    return 0;
  }
  rtCStringBusy = 0;
  return 0;
}

int rtWriteAll(int fd, int p, int length) {
  var offset = 0;
  while (offset < length) {
    var written = rtSyscall(4, fd, p + offset, length - offset, 0, 0, 0);
    if (written <= 0) rtHostExit(74);
    offset = offset + written;
  }
  return 0;
}

int rtIoError([int path = 0]) {
  if (path != 0) {
    var encoded = rtStringEncodeUtf8(path);
    var length = nativeLoad64(encoded);
    nativeStore8(encoded + 8 + length, 10);
    rtWriteAll(2, encoded + 8, length + 1);
    rtUtf8Release();
  }
  var message = rtCStringAcquire(0x726f727265204f49, 10, 0, 0);
  rtWriteAll(2, message, 9);
  rtHostExit(74);
  return 0;
}

int rtInitializationError() {
  var message = rtCStringAcquire(
    0x63203a6374726164,
    0x2072616c75637269,
    0x696c616974696e69,
    0xa6e6f6974617a,
  );
  rtWriteAll(2, message, 31);
  rtHostExit(70);
  return 0;
}

int rtStringLength(int value) {
  return nativeLoad64(value + stringLengthOffset);
}

int rtStringRangeError() {
  var message = rtCStringAcquire(
    0x73203a6374726164,
    0x617220676e697274,
    0x6f7272652065676e,
    0xa72,
  );
  rtWriteAll(2, message, 26);
  rtHostExit(70);
  return 0;
}

int rtStringCodeUnit(int value, int index) {
  if (index < 0 || index >= nativeLoad64(value + stringLengthOffset)) {
    return rtStringRangeError();
  }
  return nativeLoad16(value + stringDataOffset + index * 2);
}

int rtStringRawCodeUnit(int value, int index) {
  return nativeLoad16(value + stringDataOffset + index * 2);
}

int rtStringAllocate(int descriptor, int length) {
  var size = nativeLoad64(descriptor + descriptorSizeOffset);
  var result = rtAlloc(size + length * 2);
  nativeStore64(result, descriptor);
  nativeStore64(result + objectFlagsOffset, 0);
  nativeStore64(result + stringLengthOffset, length);
  return result;
}

int rtStringNew(int length) {
  var metadata = nativeMetadataAddress(metadataStrings);
  var descriptor =
      metadata + nativeLoad64(metadata + metadataStringDescriptorOffset);
  return rtStringAllocate(descriptor, length);
}

int rtStringConcat(int left, int right) {
  var a = nativeLoad64(left + stringLengthOffset);
  if (a == 0) return right;
  var b = nativeLoad64(right + stringLengthOffset);
  if (b == 0) return left;
  var mark = rtRootMark();
  rtRootPush(left, storageRef);
  rtRootPush(right, storageRef);
  var result = rtStringAllocate(rtObjectDescriptor(left), a + b);
  var i = 0;
  while (i < a) {
    nativeStore16(
      result + stringDataOffset + i * 2,
      nativeLoad16(left + stringDataOffset + i * 2),
    );
    i = i + 1;
  }
  i = 0;
  while (i < b) {
    nativeStore16(
      result + stringDataOffset + (a + i) * 2,
      nativeLoad16(right + stringDataOffset + i * 2),
    );
    i = i + 1;
  }
  rtRootRestore(mark);
  return result;
}

int rtStringEqual(int left, int right) {
  if (left == right) return 1;
  var length = nativeLoad64(left + stringLengthOffset);
  if (length != nativeLoad64(right + stringLengthOffset)) return 0;
  var i = 0;
  while (i < length) {
    if (nativeLoad16(left + stringDataOffset + i * 2) !=
        nativeLoad16(right + stringDataOffset + i * 2))
      return 0;
    i = i + 1;
  }
  return 1;
}

int rtStringSubstring(int value, int start, int end) {
  var length = nativeLoad64(value + stringLengthOffset);
  if (start < 0 || start > length || end < start || end > length) {
    return rtStringRangeError();
  }
  var result = rtStringAllocate(rtObjectDescriptor(value), end - start);
  var i = start;
  while (i < end) {
    nativeStore16(
      result + stringDataOffset + (i - start) * 2,
      nativeLoad16(value + stringDataOffset + i * 2),
    );
    i = i + 1;
  }
  return result;
}

int rtStringMatch(int value, int prefix, int start) {
  var n = nativeLoad64(prefix + stringLengthOffset);
  var i = 0;
  while (i < n) {
    if (nativeLoad16(value + stringDataOffset + (start + i) * 2) !=
        nativeLoad16(prefix + stringDataOffset + i * 2))
      return 0;
    i = i + 1;
  }
  return 1;
}

int rtStringStartsWith(int value, int prefix, int start) {
  var length = nativeLoad64(value + stringLengthOffset);
  if (start < 0 || start > length) return rtStringRangeError();
  if (nativeLoad64(prefix + stringLengthOffset) > length - start) return 0;
  return rtStringMatch(value, prefix, start);
}

int rtStringEndsWith(int value, int suffix) {
  var start =
      nativeLoad64(value + stringLengthOffset) -
      nativeLoad64(suffix + stringLengthOffset);
  if (start < 0) return 0;
  return rtStringMatch(value, suffix, start);
}

int rtStringIndexOf(int value, int needle, int start) {
  var length = nativeLoad64(value + stringLengthOffset);
  if (start < 0 || start > length) return rtStringRangeError();
  var end = length - nativeLoad64(needle + stringLengthOffset);
  var i = start;
  while (i <= end) {
    if (rtStringMatch(value, needle, i) == 1) return i;
    i = i + 1;
  }
  return -1;
}

int rtStringLastIndexOf(int value, int needle, int start) {
  var length = nativeLoad64(value + stringLengthOffset);
  if (start < 0 || start > length) return rtStringRangeError();
  var end = length - nativeLoad64(needle + stringLengthOffset);
  var i = start;
  if (i > end) i = end;
  while (i >= 0) {
    if (rtStringMatch(value, needle, i) == 1) return i;
    i = i - 1;
  }
  return -1;
}

int rtIntToString(int value) {
  var result = rtStringNew(20);
  var count = 0;
  var number = value;
  if (number > 0) number = -number;
  if (number == 0) {
    nativeStore16(result + stringDataOffset, 48);
    count = 1;
  }
  while (number < 0) {
    var quotient = number ~/ 10;
    var digit = quotient * 10 - number;
    nativeStore16(result + stringDataOffset + count * 2, 48 + digit);
    count = count + 1;
    number = quotient;
  }
  if (value < 0) {
    nativeStore16(result + stringDataOffset + count * 2, 45);
    count = count + 1;
  }
  nativeStore64(result + stringLengthOffset, count);
  var i = 0;
  var end = count - 1;
  while (i < end) {
    var digit = nativeLoad16(result + stringDataOffset + i * 2);
    nativeStore16(
      result + stringDataOffset + i * 2,
      nativeLoad16(result + stringDataOffset + end * 2),
    );
    nativeStore16(result + stringDataOffset + end * 2, digit);
    i = i + 1;
    end = end - 1;
  }
  return result;
}

int rtIntParse(int value) {
  var length = nativeLoad64(value + stringLengthOffset);
  var i = 0;
  var sign = 1;
  if (length > 0 && rtStringRawCodeUnit(value, 0) == 45) {
    sign = -1;
    i = 1;
  } else if (length > 0 && rtStringRawCodeUnit(value, 0) == 43) {
    i = 1;
  }
  var radix = 10;
  if (i + 1 < length && rtStringRawCodeUnit(value, i) == 48) {
    var x = rtStringRawCodeUnit(value, i + 1);
    if (x == 120 || x == 88) {
      radix = 16;
      i = i + 2;
    }
  }
  var result = 0;
  while (i < length) {
    var c = rtStringRawCodeUnit(value, i);
    var digit = c - 48;
    if (c >= 65 && c <= 70) digit = c - 55;
    if (c >= 97 && c <= 102) digit = c - 87;
    if (digit < 0 || digit >= radix) rtHostExit(65);
    result = result * radix + digit;
    i = i + 1;
  }
  return result * sign;
}

int rtListRangeError() {
  var message = rtCStringAcquire(
    0x6c203a6374726164,
    0x676e617220747369,
    0xa726f7272652065,
    0,
  );
  rtWriteAll(2, message, 24);
  rtHostExit(70);
  return 0;
}

int rtListFixedError() {
  var message = rtCStringAcquire(
    0x66203a6374726164,
    0x73696c2064657869,
    0x6874676e656c2074,
    0xa,
  );
  rtWriteAll(2, message, 25);
  rtHostExit(70);
  return 0;
}

int rtListReadOnlyError() {
  var message = rtCStringAcquire(
    0x69203a6374726164,
    0x656c626174756d6d,
    0xa7473696c20,
    0,
  );
  rtWriteAll(2, message, 22);
  rtHostExit(70);
  return 0;
}

int rtListNew(int typeRef) {
  var metadata = nativeMetadataAddress(metadataLists);
  var descriptor =
      metadata + nativeLoad64(metadata + metadataListDescriptorOffset);
  var result = rtAlloc(nativeLoad64(descriptor + descriptorSizeOffset));
  nativeStore64(result, descriptor);
  nativeStore64(result + objectFlagsOffset, 0);
  nativeStore64(result + listLengthOffset, 0);
  nativeStore64(result + listCapacityOffset, 0);
  nativeStore64(result + listBackingOffset, 0);
  nativeStore64(result + listTypeOffset, typeRef);
  return result;
}

int rtListFreeze(int list) {
  var flags = nativeLoad64(list + objectFlagsOffset);
  nativeStore64(
    list + objectFlagsOffset,
    flags | objectListFixed | objectListReadOnly,
  );
  return list;
}

int rtListBackingNew(int typeRef, int capacity) {
  var element = typeRef + nativeLoad64(typeRef + typeArgumentOffset);
  var slot = metadataWordArrayDescriptorOffset;
  if (nativeLoad64(element + typeValueRepOffset) == storageRef) {
    slot = metadataRefArrayDescriptorOffset;
  } else if (nativeLoad64(element + typeValueRepOffset) == storageTagged) {
    slot = metadataTaggedArrayDescriptorOffset;
  }
  var metadata = nativeMetadataAddress(metadataLists);
  var descriptor = metadata + nativeLoad64(metadata + slot);
  var result = rtAlloc(
    nativeLoad64(descriptor + descriptorSizeOffset) + capacity * 8,
  );
  nativeStore64(result, descriptor);
  nativeStore64(result + objectFlagsOffset, 0);
  nativeStore64(result + arrayLengthOffset, 0);
  return result;
}

int rtListLength(int list) {
  return nativeLoad64(list + listLengthOffset);
}

int rtListRawGet(int list, int index) {
  var backing = nativeLoad64(list + listBackingOffset);
  return nativeLoad64(backing + arrayDataOffset + index * 8);
}

int rtListElementType(int list) {
  var type = nativeLoad64(list + listTypeOffset);
  return type + nativeLoad64(type + typeArgumentOffset);
}

int rtListGet(int list, int index, int expectedType) {
  var length = nativeLoad64(list + listLengthOffset);
  if (index < 0 || index >= length) return rtListRangeError();
  var backing = nativeLoad64(list + listBackingOffset);
  var value = nativeLoad64(backing + arrayDataOffset + index * 8);
  var type = nativeLoad64(list + listTypeOffset);
  var actualType = type + nativeLoad64(type + typeArgumentOffset);
  if (actualType == expectedType) return value;
  return rtValueCast(rtValueBox(value, actualType), expectedType);
}

int rtListSet(int list, int index, int value, int sourceType) {
  var stored = value;
  var actualType = rtListElementType(list);
  var mark = -1;
  if (actualType != sourceType) {
    mark = rtRootMark();
    rtRootPush(list, storageRef);
    rtRootPushValue(value, sourceType);
    stored = rtValueCast(rtValueBox(value, sourceType), actualType);
  }
  if ((nativeLoad64(list + objectFlagsOffset) & objectListReadOnly) != 0) {
    return rtListReadOnlyError();
  }
  var length = nativeLoad64(list + listLengthOffset);
  if (index < 0 || index >= length) return rtListRangeError();
  var backing = nativeLoad64(list + listBackingOffset);
  nativeStore64(backing + arrayDataOffset + index * 8, stored);
  if (mark >= 0) rtRootRestore(mark);
  return value;
}

int rtListGrow(int list, int value, int elementType) {
  var mark = rtRootMark();
  rtRootPush(list, storageRef);
  rtRootPushValue(value, elementType);
  var capacity = nativeLoad64(list + listCapacityOffset);
  var backing = nativeLoad64(list + listBackingOffset);
  var nextCapacity = capacity * 2;
  if (nextCapacity == 0) nextCapacity = 8;
  if (backing == 0) {
    backing = rtListBackingNew(
      nativeLoad64(list + listTypeOffset),
      nextCapacity,
    );
  } else {
    backing = rtGrowBuffer(
      backing,
      arrayDataOffset + capacity * 8,
      arrayDataOffset + nextCapacity * 8,
    );
  }
  nativeStore64(list + listCapacityOffset, nextCapacity);
  nativeStore64(list + listBackingOffset, backing);
  rtRootRestore(mark);
  return backing;
}

int rtListAdd(int list, int value, int sourceType) {
  var stored = value;
  var actualType = rtListElementType(list);
  var mark = -1;
  if (actualType != sourceType) {
    mark = rtRootMark();
    rtRootPush(list, storageRef);
    rtRootPushValue(value, sourceType);
    stored = rtValueCast(rtValueBox(value, sourceType), actualType);
  }
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var length = nativeLoad64(list + listLengthOffset);
  var capacity = nativeLoad64(list + listCapacityOffset);
  var backing = nativeLoad64(list + listBackingOffset);
  if (length == capacity) {
    backing = rtListGrow(list, stored, actualType);
  }
  nativeStore64(backing + arrayDataOffset + length * 8, stored);
  nativeStore64(backing + arrayLengthOffset, length + 1);
  nativeStore64(list + listLengthOffset, length + 1);
  if (mark >= 0) rtRootRestore(mark);
  return 0;
}

int rtListInsert(int list, int index, int value, int sourceType) {
  var stored = value;
  var actualType = rtListElementType(list);
  var mark = -1;
  if (actualType != sourceType) {
    mark = rtRootMark();
    rtRootPush(list, storageRef);
    rtRootPushValue(value, sourceType);
    stored = rtValueCast(rtValueBox(value, sourceType), actualType);
  }
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var length = nativeLoad64(list + listLengthOffset);
  if (index < 0 || index > length) return rtListRangeError();
  var backing = nativeLoad64(list + listBackingOffset);
  if (length == nativeLoad64(list + listCapacityOffset)) {
    backing = rtListGrow(list, stored, actualType);
  }
  var next = length;
  while (next > index) {
    nativeStore64(
      backing + arrayDataOffset + next * 8,
      nativeLoad64(backing + arrayDataOffset + (next - 1) * 8),
    );
    next--;
  }
  nativeStore64(backing + arrayDataOffset + index * 8, stored);
  nativeStore64(backing + arrayLengthOffset, length + 1);
  nativeStore64(list + listLengthOffset, length + 1);
  if (mark >= 0) rtRootRestore(mark);
  return 0;
}

int rtListRemoveLast(int list, int expectedType) {
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var mark = -1;
  if (rtListElementType(list) != expectedType) {
    mark = rtRootMark();
    rtRootPush(list, storageRef);
  }
  var length = nativeLoad64(list + listLengthOffset) - 1;
  var value = rtListGet(list, length, expectedType);
  var backing = nativeLoad64(list + listBackingOffset);
  nativeStore64(backing + arrayLengthOffset, length);
  nativeStore64(list + listLengthOffset, length);
  if (mark >= 0) rtRootRestore(mark);
  return value;
}

int rtListRemoveAt(int list, int index, int expectedType) {
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var mark = -1;
  if (rtListElementType(list) != expectedType) {
    mark = rtRootMark();
    rtRootPush(list, storageRef);
  }
  var value = rtListGet(list, index, expectedType);
  var length = nativeLoad64(list + listLengthOffset) - 1;
  var backing = nativeLoad64(list + listBackingOffset);
  while (index < length) {
    nativeStore64(
      backing + arrayDataOffset + index * 8,
      nativeLoad64(backing + arrayDataOffset + (index + 1) * 8),
    );
    index++;
  }
  nativeStore64(backing + arrayLengthOffset, length);
  nativeStore64(list + listLengthOffset, length);
  if (mark >= 0) rtRootRestore(mark);
  return value;
}

int rtListClear(int list) {
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var backing = nativeLoad64(list + listBackingOffset);
  if (backing != 0) nativeStore64(backing + arrayLengthOffset, 0);
  nativeStore64(list + listLengthOffset, 0);
  return 0;
}

int rtListFilled(int length, int value, int growable, int typeRef) {
  if (length < 0) return rtListRangeError();
  var mark = -1;
  if (length != 0) {
    mark = rtRootMark();
    rtRootPushValue(value, rtTypeArgument(typeRef));
  }
  var result = rtListNew(typeRef);
  if (growable == 0) {
    nativeStore64(result + objectFlagsOffset, objectListFixed);
  }
  if (length == 0) return result;
  rtRootPush(result, storageRef);
  var backing = rtListBackingNew(typeRef, length);
  var i = 0;
  while (i < length) {
    nativeStore64(backing + arrayDataOffset + i * 8, value);
    i = i + 1;
  }
  nativeStore64(backing + arrayLengthOffset, length);
  nativeStore64(result + listCapacityOffset, length);
  nativeStore64(result + listBackingOffset, backing);
  nativeStore64(result + listLengthOffset, length);
  rtRootRestore(mark);
  return result;
}

int rtListSublist(int list, int start, int end, int hasEnd) {
  var length = nativeLoad64(list + listLengthOffset);
  if (hasEnd == 0) end = length;
  if (start < 0 || end < start || end > length) return rtListRangeError();
  var count = end - start;
  var type = nativeLoad64(list + listTypeOffset);
  var mark = rtRootMark();
  rtRootPush(list, storageRef);
  var result = rtListNew(type);
  if (count > 0) {
    rtRootPush(result, storageRef);
    var backing = rtListBackingNew(type, count);
    for (var i = 0; i < count; i++)
      nativeStore64(
        backing + arrayDataOffset + i * 8,
        rtListRawGet(list, start + i),
      );
    nativeStore64(backing + arrayLengthOffset, count);
    nativeStore64(result + listCapacityOffset, count);
    nativeStore64(result + listBackingOffset, backing);
    nativeStore64(result + listLengthOffset, count);
  }
  rtRootRestore(mark);
  return result;
}

int rtListFromData(int data) {
  var type = data + nativeLoad64(data + constantListTypeOffset);
  var length = nativeLoad64(data + constantListLengthOffset);
  var result = rtListNew(type);
  if (length == 0) return rtListFreeze(result);
  var mark = rtRootMark();
  rtRootPush(result, storageRef);
  var backing = rtListBackingNew(type, length);
  nativeStore64(result + listCapacityOffset, length);
  nativeStore64(result + listBackingOffset, backing);
  var element = rtTypeArgument(type);
  var representation = nativeLoad64(element + typeValueRepOffset);
  var kind = nativeLoad64(element + typeKindOffset);
  if (kind == typeKindNullable) {
    kind = nativeLoad64(rtTypeArgument(element) + typeKindOffset);
  }
  var stride = 8;
  if (representation == storageTagged) stride = constantListTaggedEntryBytes;
  var entry = data + constantListDataOffset;
  var index = 0;
  while (index < length) {
    var value = nativeLoad64(entry);
    if (representation == storageRef) {
      if (value != 0) {
        if (kind == typeKindList || kind == typeKindClass)
          value = nativeCall0(entry + value);
        else
          value = entry + value;
      }
    } else if (representation == storageTagged) {
      var actual = value;
      value = nativeLoad64(entry + 8);
      if (actual == typeKindInt)
        value = rtBoxInt(value);
      else if (actual == typeKindDouble)
        value = rtBoxDouble(value);
      else if (actual == typeKindBool)
        value = rtBoxBool(value);
      else if (actual == typeKindNull)
        value = 0;
      else if (actual == typeKindList || actual == typeKindClass)
        value = nativeCall0(entry + value);
      else
        value = entry + value;
    }
    nativeStore64(backing + arrayDataOffset + index * 8, value);
    nativeStore64(backing + arrayLengthOffset, index + 1);
    nativeStore64(result + listLengthOffset, index + 1);
    entry = entry + stride;
    index = index + 1;
  }
  rtListFreeze(result);
  rtRootRestore(mark);
  return result;
}

int rtStringFromCodes(int codes) {
  var length = rtListLength(codes);
  var units = length;
  var i = 0;
  while (i < length) {
    var code = rtListRawGet(codes, i);
    if (code < 0 || code > 1114111) {
      var message = rtCStringAcquire(
        0x69203a6374726164,
        0x632064696c61766e,
        0x7265746361726168,
        0xa65646f6320,
      );
      rtWriteAll(2, message, 30);
      rtHostExit(70);
    }
    if (code > 65535) units = units + 1;
    i = i + 1;
  }
  var result = rtStringNew(units);
  i = 0;
  var count = 0;
  while (i < length) {
    var c = rtListRawGet(codes, i);
    if (c > 65535) {
      var scalar = c - 65536;
      nativeStore16(
        result + stringDataOffset + count * 2,
        55296 + (scalar >> 10),
      );
      nativeStore16(
        result + stringDataOffset + 2 + count * 2,
        56320 + (scalar & 1023),
      );
      count = count + 2;
    } else {
      nativeStore16(result + stringDataOffset + count * 2, c);
      count = count + 1;
    }
    i = i + 1;
  }
  nativeStore64(result + stringLengthOffset, count);
  return result;
}

int rtStringDecodeUtf8(int bytes, int length) {
  var result = rtStringNew(length);
  var i = 0;
  var count = 0;
  while (i < length) {
    var c = nativeLoad8(bytes + i);
    i = i + 1;
    if (c >= 192 && c < 224) {
      c = ((c & 31) << 6) | (nativeLoad8(bytes + i) & 63);
      i = i + 1;
    } else if (c >= 224 && c < 240) {
      c =
          ((c & 15) << 12) |
          ((nativeLoad8(bytes + i) & 63) << 6) |
          (nativeLoad8(bytes + i + 1) & 63);
      i = i + 2;
    } else if (c >= 240) {
      c =
          ((c & 7) << 18) |
          ((nativeLoad8(bytes + i) & 63) << 12) |
          ((nativeLoad8(bytes + i + 1) & 63) << 6) |
          (nativeLoad8(bytes + i + 2) & 63);
      i = i + 3;
    }
    if (c > 65535) {
      var scalar = c - 65536;
      nativeStore16(
        result + stringDataOffset + count * 2,
        55296 + (scalar >> 10),
      );
      nativeStore16(
        result + stringDataOffset + 2 + count * 2,
        56320 + (scalar & 1023),
      );
      count = count + 2;
    } else {
      nativeStore16(result + stringDataOffset + count * 2, c);
      count = count + 1;
    }
  }
  nativeStore64(result + stringLengthOffset, count);
  return result;
}

int rtStringFromCString(int bytes) {
  var length = 0;
  while (nativeLoad8(bytes + length) != 0) length = length + 1;
  return rtStringDecodeUtf8(bytes, length);
}

int rtStringFromWords(int a, int b, int c, int d) {
  var bytes = rtCStringAcquire(a, b, c, d);
  var result = rtStringFromCString(bytes);
  rtCStringRelease();
  return result;
}

int rtUtf8Bytes = 0;
int rtUtf8Capacity = 0;
int rtUtf8Busy = 0;

@pragma('dartc:no-gc')
int rtUtf8Acquire(int bytes) {
  if (rtUtf8Busy != 0) {
    rtHostExit(70);
    return 0;
  }
  if (bytes > rtUtf8Capacity) {
    var capacity = (bytes + 16383) & -16384;
    if (capacity < rtUtf8Capacity * 2) capacity = rtUtf8Capacity * 2;
    var previous = rtUtf8Bytes;
    var oldCapacity = rtUtf8Capacity;
    rtUtf8Bytes = rtMap(capacity);
    rtUtf8Capacity = capacity;
    rtUnmap(previous, oldCapacity);
  }
  rtUtf8Busy = 1;
  return rtUtf8Bytes;
}

@pragma('dartc:no-gc')
int rtUtf8Release() {
  if (rtUtf8Busy == 0) {
    rtHostExit(70);
    return 0;
  }
  rtUtf8Busy = 0;
  return 0;
}

@pragma('dartc:no-gc')
int rtStringEncodeUtf8(int value) {
  var length = nativeLoad64(value + stringLengthOffset);
  var result = rtUtf8Acquire(9 + length * 4);
  var i = 0;
  var count = 0;
  while (i < length) {
    var c = nativeLoad16(value + stringDataOffset + i * 2);
    i = i + 1;
    if (c >= 55296 && c <= 56319) {
      var low = 0;
      if (i < length) low = nativeLoad16(value + stringDataOffset + i * 2);
      if (low >= 56320 && low <= 57343) {
        c = 65536 + ((c - 55296) << 10) + low - 56320;
        i = i + 1;
      } else {
        c = 65533;
      }
    } else if (c >= 56320 && c <= 57343) {
      c = 65533;
    }
    if (c < 128) {
      nativeStore8(result + 8 + count, c);
      count = count + 1;
    } else if (c < 2048) {
      nativeStore8(result + 8 + count, 192 | (c >> 6));
      nativeStore8(result + 9 + count, 128 | (c & 63));
      count = count + 2;
    } else if (c < 65536) {
      nativeStore8(result + 8 + count, 224 | (c >> 12));
      nativeStore8(result + 9 + count, 128 | ((c >> 6) & 63));
      nativeStore8(result + 10 + count, 128 | (c & 63));
      count = count + 3;
    } else {
      nativeStore8(result + 8 + count, 240 | (c >> 18));
      nativeStore8(result + 9 + count, 128 | ((c >> 12) & 63));
      nativeStore8(result + 10 + count, 128 | ((c >> 6) & 63));
      nativeStore8(result + 11 + count, 128 | (c & 63));
      count = count + 4;
    }
  }
  nativeStore64(result, count);
  nativeStore8(result + 8 + count, 0);
  return result;
}

@pragma('dartc:no-gc')
int rtPrintString(int value) {
  var encoded = rtStringEncodeUtf8(value);
  var length = nativeLoad64(encoded);
  nativeStore8(encoded + 8 + length, 10);
  rtWriteAll(1, encoded + 8, length + 1);
  rtUtf8Release();
  return 0;
}

int rtPrintInt(int value) {
  return rtPrintString(rtIntToString(value));
}

@pragma('dartc:no-gc')
int rtPrintBool(int value) {
  var p = 0;
  var length = 0;
  if (value == 0) {
    p = rtCStringAcquire(0x0a65736c6166, 0, 0, 0);
    length = 6;
  } else {
    p = rtCStringAcquire(0x0a65757274, 0, 0, 0);
    length = 5;
  }
  rtWriteAll(1, p, length);
  rtCStringRelease();
  return 0;
}

int rtHostRead(int path) {
  return rtHostReadFile(path, 0);
}

int rtHostReadIfExists(int path) {
  return rtHostReadFile(path, 1);
}

int rtHostReadFile(int path, int optional) {
  var encoded = rtStringEncodeUtf8(path);
  var fd = rtSyscall(5, encoded + 8, 0, 0, 0, 0, 0);
  rtUtf8Release();
  if (fd < 0) {
    if (optional != 0 && (fd == -2 || fd == -20)) return 0;
    return rtIoError(path);
  }
  var capacity = 65536;
  var bytes = rtMap(capacity);
  var length = 0;
  var done = 0;
  while (done == 0) {
    if (length == capacity) {
      var replacement = rtMap(capacity * 2);
      var offset = 0;
      while (offset < capacity) {
        nativeStore64(replacement + offset, nativeLoad64(bytes + offset));
        offset = offset + 8;
      }
      rtUnmap(bytes, capacity);
      bytes = replacement;
      capacity = capacity * 2;
    }
    var count = rtSyscall(3, fd, bytes + length, capacity - length, 0, 0, 0);
    if (count < 0) {
      return rtIoError(path);
    }
    if (count == 0) done = 1;
    length = length + count;
  }
  rtSyscall(6, fd, 0, 0, 0, 0, 0);
  var result = rtStringDecodeUtf8(bytes, length);
  rtUnmap(bytes, capacity);
  return result;
}

int rtHostCurrentDirectory() {
  var capacity = 1024;
  var bytes = rtMap(capacity);
  if (nativeTarget() == 0) {
    // Darwin has no getcwd syscall; F_GETPATH writes a MAXPATHLEN buffer.
    nativeStore64(bytes, 46);
    var fd = rtSyscall(5, bytes, 0, 0, 0, 0, 0);
    if (fd < 0) return rtIoError();
    var status = rtSyscall(92, fd, 50, bytes, 0, 0, 0);
    rtSyscall(6, fd, 0, 0, 0, 0, 0);
    if (status < 0) return rtIoError();
  } else {
    var status = nativeSyscall(17, bytes, capacity, 0, 0, 0, 0);
    while (status == -34) {
      rtUnmap(bytes, capacity);
      capacity = capacity * 2;
      bytes = rtMap(capacity);
      status = nativeSyscall(17, bytes, capacity, 0, 0, 0, 0);
    }
    if (status < 0) return rtIoError();
  }
  var result = rtStringFromCString(bytes);
  rtUnmap(bytes, capacity);
  return result;
}

int rtPackBytes(int source, int destination, int count) {
  var i = 0;
  while (i < count) {
    nativeStore8(destination + i, nativeLoad64(source + i * 8));
    i = i + 1;
  }
  return 0;
}

@pragma('dartc:no-gc')
int rtHostWrite(int path, int bytes) {
  var encoded = rtStringEncodeUtf8(path);
  var fd = rtSyscall(5, encoded + 8, 1537, 420, 0, 0, 0);
  rtUtf8Release();
  if (fd < 0) rtIoError();
  var length = rtListLength(bytes);
  var capacity = 65536;
  if (length < capacity) capacity = length;
  var data = rtMap(capacity);
  var source = nativeLoad64(bytes + listBackingOffset) + arrayDataOffset;
  var offset = 0;
  while (offset < length) {
    var count = length - offset;
    if (count > capacity) count = capacity;
    rtPackBytes(source, data, count);
    rtWriteAll(fd, data, count);
    source = source + count * 8;
    offset = offset + count;
  }
  rtUnmap(data, capacity);
  rtSyscall(6, fd, 0, 0, 0, 0, 0);
  return 0;
}

int rtArguments(int argc, int argv, int typeRef) {
  var result = rtListNew(typeRef);
  if (argc <= 1) return result;
  var mark = rtRootMark();
  rtRootPush(result, storageRef);
  var i = 1;
  while (i < argc) {
    rtListAdd(
      result,
      rtStringFromCString(nativeLoad64(argv + i * 8)),
      rtTypeArgument(typeRef),
    );
    i = i + 1;
  }
  rtRootRestore(mark);
  return result;
}

int _rtExecutablePath() {
  var capacity = 4096;
  var bytes = rtMap(capacity);
  var result = 0;
  if (nativeTarget() == 0) {
    // Darwin proc_info(PIDINFO, getpid(), PIDPATHINFO, 0, buffer, size).
    var pid = nativeSyscall(20, 0, 0, 0, 0, 0, 0);
    var status = nativeSyscall(336, 2, pid, 11, 0, bytes, capacity);
    if (status < 0) return rtIoError();
    result = rtStringFromCString(bytes);
  } else {
    var path = rtCStringAcquire(0x65732f636f72702f, 0x6578652f666c, 0, 0);
    var length = nativeSyscall(78, -100, path, bytes, capacity, 0, 0);
    // readlinkat does not terminate the result and truncates to capacity.
    while (length == capacity) {
      rtUnmap(bytes, capacity);
      capacity = capacity * 2;
      bytes = rtMap(capacity);
      length = nativeSyscall(78, -100, path, bytes, capacity, 0, 0);
    }
    rtCStringRelease();
    if (length < 0) return rtIoError();
    result = rtStringDecodeUtf8(bytes, length);
  }
  rtUnmap(bytes, capacity);
  return result;
}

int rtHostStdPath() {
  var executable = _rtExecutablePath();
  var mark = rtRootMark();
  rtRootPush(executable, storageRef);
  var slash = rtStringFromWords(47, 0, 0, 0);
  var end = rtStringLastIndexOf(executable, slash, rtStringLength(executable));
  if (end < 0) return rtIoError();
  var directory = rtStringSubstring(executable, 0, end);
  rtRootPush(directory, storageRef);
  var suffix = rtStringFromWords(
    0x2f62696c2f2e2e2f,
    0x746e75722f637273,
    0x747261642e656d69,
    0,
  );
  var result = rtStringConcat(directory, suffix);
  rtRootRestore(mark);
  return result;
}

@pragma('dartc:no-gc')
int rtHostFinish(int path, int outputTarget) {
  var encoded = rtStringEncodeUtf8(path);
  var changed = rtSyscall(15, encoded + 8, 493, 0, 0, 0, 0);
  rtUtf8Release();
  if (changed < 0) rtIoError();
  rtHostExit(0);
  return 0;
}

@pragma('dartc:no-gc')
int rtObjectDescriptor(int object) {
  var descriptor = nativeLoad64(object);
  if ((nativeLoad64(object + objectFlagsOffset) & objectStaticRelative) != 0) {
    descriptor = object + descriptor;
  }
  return descriptor;
}

@pragma('dartc:no-gc')
int rtFunctionType(int value) {
  var type = nativeLoad64(value + functionTypeOffset);
  if ((nativeLoad64(value + objectFlagsOffset) & objectStaticRelative) != 0) {
    type = value + type;
  }
  return type;
}

@pragma('dartc:no-gc')
int rtFunctionEntry(int value) {
  var entry = nativeLoad64(value + functionEntryOffset);
  if ((nativeLoad64(value + objectFlagsOffset) & objectStaticRelative) != 0) {
    entry = value + entry;
  }
  return entry;
}

int rtObjectNew(int descriptor) {
  var size = nativeLoad64(descriptor + descriptorSizeOffset);
  var object = rtAlloc(size);
  nativeStore64(object, descriptor);
  nativeStore64(object + objectFlagsOffset, 0);
  var offset = objectHeaderBytes;
  while (offset < size) {
    nativeStore64(object + offset, 0);
    offset = offset + 8;
  }
  return object;
}

int rtObjectFromData(int data) {
  var type = data + nativeLoad64(data + constantObjectTypeOffset);
  var descriptor = type + nativeLoad64(type + typeClassOffset);
  var count = nativeLoad64(data + constantObjectLengthOffset);
  var result = rtObjectNew(descriptor);
  var mark = rtRootMark();
  rtRootPush(result, storageRef);
  var bitmap = nativeLoad64(descriptor + descriptorTaggedBitmapOffset);
  if (bitmap != 0) bitmap = descriptor + bitmap;
  var entry = data + constantObjectDataOffset;
  var index = 0;
  while (index < count) {
    var kind = nativeLoad64(entry);
    var value = nativeLoad64(entry + 8);
    if (kind == typeKindInt || kind == typeKindDouble || kind == typeKindBool) {
      if (bitmap != 0 &&
          (nativeLoad64(bitmap + (index ~/ 64) * 8) & (1 << (index & 63))) !=
              0) {
        if (kind == typeKindInt)
          value = rtBoxInt(value);
        else if (kind == typeKindDouble)
          value = rtBoxDouble(value);
        else
          value = rtBoxBool(value);
      }
    } else if (kind == typeKindNull) {
      value = 0;
    } else if (kind == typeKindString || kind == typeKindFunction) {
      value = entry + value;
    } else if (kind == typeKindList || kind == typeKindClass) {
      value = nativeCall0(entry + value);
    }
    nativeStore64(result + objectHeaderBytes + index * 8, value);
    entry = entry + constantObjectEntryBytes;
    index = index + 1;
  }
  rtRootRestore(mark);
  return result;
}

int rtObjectGet(int object, int index) {
  return nativeLoad64(object + objectHeaderBytes + index * 8);
}

int rtObjectSet(int object, int index, int value) {
  nativeStore64(object + objectHeaderBytes + index * 8, value);
  return value;
}

int rtValueTypeError() {
  var message = rtCStringAcquire(
    0x72203a6374726164,
    0x7420656d69746e75,
    0x6f72726520657079,
    0xa72,
  );
  rtWriteAll(2, message, 26);
  rtHostExit(70);
  return 0;
}

@pragma('dartc:no-gc')
int rtTypeArgument(int type) {
  return type + nativeLoad64(type + typeArgumentOffset);
}

int rtInstantiateType(int type, int arguments) {
  if ((nativeLoad64(type + objectFlagsOffset) & objectTypeTemplate) == 0)
    return type;
  var kind = nativeLoad64(type + typeKindOffset);
  if (kind == typeKindParameter)
    return rtListRawGet(arguments, nativeLoad64(type + typeArgumentOffset));
  var mark = rtRootMark();
  rtRootPush(type, storageRef);
  rtRootPush(arguments, storageRef);
  var result = 0;
  if (kind == typeKindList || kind == typeKindNullable) {
    var child = rtInstantiateType(rtTypeArgument(type), arguments);
    rtRootPush(child, storageRef);
    result = rtAlloc(typeRefBytes);
    nativeStore64(result, rtObjectDescriptor(type));
    nativeStore64(result + objectFlagsOffset, 0);
    nativeStore64(result + typeKindOffset, kind);
    nativeStore64(result + typeArgumentOffset, child - result);
    nativeStore64(result + typeClassOffset, 0);
    var representation = storageRef;
    if (kind == typeKindNullable &&
        nativeLoad64(child + typeValueRepOffset) != storageRef)
      representation = storageTagged;
    nativeStore64(result + typeValueRepOffset, representation);
  } else {
    var source = rtTypeArgument(type);
    var count = nativeLoad64(source + functionSignatureCountOffset);
    result = rtAlloc(
      typeRefBytes + functionSignatureParametersOffset + count * 8,
    );
    nativeStore64(result, rtObjectDescriptor(type));
    nativeStore64(result + objectFlagsOffset, 0);
    nativeStore64(result + typeKindOffset, typeKindFunction);
    nativeStore64(result + typeArgumentOffset, typeRefBytes);
    nativeStore64(result + typeClassOffset, 0);
    nativeStore64(result + typeValueRepOffset, storageRef);
    var signature = result + typeRefBytes;
    nativeStore64(
      signature + functionSignatureRequiredOffset,
      nativeLoad64(source + functionSignatureRequiredOffset),
    );
    nativeStore64(signature + functionSignatureCountOffset, count);
    nativeStore64(
      signature + functionSignatureResultOffset,
      source + nativeLoad64(source + functionSignatureResultOffset) - signature,
    );
    var i = 0;
    while (i < count) {
      var input = source + functionSignatureParametersOffset + i * 8;
      var output = signature + functionSignatureParametersOffset + i * 8;
      nativeStore64(output, input + nativeLoad64(input) - output);
      i++;
    }
    // Publish a fully initialized graph before recursively allocating children.
    rtRootPush(result, storageRef);
    var resultType = rtInstantiateType(
      source + nativeLoad64(source + functionSignatureResultOffset),
      arguments,
    );
    nativeStore64(
      signature + functionSignatureResultOffset,
      resultType - signature,
    );
    i = 0;
    while (i < count) {
      var input = source + functionSignatureParametersOffset + i * 8;
      var output = signature + functionSignatureParametersOffset + i * 8;
      var parameter = rtInstantiateType(input + nativeLoad64(input), arguments);
      nativeStore64(output, parameter - output);
      i++;
    }
  }
  rtRootRestore(mark);
  return result;
}

int rtValueCheck(int value, int expected) {
  if (rtValueMatches(value, expected) == 0) return rtValueTypeError();
  return value;
}

int rtListFilledChecked(int length, int value, int growable, int type) {
  var mark = rtRootMark();
  rtRootPush(type, storageRef);
  rtRootPush(value, storageTagged);
  var stored = rtValueCast(value, rtTypeArgument(type));
  var result = rtListFilled(length, stored, growable, type);
  rtRootRestore(mark);
  return result;
}

int rtTypeSubtype(int actual, int expected) {
  if (actual == expected) return 1;
  var target = nativeLoad64(expected + typeKindOffset);
  if (target == typeKindDynamic || target == typeKindVoid) return 1;
  var source = nativeLoad64(actual + typeKindOffset);
  if (source == typeKindNever) return 1;
  if (target == typeKindNullable) {
    var child = rtTypeArgument(expected);
    if (nativeLoad64(child + typeKindOffset) == typeKindObject) return 1;
    if (source == typeKindNull) return 1;
    if (source == typeKindNullable) actual = rtTypeArgument(actual);
    return rtTypeSubtype(actual, child);
  }
  if (source == typeKindNullable) return 0;
  if (source == typeKindNull) {
    if (target == typeKindNull) return 1;
    return 0;
  }
  if (target == typeKindObject) {
    if (source == typeKindDynamic || source == typeKindVoid) return 0;
    return 1;
  }
  if ((source == typeKindInt || source == typeKindDouble) &&
      target == typeKindNum)
    return 1;
  if (source != target) return 0;
  if (source == typeKindList) {
    return rtTypeSubtype(rtTypeArgument(actual), rtTypeArgument(expected));
  }
  if (source == typeKindClass) {
    var left = actual + nativeLoad64(actual + typeClassOffset);
    var right = expected + nativeLoad64(expected + typeClassOffset);
    if (left != right) return 0;
  }
  if (source == typeKindFunction) {
    var targetSignature = nativeLoad64(expected + typeArgumentOffset);
    if (targetSignature == 0) return 1;
    var sourceSignature = nativeLoad64(actual + typeArgumentOffset);
    if (sourceSignature == 0) return 0;
    sourceSignature = actual + sourceSignature;
    targetSignature = expected + targetSignature;
    var required = nativeLoad64(
      sourceSignature + functionSignatureRequiredOffset,
    );
    var count = nativeLoad64(targetSignature + functionSignatureCountOffset);
    if (required >
            nativeLoad64(targetSignature + functionSignatureRequiredOffset) ||
        nativeLoad64(sourceSignature + functionSignatureCountOffset) < count) {
      return 0;
    }
    var result =
        sourceSignature +
        nativeLoad64(sourceSignature + functionSignatureResultOffset);
    var expectedResult =
        targetSignature +
        nativeLoad64(targetSignature + functionSignatureResultOffset);
    if (rtTypeSubtype(result, expectedResult) == 0) return 0;
    var i = 0;
    while (i < count) {
      var sourceParameter =
          sourceSignature + functionSignatureParametersOffset + i * 8;
      var targetParameter =
          targetSignature + functionSignatureParametersOffset + i * 8;
      if (rtTypeSubtype(
            targetParameter + nativeLoad64(targetParameter),
            sourceParameter + nativeLoad64(sourceParameter),
          ) ==
          0) {
        return 0;
      }
      i++;
    }
  }
  return 1;
}

int rtBoxInt(int value) {
  if (value >= -4611686018427387904 && value <= 4611686018427387903) {
    return (value << 1) | 1;
  }
  var metadata = nativeMetadataAddress(metadataValues);
  var descriptor =
      metadata + nativeLoad64(metadata + metadataIntBoxDescriptorOffset);
  var result = rtObjectNew(descriptor);
  nativeStore64(result + objectHeaderBytes, value);
  return result;
}

@pragma('dartc:no-gc')
int rtBoxBool(int value) {
  if (value == 0) return valueFalse;
  return valueTrue;
}

int rtValueKind(int value) {
  if (value == 0) return typeKindNull;
  if (value == valueFalse || value == valueTrue) return typeKindBool;
  if ((value & 1) != 0) return typeKindInt;
  var kind = nativeLoad64(rtObjectDescriptor(value) + descriptorKindOffset);
  if (kind == descriptorIntBox) return typeKindInt;
  if (kind == descriptorDoubleBox) return typeKindDouble;
  if (kind == descriptorString) return typeKindString;
  if (kind == descriptorList) return typeKindList;
  if (kind == descriptorFunction) return typeKindFunction;
  return typeKindClass;
}

int rtValueInt(int value) {
  if ((value & 1) != 0) return value >> 1;
  if (value > valueTrue) {
    var kind = nativeLoad64(rtObjectDescriptor(value) + descriptorKindOffset);
    if (kind == descriptorIntBox)
      return nativeLoad64(value + objectHeaderBytes);
  }
  return rtValueTypeError();
}

int rtValueBool(int value) {
  if (value == valueFalse) return 0;
  if (value == valueTrue) return 1;
  return rtValueTypeError();
}

int rtValueBox(int value, int type) {
  var representation = nativeLoad64(type + typeValueRepOffset);
  if (representation == storageTagged || representation == storageRef) {
    return value;
  }
  var kind = nativeLoad64(type + typeKindOffset);
  if (kind == typeKindInt) return rtBoxInt(value);
  if (kind == typeKindDouble) return rtBoxDouble(value);
  if (kind == typeKindBool) return rtBoxBool(value);
  if (kind == typeKindNull) return 0;
  return rtValueTypeError();
}

int rtValueMatches(int value, int expected) {
  var kind = nativeLoad64(expected + typeKindOffset);
  if (kind == typeKindNever) return 0;
  if (kind == typeKindDynamic || kind == typeKindVoid) return 1;
  if (kind == typeKindNullable) {
    if (value == 0) return 1;
    return rtValueMatches(value, rtTypeArgument(expected));
  }
  if (kind == typeKindNull) {
    if (value == 0) return 1;
    return 0;
  }
  if (value == 0) return 0;
  if (kind == typeKindObject) return 1;
  var actual = rtValueKind(value);
  if (kind == typeKindNum &&
      (actual == typeKindInt || actual == typeKindDouble))
    return 1;
  if (actual != kind) return 0;
  if (kind == typeKindList) {
    return rtTypeSubtype(nativeLoad64(value + listTypeOffset), expected);
  }
  if (kind == typeKindFunction) {
    return rtTypeSubtype(rtFunctionType(value), expected);
  }
  if (kind == typeKindClass) {
    var descriptor = expected + nativeLoad64(expected + typeClassOffset);
    if (rtObjectDescriptor(value) != descriptor) return 0;
  }
  return 1;
}

int rtValueCast(int value, int expected) {
  if (rtValueMatches(value, expected) == 0) return rtValueTypeError();
  var representation = nativeLoad64(expected + typeValueRepOffset);
  if (representation == storageTagged) return value;
  if (value == 0) return 0;
  var kind = nativeLoad64(expected + typeKindOffset);
  if (kind == typeKindNullable) {
    kind = nativeLoad64(rtTypeArgument(expected) + typeKindOffset);
  }
  if (kind == typeKindInt) return rtValueInt(value);
  if (kind == typeKindDouble) return rtValueDouble(value);
  if (kind == typeKindBool) return rtValueBool(value);
  if (kind == typeKindVoid) return 0;
  return value;
}

int rtBoxDouble(int bits) {
  final metadata = nativeMetadataAddress(metadataValues);
  final descriptor =
      metadata + nativeLoad64(metadata + metadataDoubleBoxDescriptorOffset);
  final result = rtObjectNew(descriptor);
  nativeStore64(result + objectHeaderBytes, bits);
  return result;
}

int rtValueDouble(int value) {
  if (rtValueKind(value) != typeKindDouble) return rtValueTypeError();
  return nativeLoad64(value + objectHeaderBytes);
}

int rtNumberDouble(int value) {
  if (rtValueKind(value) == typeKindInt)
    return hostFloat64FromInt(rtValueInt(value));
  return rtValueDouble(value);
}

int rtDoubleToString(int bits) => nativeValueBits(binary64Format(bits));

int rtDoubleToInt(int bits) {
  if ((bits & 0x7fffffffffffffff) >= binary64Infinity)
    return rtValueTypeError();
  return hostFloat64ToInt(bits);
}

int rtNumberToInt(int value) {
  if (rtValueKind(value) == typeKindInt) return rtValueInt(value);
  return rtDoubleToInt(rtValueDouble(value));
}

int rtDoubleParse(int text) {
  final bits = binary64Parse(nativeValueFromBits(text) as String);
  if (bits == null) return rtValueTypeError();
  return bits;
}

int rtDoubleTryParse(int text) {
  final bits = binary64Parse(nativeValueFromBits(text) as String);
  return bits == null ? 0 : rtBoxDouble(bits);
}

int rtDoubleModulo(int left, int right) => binary64Modulo(left, right);
int rtDoubleTruncDiv(int left, int right) =>
    rtDoubleToInt(hostFloat64Div(left, right));

int rtValueNeg(int value) {
  if (rtValueKind(value) == typeKindInt) return rtBoxInt(-rtValueInt(value));
  return rtBoxDouble(rtValueDouble(value) ^ binary64Sign);
}

bool rtNumberIsIntPair(int left, int right) =>
    rtValueKind(left) == typeKindInt && rtValueKind(right) == typeKindInt;

int rtValueAdd(int left, int right) {
  if (rtValueKind(left) == typeKindString &&
      rtValueKind(right) == typeKindString)
    return rtStringConcat(left, right);
  if (rtNumberIsIntPair(left, right))
    return rtBoxInt(rtValueInt(left) + rtValueInt(right));
  return rtBoxDouble(
    hostFloat64Add(rtNumberDouble(left), rtNumberDouble(right)),
  );
}

int rtValueSub(int left, int right) {
  if (rtNumberIsIntPair(left, right))
    return rtBoxInt(rtValueInt(left) - rtValueInt(right));
  return rtBoxDouble(
    hostFloat64Sub(rtNumberDouble(left), rtNumberDouble(right)),
  );
}

int rtValueMul(int left, int right) {
  if (rtNumberIsIntPair(left, right))
    return rtBoxInt(rtValueInt(left) * rtValueInt(right));
  return rtBoxDouble(
    hostFloat64Mul(rtNumberDouble(left), rtNumberDouble(right)),
  );
}

int rtValueFloatDiv(int left, int right) =>
    rtBoxDouble(hostFloat64Div(rtNumberDouble(left), rtNumberDouble(right)));

int rtValueDiv(int left, int right) {
  if (!rtNumberIsIntPair(left, right))
    return rtBoxInt(
      rtDoubleTruncDiv(rtNumberDouble(left), rtNumberDouble(right)),
    );
  final divisor = rtValueInt(right);
  if (divisor == 0) return rtValueTypeError();
  return rtBoxInt(rtValueInt(left) ~/ divisor);
}

int rtValueMod(int left, int right) {
  if (!rtNumberIsIntPair(left, right))
    return rtBoxDouble(
      binary64Modulo(rtNumberDouble(left), rtNumberDouble(right)),
    );
  final divisor = rtValueInt(right);
  if (divisor == 0) return rtValueTypeError();
  return rtBoxInt(rtValueInt(left) % divisor);
}

int rtValueRemainder(int left, int right) {
  if (!rtNumberIsIntPair(left, right))
    return rtBoxDouble(
      binary64Remainder(rtNumberDouble(left), rtNumberDouble(right)),
    );
  final a = rtValueInt(left);
  final b = rtValueInt(right);
  if (b == 0) return rtValueTypeError();
  final remainder = a % b;
  return rtBoxInt(
    a < 0 && remainder != 0 ? remainder - (b < 0 ? -b : b) : remainder,
  );
}

int rtNumberProperty(int value, int property) {
  final integer = rtValueKind(value) == typeKindInt;
  final bits = integer ? 0 : rtValueDouble(value);
  final magnitude = bits & 0x7fffffffffffffff;
  final result = switch (property) {
    0 => !integer && magnitude > binary64Infinity,
    1 => integer || magnitude < binary64Infinity,
    2 => !integer && magnitude == binary64Infinity,
    _ =>
      integer
          ? rtValueInt(value) < 0
          : bits < 0 && magnitude <= binary64Infinity,
  };
  return result ? 1 : 0;
}

int rtValueAnd(int left, int right) {
  if (left == valueFalse || left == valueTrue) {
    return rtBoxBool(rtValueBool(left) & rtValueBool(right));
  }
  return rtBoxInt(rtValueInt(left) & rtValueInt(right));
}

int rtValueOr(int left, int right) {
  if (left == valueFalse || left == valueTrue) {
    return rtBoxBool(rtValueBool(left) | rtValueBool(right));
  }
  return rtBoxInt(rtValueInt(left) | rtValueInt(right));
}

int rtValueXor(int left, int right) {
  if (left == valueFalse || left == valueTrue) {
    return rtBoxBool(rtValueBool(left) ^ rtValueBool(right));
  }
  return rtBoxInt(rtValueInt(left) ^ rtValueInt(right));
}

int rtValueShl(int left, int right) {
  var value = rtValueInt(left);
  var count = rtValueInt(right);
  if (count < 0) return rtValueTypeError();
  if (count >= 64) return rtBoxInt(0);
  return rtBoxInt(value << count);
}

int rtValueShr(int left, int right) {
  var value = rtValueInt(left);
  var count = rtValueInt(right);
  if (count < 0) return rtValueTypeError();
  if (count >= 64) {
    if (value < 0) return rtBoxInt(-1);
    return rtBoxInt(0);
  }
  return rtBoxInt(value >> count);
}

int rtValueUshr(int left, int right) {
  var value = rtValueInt(left);
  var count = rtValueInt(right);
  if (count < 0) return rtValueTypeError();
  if (count >= 64) return rtBoxInt(0);
  return rtBoxInt(value >>> count);
}

int rtValueIdentical(int left, int right) {
  if (left == right) return 1;
  final a = rtValueKind(left);
  final b = rtValueKind(right);
  if (a == typeKindDouble && b == typeKindDouble) {
    final x = rtValueDouble(left);
    final y = rtValueDouble(right);
    return x == y || binary64IsNaN(x) && binary64IsNaN(y) ? 1 : 0;
  }
  if (a == typeKindInt &&
      b == typeKindInt &&
      rtValueInt(left) == rtValueInt(right))
    return 1;
  return 0;
}

int rtValueEq(int left, int right) {
  final a = rtValueKind(left);
  final b = rtValueKind(right);
  if ((a == typeKindDouble || a == typeKindInt) &&
      (b == typeKindDouble || b == typeKindInt)) {
    if (a == typeKindInt && b == typeKindInt)
      return rtValueInt(left) == rtValueInt(right) ? 1 : 0;
    return hostFloat64Compare(rtNumberDouble(left), rtNumberDouble(right)) == 0
        ? 1
        : 0;
  }
  if (left == right) return 1;
  if (a != b) return 0;
  if (a == typeKindString) return rtStringEqual(left, right);
  if (a == typeKindFunction) {
    final descriptor = rtObjectDescriptor(left);
    if (nativeLoad64(descriptor) == boundMethodClassId &&
        descriptor == rtObjectDescriptor(right) &&
        nativeLoad64(left + functionInstanceBytes) ==
            nativeLoad64(right + functionInstanceBytes))
      return 1;
  }
  return 0;
}

int rtNumberCompare(int left, int right) {
  if (rtNumberIsIntPair(left, right)) {
    final a = rtValueInt(left);
    final b = rtValueInt(right);
    return a < b
        ? -1
        : a > b
        ? 1
        : 0;
  }
  return hostFloat64Compare(rtNumberDouble(left), rtNumberDouble(right));
}

int rtNumberCompareTo(int left, int right) {
  final a = rtValueKind(left);
  final b = rtValueKind(right);
  if (a == typeKindInt && b == typeKindInt) return rtNumberCompare(left, right);
  if (a == typeKindInt) {
    final bits = rtValueDouble(right);
    if (binary64IsNaN(bits)) return -1;
    if (bits == binary64Sign && rtValueInt(left) == 0) return 1;
    return -binary64CompareInt(bits, rtValueInt(left));
  }
  final bits = rtValueDouble(left);
  if (b == typeKindInt) {
    if (binary64IsNaN(bits)) return 1;
    if (bits == binary64Sign && rtValueInt(right) == 0) return -1;
    return binary64CompareInt(bits, rtValueInt(right));
  }
  final other = rtValueDouble(right);
  if (binary64IsNaN(bits)) return binary64IsNaN(other) ? 0 : 1;
  if (binary64IsNaN(other)) return -1;
  final result = hostFloat64Compare(bits, other);
  if (result == 0 && bits != other) return bits < 0 ? -1 : 1;
  return result;
}

int rtValueLt(int left, int right) =>
    rtNumberCompare(left, right) == -1 ? 1 : 0;
int rtValueLe(int left, int right) => rtNumberCompare(left, right) <= 0 ? 1 : 0;
int rtValueGt(int left, int right) => rtNumberCompare(left, right) == 1 ? 1 : 0;
int rtValueGe(int left, int right) {
  final result = rtNumberCompare(left, right);
  return result == 0 || result == 1 ? 1 : 0;
}

int rtListModificationError() {
  var message = rtCStringAcquire(
    0x63203a6374726164,
    0x6e65727275636e6f,
    0x696669646f6d2074,
    0xa6e6f69746163,
  );
  rtWriteAll(2, message, 31);
  rtHostExit(70);
  return 0;
}

int rtValueActiveRoot = 0;

int rtStringFromParts(int parts) {
  var length = 0;
  var count = rtListLength(parts);
  var i = 0;
  while (i < count) {
    length = length + rtStringLength(rtListRawGet(parts, i));
    i = i + 1;
  }
  var result = rtStringNew(length);
  var position = 0;
  i = 0;
  while (i < count) {
    var part = rtListRawGet(parts, i);
    var units = rtStringLength(part);
    var unit = 0;
    while (unit < units) {
      nativeStore16(
        result + stringDataOffset + position * 2,
        nativeLoad16(part + stringDataOffset + unit * 2),
      );
      position = position + 1;
      unit = unit + 1;
    }
    i = i + 1;
  }
  return result;
}

int rtValueFormat(int value, int handleType) {
  var kind = rtValueKind(value);
  if (kind != typeKindClass && kind != typeKindList) {
    return rtValueFormatCore(value, handleType, kind);
  }
  var mark = rtRootMark();
  rtRootPush(value, storageTagged);
  var result = rtValueFormatCore(value, handleType, kind);
  rtRootRestore(mark);
  return result;
}

int rtValueFormatCore(int value, int handleType, int kind) {
  if (value == 0) {
    return rtStringFromWords(0x6c6c756e, 0, 0, 0);
  }
  if (value == valueFalse) {
    return rtStringFromWords(0x65736c6166, 0, 0, 0);
  }
  if (value == valueTrue) {
    return rtStringFromWords(0x65757274, 0, 0, 0);
  }
  if (kind == typeKindInt) return rtIntToString(rtValueInt(value));
  if (kind == typeKindDouble) return rtDoubleToString(rtValueDouble(value));
  if (kind == typeKindString) return value;
  if (kind == typeKindFunction) {
    return rtStringFromWords(0x657275736f6c43, 0, 0, 0);
  }
  var descriptor = rtObjectDescriptor(value);
  if (kind == typeKindClass) {
    var callback = nativeLoad64(descriptor + descriptorToStringOffset);
    if (callback != 0) return nativeCall1(descriptor + callback, value);
    var name = descriptor + nativeLoad64(descriptor + descriptorNameOffset);
    var prefix = rtStringFromWords(0x65636e6174736e49, 0x2720666f20, 0, 0);
    rtRootPush(prefix, storageRef);
    var suffix = rtStringFromWords(39, 0, 0, 0);
    rtRootPush(suffix, storageRef);
    var head = rtStringConcat(prefix, name);
    rtRootPush(head, storageRef);
    return rtStringConcat(head, suffix);
  }
  var length = rtListLength(value);
  if (length == 0) return rtStringFromWords(0x5d5b, 0, 0, 0);
  if (rtValueActiveRoot == 0) {
    var active = rtListNew(handleType);
    rtValueActiveRoot = rtGlobalRootNew(active, storageRef);
  }
  var active = rtGlobalRootValue(rtValueActiveRoot);
  var depth = rtListLength(active);
  var i = 0;
  while (i < depth) {
    if (rtListRawGet(active, i) == value) {
      return rtStringFromWords(0x5d2e2e2e5b, 0, 0, 0);
    }
    i = i + 1;
  }
  var wordType = rtTypeArgument(handleType);
  rtListAdd(active, value, wordType);
  var parts = rtListNew(handleType);
  rtRootPush(parts, storageRef);
  var opening = rtStringFromWords(91, 0, 0, 0);
  rtRootPush(opening, storageRef);
  rtListAdd(parts, opening, wordType);
  var separator = rtStringFromWords(0x202c, 0, 0, 0);
  rtRootPush(separator, storageRef);
  var elementType = rtListElementType(value);
  i = 0;
  while (i < length) {
    var mark = rtRootMark();
    if (i != 0) rtListAdd(parts, separator, wordType);
    var element = rtValueBox(rtListRawGet(value, i), elementType);
    rtRootPush(element, storageTagged);
    var rendered = rtValueFormat(element, handleType);
    rtRootPush(rendered, storageRef);
    if (nativeLoad64(value + listLengthOffset) != length) {
      return rtListModificationError();
    }
    rtListAdd(parts, rendered, wordType);
    rtRootRestore(mark);
    i = i + 1;
  }
  var closing = rtStringFromWords(93, 0, 0, 0);
  rtRootPush(closing, storageRef);
  rtListAdd(parts, closing, wordType);
  var result = rtStringFromParts(parts);
  var backing = nativeLoad64(active + listBackingOffset);
  nativeStore64(backing + arrayLengthOffset, depth);
  nativeStore64(active + listLengthOffset, depth);
  return result;
}

int rtValueToString(int value) {
  var metadata = nativeMetadataAddress(metadataValues);
  var handleType = metadata + nativeLoad64(metadata + metadataHandleTypeOffset);
  return rtValueFormat(value, handleType);
}

Never rtRootFailure() {
  rtHostExit(70);
  while (true) {}
}

Never rtPatternMatchFailure() {
  rtValueTypeError();
  while (true) {}
}

int rtRootValues = 0;
int rtRootCount = 0;
int rtRootCapacity = 0;
int rtGlobalRoots = 0;
int rtGlobalRootCount = 0;
int rtGlobalRootCapacity = 0;

@pragma('dartc:no-gc')
int rtRootBuffer(int previous, int count, int capacity) {
  var buffer = rtMap(capacity * 16);
  var i = 0;
  while (i < count) {
    nativeStore64(buffer + i * 16, nativeLoad64(previous + i * 16));
    nativeStore64(buffer + i * 16 + 8, nativeLoad64(previous + i * 16 + 8));
    i = i + 1;
  }
  return buffer;
}

@pragma('dartc:no-gc')
int rtRootMark() {
  return rtRootCount;
}

@pragma('dartc:no-gc')
int rtRootPush(int value, int kind) {
  if (kind == storageRef) {
    if (value == 0) return 0;
  } else if (kind == storageTagged) {
    if (value <= valueTrue || (value & 1) != 0) return 0;
  } else {
    return rtRootFailure();
  }
  if (rtRootCount == rtRootCapacity) {
    var capacity = rtRootCapacity * 2;
    if (capacity == 0) capacity = 1024;
    var previous = rtRootValues;
    var oldCapacity = rtRootCapacity;
    rtRootValues = rtRootBuffer(previous, rtRootCount, capacity);
    rtRootCapacity = capacity;
    rtUnmap(previous, oldCapacity * 16);
  }
  var slot = rtRootValues + rtRootCount * 16;
  nativeStore64(slot, value);
  nativeStore64(slot + 8, kind);
  rtRootCount = rtRootCount + 1;
  return 0;
}

@pragma('dartc:no-gc')
int rtRootPushValue(int value, int type) {
  var representation = nativeLoad64(type + typeValueRepOffset);
  if (representation == storageWord) return 0;
  return rtRootPush(value, representation);
}

@pragma('dartc:no-gc')
int rtRootRestore(int mark) {
  if (mark < 0 || mark > rtRootCount) return rtRootFailure();
  rtRootCount = mark;
  return 0;
}

@pragma('dartc:no-gc')
int rtGlobalRootNew(int value, int kind) {
  if (kind != storageRef && kind != storageTagged) return rtRootFailure();
  if (rtGlobalRootCount == rtGlobalRootCapacity) {
    var capacity = rtGlobalRootCapacity * 2;
    if (capacity == 0) capacity = 1024;
    var previous = rtGlobalRoots;
    var oldCapacity = rtGlobalRootCapacity;
    rtGlobalRoots = rtRootBuffer(previous, rtGlobalRootCount, capacity);
    rtGlobalRootCapacity = capacity;
    rtUnmap(previous, oldCapacity * 16);
  }
  var slot = rtGlobalRoots + rtGlobalRootCount * 16;
  nativeStore64(slot, value);
  nativeStore64(slot + 8, kind);
  rtGlobalRootCount = rtGlobalRootCount + 1;
  return rtGlobalRootCount;
}

@pragma('dartc:no-gc')
int rtGlobalRootValue(int index) {
  if (index <= 0 || index > rtGlobalRootCount) return rtRootFailure();
  return nativeLoad64(rtGlobalRoots + (index - 1) * 16);
}

@pragma('dartc:no-gc')
int rtGlobalRootSet(int index, int value) {
  if (index <= 0 || index > rtGlobalRootCount) return rtRootFailure();
  nativeStore64(rtGlobalRoots + (index - 1) * 16, value);
  return 0;
}

int rtRootAppend(int value, int kind, int worklist, int count, int capacity) {
  if (kind == storageRef) {
    if (value == 0) return count;
  } else if (kind == storageTagged) {
    if (value <= valueTrue || (value & 1) != 0) return count;
  } else {
    return rtRootFailure();
  }
  if (count >= capacity) return rtRootFailure();
  nativeStore64(worklist + count * 8, value);
  return count + 1;
}

@pragma('dartc:no-gc')
int rtTraceRoots(int frame, int worklist, int capacity) {
  if (frame == 0 || capacity < 0 || capacity != 0 && worklist == 0) {
    return rtRootFailure();
  }
  var metadata = nativeMetadataAddress(metadataRoots);
  var displacement = nativeLoad64(metadata + metadataRootTableOffset);
  if (displacement == 0) return rtRootFailure();
  var table = metadata + displacement;
  var callCount = nativeLoad64(table + rootTableCallCountOffset);
  var calls = table + nativeLoad64(table + rootTableCallsOffset);
  var globalCount = nativeLoad64(table + rootTableGlobalCountOffset);
  var globals = table + nativeLoad64(table + rootTableGlobalsOffset);
  var count = 0;
  var i = 0;
  while (i < rtGlobalRootCount) {
    var slot = rtGlobalRoots + i * 16;
    count = rtRootAppend(
      nativeLoad64(slot),
      nativeLoad64(slot + 8),
      worklist,
      count,
      capacity,
    );
    i = i + 1;
  }
  i = 0;
  while (i < rtRootCount) {
    var slot = rtRootValues + i * 16;
    count = rtRootAppend(
      nativeLoad64(slot),
      nativeLoad64(slot + 8),
      worklist,
      count,
      capacity,
    );
    i = i + 1;
  }
  i = 0;
  while (i < globalCount) {
    var record = globals + i * globalRootBytes;
    var slot = record + nativeLoad64(record + globalRootAddressOffset);
    count = rtRootAppend(
      nativeLoad64(slot),
      nativeLoad64(record + globalRootKindOffset),
      worklist,
      count,
      capacity,
    );
    i = i + 1;
  }
  while (true) {
    var pc = nativeLoad64(frame + 8);
    var low = 0;
    var high = callCount;
    while (low < high) {
      var middle = (low + high) ~/ 2;
      var record = calls + middle * rootCallBytes;
      var returnPc = record + nativeLoad64(record + rootCallReturnOffset);
      if (returnPc < pc)
        low = middle + 1;
      else
        high = middle;
    }
    if (low == callCount) return rtRootFailure();
    var call = calls + low * rootCallBytes;
    if (call + nativeLoad64(call + rootCallReturnOffset) != pc) {
      return rtRootFailure();
    }
    var roots = nativeLoad64(call + rootCallCountOffset);
    if (roots == -1) return count;
    if (roots < 0) return rtRootFailure();
    var caller = nativeLoad64(frame);
    if (caller == 0) return rtRootFailure();
    var slots = call + nativeLoad64(call + rootCallSlotsOffset);
    i = 0;
    while (i < roots) {
      var record = slots + i * rootSlotBytes;
      var slot = caller + nativeLoad64(record + rootSlotFrameOffset);
      count = rtRootAppend(
        nativeLoad64(slot),
        nativeLoad64(record + rootSlotKindOffset),
        worklist,
        count,
        capacity,
      );
      i = i + 1;
    }
    frame = caller;
  }
}

@pragma('dartc:no-gc')
int rtTraceBitmap(
  int value,
  int fields,
  int bitmap,
  int kind,
  int worklist,
  int count,
  int capacity,
) {
  var field = 0;
  while (field < fields) {
    var bits = nativeLoad64(bitmap + (field ~/ 64) * 8);
    var end = field + 64;
    if (end > fields) end = fields;
    while (bits != 0 && field < end) {
      if ((bits & 1) != 0) {
        count = rtRootAppend(
          nativeLoad64(value + objectHeaderBytes + field * 8),
          kind,
          worklist,
          count,
          capacity,
        );
      }
      bits = bits >>> 1;
      field = field + 1;
    }
    field = end;
  }
  return count;
}

@pragma('dartc:no-gc')
int rtTraceType(int type, int worklist, int count, int capacity) {
  if ((nativeLoad64(type + objectFlagsOffset) & objectStaticRelative) != 0)
    return count;
  return rtRootAppend(type, storageRef, worklist, count, capacity);
}

// value is an object base supplied by root or object-edge enumeration.
@pragma('dartc:no-gc')
int rtTraceObject(int value, int worklist, int capacity) {
  if (capacity < 0 || capacity != 0 && worklist == 0) {
    return rtRootFailure();
  }
  if (value == 0) return 0;
  var descriptor = rtObjectDescriptor(value);
  var kind = nativeLoad64(descriptor + descriptorKindOffset);
  switch (kind) {
    case descriptorString ||
        descriptorIntBox ||
        descriptorDoubleBox ||
        descriptorWordArray:
      return 0;
    case descriptorList:
      var count = rtRootAppend(
        nativeLoad64(value + listBackingOffset),
        storageRef,
        worklist,
        0,
        capacity,
      );
      return rtTraceType(
        nativeLoad64(value + listTypeOffset),
        worklist,
        count,
        capacity,
      );
    case descriptorType:
      // Static types only refer to other static metadata.
      if ((nativeLoad64(value + objectFlagsOffset) & objectStaticRelative) != 0)
        return 0;
      var typeKind = nativeLoad64(value + typeKindOffset);
      if (typeKind == typeKindList || typeKind == typeKindNullable)
        return rtTraceType(rtTypeArgument(value), worklist, 0, capacity);
      if (typeKind != typeKindFunction ||
          nativeLoad64(value + typeArgumentOffset) == 0)
        return 0;
      // A heap function type owns its signature inline, after the type record.
      var signature = rtTypeArgument(value);
      var result =
          signature + nativeLoad64(signature + functionSignatureResultOffset);
      var count = rtTraceType(result, worklist, 0, capacity);
      var parameters = nativeLoad64(signature + functionSignatureCountOffset);
      var i = 0;
      while (i < parameters) {
        var entry = signature + functionSignatureParametersOffset + i * 8;
        count = rtTraceType(
          entry + nativeLoad64(entry),
          worklist,
          count,
          capacity,
        );
        i++;
      }
      return count;
    case descriptorClass || descriptorFunction:
      var count = 0;
      if (kind == descriptorFunction)
        count = rtTraceType(rtFunctionType(value), worklist, count, capacity);
      var fields = nativeLoad64(descriptor + descriptorFieldsOffset);
      var bitmap = nativeLoad64(descriptor + descriptorRefBitmapOffset);
      if (bitmap != 0) {
        count = rtTraceBitmap(
          value,
          fields,
          descriptor + bitmap,
          storageRef,
          worklist,
          count,
          capacity,
        );
      }
      bitmap = nativeLoad64(descriptor + descriptorTaggedBitmapOffset);
      if (bitmap != 0) {
        count = rtTraceBitmap(
          value,
          fields,
          descriptor + bitmap,
          storageTagged,
          worklist,
          count,
          capacity,
        );
      }
      return count;
    case descriptorRefArray || descriptorTaggedArray:
      var count = 0;
      var representation = storageRef;
      if (kind == descriptorTaggedArray) representation = storageTagged;
      var length = nativeLoad64(value + arrayLengthOffset);
      var i = 0;
      while (i < length) {
        count = rtRootAppend(
          nativeLoad64(value + arrayDataOffset + i * 8),
          representation,
          worklist,
          count,
          capacity,
        );
        i = i + 1;
      }
      return count;
    default:
      return rtRootFailure();
  }
}
