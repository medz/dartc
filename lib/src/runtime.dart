external int nativeLoad64(int p);
external int nativeStore64(int p, int value);
external int nativeLoad8(int p);
external int nativeStore8(int p, int value);
external int nativeSyscall(int n, int a, int b, int c, int d, int e, int f);
external int nativeTarget();

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

int rtAlloc(int bytes) {
  var size = (bytes + 15) & -16;
  if (rtArenaNext + size > rtArenaEnd || rtArenaNext == 0) {
    var capacity = 8388608;
    if (size > capacity) capacity = (size + 16383) & -16384;
    var memory = rtSyscall(197, 0, capacity, 3, 4098, -1, 0);
    if (memory < 0) rtHostExit(71);
    rtArenaNext = memory;
    rtArenaEnd = memory + capacity;
  }
  var result = rtArenaNext;
  rtArenaNext = rtArenaNext + size;
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

int rtStringLength(int value) {
  return nativeLoad64(value);
}

int rtStringCodeUnit(int value, int index) {
  return nativeLoad64(value + 8 + index * 8);
}

int rtStringNew(int length) {
  var result = rtAlloc(8 + length * 8);
  nativeStore64(result, length);
  return result;
}

int rtStringConcat(int left, int right) {
  var a = nativeLoad64(left);
  var b = nativeLoad64(right);
  var result = rtStringNew(a + b);
  var i = 0;
  while (i < a) {
    nativeStore64(result + 8 + i * 8, nativeLoad64(left + 8 + i * 8));
    i = i + 1;
  }
  i = 0;
  while (i < b) {
    nativeStore64(result + 8 + (a + i) * 8, nativeLoad64(right + 8 + i * 8));
    i = i + 1;
  }
  return result;
}

int rtStringEqual(int left, int right) {
  if (left == right) return 1;
  var length = nativeLoad64(left);
  if (length != nativeLoad64(right)) return 0;
  var i = 0;
  while (i < length) {
    if (nativeLoad64(left + 8 + i * 8) != nativeLoad64(right + 8 + i * 8))
      return 0;
    i = i + 1;
  }
  return 1;
}

int rtStringSubstring(int value, int start, int end) {
  if (end < 0) end = nativeLoad64(value);
  var result = rtStringNew(end - start);
  var i = start;
  while (i < end) {
    nativeStore64(
      result + 8 + (i - start) * 8,
      nativeLoad64(value + 8 + i * 8),
    );
    i = i + 1;
  }
  return result;
}

int rtStringStartsWith(int value, int prefix, int start) {
  var n = nativeLoad64(prefix);
  if (start + n > nativeLoad64(value)) return 0;
  var i = 0;
  while (i < n) {
    if (nativeLoad64(value + 8 + (start + i) * 8) !=
        nativeLoad64(prefix + 8 + i * 8))
      return 0;
    i = i + 1;
  }
  return 1;
}

int rtStringEndsWith(int value, int suffix) {
  var start = nativeLoad64(value) - nativeLoad64(suffix);
  if (start < 0) return 0;
  return rtStringStartsWith(value, suffix, start);
}

int rtStringIndexOf(int value, int needle, int start) {
  var end = nativeLoad64(value) - nativeLoad64(needle);
  var i = start;
  while (i <= end) {
    if (rtStringStartsWith(value, needle, i) == 1) return i;
    i = i + 1;
  }
  return -1;
}

int rtStringLastIndexOf(int value, int needle, int start) {
  if (start < 0) start = nativeLoad64(value);
  var end = nativeLoad64(value) - nativeLoad64(needle);
  var i = start;
  if (i > end) i = end;
  while (i >= 0) {
    if (rtStringStartsWith(value, needle, i) == 1) return i;
    i = i - 1;
  }
  return -1;
}

int rtIntToString(int value) {
  var digits = rtAlloc(168);
  var count = 0;
  var negative = 0;
  var number = value;
  if (number < 0) negative = 1;
  if (number > 0) number = -number;
  if (number == 0) {
    nativeStore64(digits, 48);
    count = 1;
  }
  while (number < 0) {
    var quotient = number ~/ 10;
    var digit = quotient * 10 - number;
    nativeStore64(digits + count * 8, 48 + digit);
    count = count + 1;
    number = quotient;
  }
  var result = rtStringNew(count + negative);
  if (negative == 1) nativeStore64(result + 8, 45);
  var i = 0;
  while (i < count) {
    nativeStore64(
      result + 8 + (negative + i) * 8,
      nativeLoad64(digits + (count - i - 1) * 8),
    );
    i = i + 1;
  }
  return result;
}

int rtIntParse(int value) {
  var length = nativeLoad64(value);
  var i = 0;
  var sign = 1;
  if (length > 0 && rtStringCodeUnit(value, 0) == 45) {
    sign = -1;
    i = 1;
  } else if (length > 0 && rtStringCodeUnit(value, 0) == 43) {
    i = 1;
  }
  var radix = 10;
  if (i + 1 < length && rtStringCodeUnit(value, i) == 48) {
    var x = rtStringCodeUnit(value, i + 1);
    if (x == 120 || x == 88) {
      radix = 16;
      i = i + 2;
    }
  }
  var result = 0;
  while (i < length) {
    var c = rtStringCodeUnit(value, i);
    var digit = c - 48;
    if (c >= 65 && c <= 70) digit = c - 55;
    if (c >= 97 && c <= 102) digit = c - 87;
    if (digit < 0 || digit >= radix) rtHostExit(65);
    result = result * radix + digit;
    i = i + 1;
  }
  return result * sign;
}

int rtListNew() {
  var result = rtAlloc(24);
  nativeStore64(result, 0);
  nativeStore64(result + 8, 0);
  nativeStore64(result + 16, 0);
  return result;
}

int rtListLength(int list) {
  return nativeLoad64(list);
}

int rtListGet(int list, int index) {
  return nativeLoad64(nativeLoad64(list + 16) + index * 8);
}

int rtListSet(int list, int index, int value) {
  nativeStore64(nativeLoad64(list + 16) + index * 8, value);
  return value;
}

int rtListAdd(int list, int value) {
  var length = nativeLoad64(list);
  var capacity = nativeLoad64(list + 8);
  var data = nativeLoad64(list + 16);
  if (length == capacity) {
    capacity = capacity * 2;
    if (capacity == 0) capacity = 8;
    var replacement = rtAlloc(capacity * 8);
    var i = 0;
    while (i < length) {
      nativeStore64(replacement + i * 8, nativeLoad64(data + i * 8));
      i = i + 1;
    }
    data = replacement;
    nativeStore64(list + 8, capacity);
    nativeStore64(list + 16, data);
  }
  nativeStore64(data + length * 8, value);
  nativeStore64(list, length + 1);
  return 0;
}

int rtListRemoveLast(int list) {
  var length = nativeLoad64(list) - 1;
  nativeStore64(list, length);
  return nativeLoad64(nativeLoad64(list + 16) + length * 8);
}

int rtListClear(int list) {
  nativeStore64(list, 0);
  return 0;
}

int rtListFilled(int length, int value) {
  var result = rtListNew();
  var data = rtAlloc(length * 8);
  nativeStore64(result, length);
  nativeStore64(result + 8, length);
  nativeStore64(result + 16, data);
  var i = 0;
  while (i < length) {
    nativeStore64(data + i * 8, value);
    i = i + 1;
  }
  return result;
}

int rtStringFromCodes(int codes) {
  var length = rtListLength(codes);
  var result = rtStringNew(length * 2);
  var i = 0;
  var count = 0;
  while (i < length) {
    var c = rtListGet(codes, i);
    if (c > 65535) {
      var scalar = c - 65536;
      nativeStore64(result + 8 + count * 8, 55296 + (scalar >> 10));
      nativeStore64(result + 16 + count * 8, 56320 + (scalar & 1023));
      count = count + 2;
    } else {
      nativeStore64(result + 8 + count * 8, c);
      count = count + 1;
    }
    i = i + 1;
  }
  nativeStore64(result, count);
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
      nativeStore64(result + 8 + count * 8, 55296 + (scalar >> 10));
      nativeStore64(result + 16 + count * 8, 56320 + (scalar & 1023));
      count = count + 2;
    } else {
      nativeStore64(result + 8 + count * 8, c);
      count = count + 1;
    }
  }
  nativeStore64(result, count);
  return result;
}

int rtStringFromCString(int bytes) {
  var length = 0;
  while (nativeLoad8(bytes + length) != 0) length = length + 1;
  return rtStringDecodeUtf8(bytes, length);
}

int rtStringEncodeUtf8(int value) {
  var length = nativeLoad64(value);
  var result = rtAlloc(9 + length * 4);
  var i = 0;
  var count = 0;
  while (i < length) {
    var c = nativeLoad64(value + 8 + i * 8);
    i = i + 1;
    if (c >= 55296 && c <= 56319) {
      var low = 0;
      if (i < length) low = nativeLoad64(value + 8 + i * 8);
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
  var bytes = rtAlloc(capacity);
  var length = 0;
  var done = 0;
  while (done == 0) {
    if (length == capacity) {
      var replacement = rtAlloc(capacity * 2);
      var i = 0;
      while (i < length) {
        nativeStore8(replacement + i, nativeLoad8(bytes + i));
        i = i + 1;
      }
      bytes = replacement;
      capacity = capacity * 2;
    }
    var count = rtSyscall(3, fd, bytes + length, capacity - length, 0, 0, 0);
    if (count < 0) rtIoError();
    if (count == 0) done = 1;
    length = length + count;
  }
  rtSyscall(6, fd, 0, 0, 0, 0, 0);
  return rtStringDecodeUtf8(bytes, length);
}

int rtHostWrite(int path, int bytes) {
  var encoded = rtStringEncodeUtf8(path);
  var fd = rtSyscall(5, encoded + 8, 1537, 420, 0, 0, 0);
  if (fd < 0) rtIoError();
  var length = rtListLength(bytes);
  var data = rtAlloc(length);
  var i = 0;
  while (i < length) {
    nativeStore8(data + i, rtListGet(bytes, i));
    i = i + 1;
  }
  rtWriteAll(fd, data, length);
  rtSyscall(6, fd, 0, 0, 0, 0, 0);
  return 0;
}

int rtArguments(int argc, int argv) {
  rtExecutable = rtStringFromCString(nativeLoad64(argv));
  var result = rtListNew();
  var i = 1;
  while (i < argc) {
    rtListAdd(result, rtStringFromCString(nativeLoad64(argv + i * 8)));
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
