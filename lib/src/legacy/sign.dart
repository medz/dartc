List<int> signConstants = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

int signRotate(int value, int bits) {
  return ((value >>> bits) | (value << (32 - bits))) & 0xffffffff;
}

List<int> signHash(List<int> bytes, int start, int length) {
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;
  var padded = ((length + 9 + 63) ~/ 64) * 64;
  final words = List<int>.filled(64, 0);
  var i = 0;
  var block = 0;
  while (block < padded) {
    i = 0;
    while (i < 16) {
      var word = 0;
      var j = 0;
      while (j < 4) {
        var offset = block + i * 4 + j;
        var value = 0;
        if (offset < length) {
          value = bytes[start + offset];
        } else if (offset == length) {
          value = 128;
        } else if (offset >= padded - 8) {
          value = ((length * 8) >>> ((padded - 1 - offset) * 8)) & 255;
        }
        word = (word << 8) | value;
        j = j + 1;
      }
      words[i] = word;
      i = i + 1;
    }
    while (i < 64) {
      var x = words[i - 15];
      var y = words[i - 2];
      var s0 = signRotate(x, 7) ^ signRotate(x, 18) ^ (x >>> 3);
      var s1 = signRotate(y, 17) ^ signRotate(y, 19) ^ (y >>> 10);
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & 0xffffffff;
      i = i + 1;
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;
    i = 0;
    while (i < 64) {
      var s1 = signRotate(e, 6) ^ signRotate(e, 11) ^ signRotate(e, 25);
      var choice = (e & f) ^ ((~e) & g);
      var t1 = (h + s1 + choice + signConstants[i] + words[i]) & 0xffffffff;
      var s0 = signRotate(a, 2) ^ signRotate(a, 13) ^ signRotate(a, 22);
      var majority = (a & b) ^ (a & c) ^ (b & c);
      var t2 = (s0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
      i = i + 1;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
    block = block + 64;
  }
  List<int> state = <int>[h0, h1, h2, h3, h4, h5, h6, h7];
  final result = List<int>.filled(32, 0);
  i = 0;
  while (i < state.length) {
    signBig32(result, i * 4, state[i]);
    i = i + 1;
  }
  return result;
}

void signLittle32(List<int> bytes, int offset, int value) {
  var i = 0;
  while (i < 4) {
    bytes[offset + i] = (value >>> (i * 8)) & 255;
    i = i + 1;
  }
}

void signLittle64(List<int> bytes, int offset, int value) {
  signLittle32(bytes, offset, value);
  signLittle32(bytes, offset + 4, value >>> 32);
}

int signRead64(List<int> bytes, int offset) {
  var result = 0;
  var i = 0;
  while (i < 8) {
    result = result | (bytes[offset + i] << (i * 8));
    i = i + 1;
  }
  return result;
}

void signBig32(List<int> bytes, int offset, int value) {
  var i = 0;
  while (i < 4) {
    bytes[offset + i] = (value >>> ((3 - i) * 8)) & 255;
    i = i + 1;
  }
}

void signBig64(List<int> bytes, int offset, int value) {
  signBig32(bytes, offset, value >>> 32);
  signBig32(bytes, offset + 4, value);
}

void signMachO(
  List<int> bytes,
  int signatureCommand,
  int linkeditCommand,
  int textSize,
  int isExecutable,
  int pageShift,
) {
  var pageSize = 1 << pageShift;
  var identifier = 'dev.medz.dartc';
  var codeLimit = bytes.length;
  var slots = (codeLimit + pageSize - 1) ~/ pageSize;
  var hashOffset = 88 + identifier.length + 1;
  var directoryLength = hashOffset + slots * 32;
  var blobLength = 20 + directoryLength;
  var signatureSize = ((blobLength + 15) ~/ 16) * 16;
  signLittle32(bytes, signatureCommand + 8, codeLimit);
  signLittle32(bytes, signatureCommand + 12, signatureSize);
  var fileOffset = signRead64(bytes, linkeditCommand + 40);
  var fileSize = codeLimit + signatureSize - fileOffset;
  signLittle64(bytes, linkeditCommand + 48, fileSize);
  signLittle64(
    bytes,
    linkeditCommand + 32,
    ((fileSize + pageSize - 1) ~/ pageSize) * pageSize,
  );

  final signature = List<int>.filled(signatureSize, 0);
  signBig32(signature, 0, 0xfade0cc0);
  signBig32(signature, 4, blobLength);
  signBig32(signature, 8, 1);
  signBig32(signature, 12, 0);
  signBig32(signature, 16, 20);
  var directory = 20;
  signBig32(signature, directory, 0xfade0c02);
  signBig32(signature, directory + 4, directoryLength);
  signBig32(signature, directory + 8, 0x20400);
  signBig32(signature, directory + 12, 2);
  signBig32(signature, directory + 16, hashOffset);
  signBig32(signature, directory + 20, 88);
  signBig32(signature, directory + 24, 0);
  signBig32(signature, directory + 28, slots);
  signBig32(signature, directory + 32, codeLimit);
  signature[directory + 36] = 32;
  signature[directory + 37] = 2;
  signature[directory + 39] = pageShift;
  signBig64(signature, directory + 64, 0);
  signBig64(signature, directory + 72, textSize);
  signBig64(signature, directory + 80, isExecutable);
  var i = 0;
  while (i < identifier.length) {
    signature[directory + 88 + i] = identifier.codeUnitAt(i);
    i = i + 1;
  }
  var page = 0;
  while (page < slots) {
    var start = page * pageSize;
    var length = codeLimit - start;
    if (length > pageSize) length = pageSize;
    var hash = signHash(bytes, start, length);
    i = 0;
    while (i < 32) {
      signature[directory + hashOffset + page * 32 + i] = hash[i];
      i = i + 1;
    }
    page = page + 1;
  }
  i = 0;
  while (i < signature.length) {
    bytes.add(signature[i]);
    i = i + 1;
  }
}
