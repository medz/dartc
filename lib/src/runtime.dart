import 'layout.dart';

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

const int rtAbiVersion = 5;

int rtArenaNext = 0;
int rtArenaEnd = 0;
int rtExecutable = 0;

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

int rtAlloc(int bytes) {
  var size = (bytes + 15) & -16;
  if (rtArenaNext + size > rtArenaEnd || rtArenaNext == 0) {
    var capacity = 8388608;
    if (size > capacity) capacity = (size + 16383) & -16384;
    var memory = rtMap(capacity);
    rtArenaNext = memory;
    rtArenaEnd = memory + capacity;
  }
  var result = rtArenaNext;
  rtArenaNext = rtArenaNext + size;
  return result;
}

int rtGrowBuffer(int address, int oldBytes, int newBytes) {
  var oldSize = (oldBytes + 15) & -16;
  var newSize = (newBytes + 15) & -16;
  if (address != 0 &&
      address + oldSize == rtArenaNext &&
      address + newSize <= rtArenaEnd) {
    rtArenaNext = address + newSize;
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

int rtCString(int a, int b, int c, int d) {
  var p = rtAlloc(32);
  nativeStore64(p, a);
  nativeStore64(p + 8, b);
  nativeStore64(p + 16, c);
  nativeStore64(p + 24, d);
  return p;
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

int rtIoError() {
  var message = rtCString(0x726f727265204f49, 10, 0, 0);
  rtWriteAll(2, message, 9);
  rtHostExit(74);
  return 0;
}

int rtInitializationError() {
  var message = rtCString(
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
  var message = rtCString(
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
  var message = rtCString(
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
  var message = rtCString(
    0x66203a6374726164,
    0x73696c2064657869,
    0x6874676e656c2074,
    0xa,
  );
  rtWriteAll(2, message, 25);
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
  if (actualType != sourceType) {
    stored = rtValueCast(rtValueBox(value, sourceType), actualType);
  }
  var length = nativeLoad64(list + listLengthOffset);
  if (index < 0 || index >= length) return rtListRangeError();
  var backing = nativeLoad64(list + listBackingOffset);
  nativeStore64(backing + arrayDataOffset + index * 8, stored);
  return value;
}

int rtListAdd(int list, int value, int sourceType) {
  var stored = value;
  var actualType = rtListElementType(list);
  if (actualType != sourceType) {
    stored = rtValueCast(rtValueBox(value, sourceType), actualType);
  }
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var length = nativeLoad64(list + listLengthOffset);
  var capacity = nativeLoad64(list + listCapacityOffset);
  var backing = nativeLoad64(list + listBackingOffset);
  if (length == capacity) {
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
  }
  nativeStore64(backing + arrayDataOffset + length * 8, stored);
  nativeStore64(backing + arrayLengthOffset, length + 1);
  nativeStore64(list + listLengthOffset, length + 1);
  return 0;
}

int rtListRemoveLast(int list, int expectedType) {
  if ((nativeLoad64(list + objectFlagsOffset) & objectListFixed) != 0) {
    return rtListFixedError();
  }
  var length = nativeLoad64(list + listLengthOffset) - 1;
  var value = rtListGet(list, length, expectedType);
  var backing = nativeLoad64(list + listBackingOffset);
  nativeStore64(backing + arrayLengthOffset, length);
  nativeStore64(list + listLengthOffset, length);
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
  var result = rtListNew(typeRef);
  if (growable == 0) {
    nativeStore64(result + objectFlagsOffset, objectListFixed);
  }
  if (length == 0) return result;
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
  return result;
}

int rtStringFromCodes(int codes) {
  var length = rtListLength(codes);
  var units = length;
  var i = 0;
  while (i < length) {
    var code = rtListRawGet(codes, i);
    if (code < 0 || code > 1114111) {
      var message = rtCString(
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

int rtStringEncodeUtf8(int value) {
  var length = nativeLoad64(value + stringLengthOffset);
  var result = rtAlloc(9 + length * 4);
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

int rtPrintString(int value) {
  var encoded = rtStringEncodeUtf8(value);
  var length = nativeLoad64(encoded);
  nativeStore8(encoded + 8 + length, 10);
  rtWriteAll(1, encoded + 8, length + 1);
  return 0;
}

int rtPrintInt(int value) {
  return rtPrintString(rtIntToString(value));
}

int rtPrintBool(int value) {
  var p = 0;
  var length = 0;
  if (value == 0) {
    p = rtCString(0x0a65736c6166, 0, 0, 0);
    length = 6;
  } else {
    p = rtCString(0x0a65757274, 0, 0, 0);
    length = 5;
  }
  rtWriteAll(1, p, length);
  return 0;
}

int rtHostRead(int path) {
  var encoded = rtStringEncodeUtf8(path);
  var fd = rtSyscall(5, encoded + 8, 0, 0, 0, 0, 0);
  if (fd < 0) rtIoError();
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
    if (count < 0) rtIoError();
    if (count == 0) done = 1;
    length = length + count;
  }
  rtSyscall(6, fd, 0, 0, 0, 0, 0);
  var result = rtStringDecodeUtf8(bytes, length);
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

int rtHostWrite(int path, int bytes) {
  var encoded = rtStringEncodeUtf8(path);
  var fd = rtSyscall(5, encoded + 8, 1537, 420, 0, 0, 0);
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
  rtExecutable = rtStringFromCString(nativeLoad64(argv));
  var result = rtListNew(typeRef);
  var i = 1;
  while (i < argc) {
    rtListAdd(
      result,
      rtStringFromCString(nativeLoad64(argv + i * 8)),
      rtTypeArgument(typeRef),
    );
    i = i + 1;
  }
  return result;
}

int rtHostStdPath() {
  var slash = rtStringFromCString(rtCString(47, 0, 0, 0));
  var end = rtStringLastIndexOf(
    rtExecutable,
    slash,
    rtStringLength(rtExecutable),
  );
  var directory = 0;
  if (end < 0) {
    directory = rtStringFromCString(rtCString(46, 0, 0, 0));
  } else {
    directory = rtStringSubstring(rtExecutable, 0, end);
  }
  var suffix = rtStringFromCString(
    rtCString(0x2f62696c2f2e2e2f, 0x746e75722f637273, 0x747261642e656d69, 0),
  );
  return rtStringConcat(directory, suffix);
}

int rtHostFinish(int path, int outputTarget) {
  var encoded = rtStringEncodeUtf8(path);
  var changed = rtSyscall(15, encoded + 8, 493, 0, 0, 0, 0);
  if (changed < 0) rtIoError();
  rtHostExit(0);
  return 0;
}

int rtObjectDescriptor(int object) {
  var descriptor = nativeLoad64(object);
  if ((nativeLoad64(object + objectFlagsOffset) & objectStaticRelative) != 0) {
    descriptor = object + descriptor;
  }
  return descriptor;
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

int rtObjectGet(int object, int index) {
  return nativeLoad64(object + objectHeaderBytes + index * 8);
}

int rtObjectSet(int object, int index, int value) {
  nativeStore64(object + objectHeaderBytes + index * 8, value);
  return value;
}

int rtValueTypeError() {
  var message = rtCString(
    0x72203a6374726164,
    0x7420656d69746e75,
    0x6f72726520657079,
    0xa72,
  );
  rtWriteAll(2, message, 26);
  rtHostExit(70);
  return 0;
}

int rtTypeArgument(int type) {
  return type + nativeLoad64(type + typeArgumentOffset);
}

int rtTypeSubtype(int actual, int expected) {
  if (actual == expected) return 1;
  var target = nativeLoad64(expected + typeKindOffset);
  if (target == typeKindDynamic || target == typeKindVoid) return 1;
  var source = nativeLoad64(actual + typeKindOffset);
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
  if (source == typeKindInt && target == typeKindNum) return 1;
  if (source != target) return 0;
  if (source == typeKindList) {
    return rtTypeSubtype(rtTypeArgument(actual), rtTypeArgument(expected));
  }
  if (source == typeKindClass) {
    var left = actual + nativeLoad64(actual + typeClassOffset);
    var right = expected + nativeLoad64(expected + typeClassOffset);
    if (left != right) return 0;
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
  if (kind == descriptorString) return typeKindString;
  if (kind == descriptorList) return typeKindList;
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
  if (kind == typeKindBool) return rtBoxBool(value);
  if (kind == typeKindNull) return 0;
  return rtValueTypeError();
}

int rtValueMatches(int value, int expected) {
  var kind = nativeLoad64(expected + typeKindOffset);
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
  if (kind == typeKindNum && actual == typeKindInt) return 1;
  if (actual != kind) return 0;
  if (kind == typeKindList) {
    return rtTypeSubtype(nativeLoad64(value + listTypeOffset), expected);
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
  if (kind == typeKindBool) return rtValueBool(value);
  if (kind == typeKindVoid) return 0;
  return value;
}

int rtValueAdd(int left, int right) {
  var kind = rtValueKind(left);
  if (kind == typeKindInt)
    return rtBoxInt(rtValueInt(left) + rtValueInt(right));
  if (kind == typeKindString && rtValueKind(right) == typeKindString) {
    return rtStringConcat(left, right);
  }
  return rtValueTypeError();
}

int rtValueSub(int left, int right) {
  return rtBoxInt(rtValueInt(left) - rtValueInt(right));
}

int rtValueMul(int left, int right) {
  return rtBoxInt(rtValueInt(left) * rtValueInt(right));
}

int rtValueDiv(int left, int right) {
  var divisor = rtValueInt(right);
  if (divisor == 0) return rtValueTypeError();
  return rtBoxInt(rtValueInt(left) ~/ divisor);
}

int rtValueMod(int left, int right) {
  var divisor = rtValueInt(right);
  if (divisor == 0) return rtValueTypeError();
  return rtBoxInt(rtValueInt(left) % divisor);
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

int rtValueEq(int left, int right) {
  if (left == right) return 1;
  var a = rtValueKind(left);
  var b = rtValueKind(right);
  if (a != b) return 0;
  if (a == typeKindInt) {
    if (rtValueInt(left) == rtValueInt(right)) return 1;
  } else if (a == typeKindString) {
    return rtStringEqual(left, right);
  }
  return 0;
}

int rtValueLt(int left, int right) {
  if (rtValueInt(left) < rtValueInt(right)) return 1;
  return 0;
}

int rtValueLe(int left, int right) {
  if (rtValueInt(left) <= rtValueInt(right)) return 1;
  return 0;
}

int rtValueGt(int left, int right) {
  if (rtValueInt(left) > rtValueInt(right)) return 1;
  return 0;
}

int rtValueGe(int left, int right) {
  if (rtValueInt(left) >= rtValueInt(right)) return 1;
  return 0;
}

int rtListModificationError() {
  var message = rtCString(
    0x63203a6374726164,
    0x6e65727275636e6f,
    0x696669646f6d2074,
    0xa6e6f69746163,
  );
  rtWriteAll(2, message, 31);
  rtHostExit(70);
  return 0;
}

int rtValueActive = 0;

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
  if (value == 0) {
    return rtStringFromCString(rtCString(0x6c6c756e, 0, 0, 0));
  }
  if (value == valueFalse) {
    return rtStringFromCString(rtCString(0x65736c6166, 0, 0, 0));
  }
  if (value == valueTrue) {
    return rtStringFromCString(rtCString(0x65757274, 0, 0, 0));
  }
  var kind = rtValueKind(value);
  if (kind == typeKindInt) return rtIntToString(rtValueInt(value));
  if (kind == typeKindString) return value;
  var descriptor = rtObjectDescriptor(value);
  if (kind == typeKindClass) {
    var callback = nativeLoad64(descriptor + descriptorToStringOffset);
    if (callback != 0) return nativeCall1(descriptor + callback, value);
    var name = descriptor + nativeLoad64(descriptor + descriptorNameOffset);
    var prefix = rtStringFromCString(
      rtCString(0x65636e6174736e49, 0x2720666f20, 0, 0),
    );
    var suffix = rtStringFromCString(rtCString(39, 0, 0, 0));
    return rtStringConcat(rtStringConcat(prefix, name), suffix);
  }
  var length = rtListLength(value);
  if (length == 0) return rtStringFromCString(rtCString(0x5d5b, 0, 0, 0));
  if (rtValueActive == 0) rtValueActive = rtListNew(handleType);
  var active = rtValueActive;
  var depth = rtListLength(active);
  var i = 0;
  while (i < depth) {
    if (rtListRawGet(active, i) == value) {
      return rtStringFromCString(rtCString(0x5d2e2e2e5b, 0, 0, 0));
    }
    i = i + 1;
  }
  var wordType = rtTypeArgument(handleType);
  rtListAdd(active, value, wordType);
  var parts = rtListNew(handleType);
  rtListAdd(parts, rtStringFromCString(rtCString(91, 0, 0, 0)), wordType);
  var separator = rtStringFromCString(rtCString(0x202c, 0, 0, 0));
  var elementType = rtListElementType(value);
  i = 0;
  while (i < length) {
    if (i != 0) rtListAdd(parts, separator, wordType);
    var element = rtValueBox(rtListRawGet(value, i), elementType);
    var rendered = rtValueFormat(element, handleType);
    if (nativeLoad64(value + listLengthOffset) != length) {
      return rtListModificationError();
    }
    rtListAdd(parts, rendered, wordType);
    i = i + 1;
  }
  rtListAdd(parts, rtStringFromCString(rtCString(93, 0, 0, 0)), wordType);
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
