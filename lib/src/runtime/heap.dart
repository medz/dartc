import '../runtime.dart';
import '../layout.dart';
import 'roots.dart';

const int rtArenaHeaderBytes = 32;
const int _arenaBytes = 8388608;
const int _freeBins = 118;

// Arena: next0/mapBytes8/bitmap16/bitmapBytes24.
// Two bits per 16-byte cell: interior0/allocated1/free2/marked3.
int rtArenaHead = 0;
int rtArenaCurrent = 0;
int rtArenaNext = 0;
int rtArenaEnd = 0;
int _freeHeads = 0;
int _allocated = 0;
int _budget = _arenaBytes;

@pragma('dartc:no-gc')
int _bin(int bytes) {
  // Exact 16-byte classes prevent repeated searches through undersized small
  // objects. Larger free spans use logarithmic classes and become bump regions.
  if (bytes <= 1024) return (bytes - 1) ~/ 16;
  var index = 64;
  bytes >>>= 10;
  while (bytes >= 2 && index < _freeBins - 1) {
    bytes >>>= 1;
    index++;
  }
  return index;
}

@pragma('dartc:no-gc')
void _boundary(int arena, int address, int state) {
  final cell = (address - arena - rtArenaHeaderBytes) ~/ 16;
  final word = nativeLoad64(arena + 16) + (cell ~/ 32) * 8;
  final shift = (cell * 2) & 63;
  nativeStore64(word, (nativeLoad64(word) & ~(3 << shift)) | (state << shift));
}

@pragma('dartc:no-gc')
int _arenaFor(int address, [int hint = 0, int secondHint = 0]) {
  if (hint != 0 &&
      address >= hint + rtArenaHeaderBytes &&
      address < hint + nativeLoad64(hint + 8))
    return hint;
  if (secondHint != 0 &&
      address >= secondHint + rtArenaHeaderBytes &&
      address < secondHint + nativeLoad64(secondHint + 8))
    return secondHint;
  var arena = rtArenaHead;
  while (arena != 0) {
    if (address >= arena + rtArenaHeaderBytes &&
        address < arena + nativeLoad64(arena + 8))
      return arena;
    arena = nativeLoad64(arena);
  }
  return 0;
}

@pragma('dartc:no-gc')
void _free(int arena, int address, int size) {
  if (size == 0) return;
  final head = _freeHeads + _bin(size) * 8;
  nativeStore64(address, nativeLoad64(head));
  nativeStore64(address + 8, size);
  nativeStore64(head, address);
  _boundary(arena, address, 2);
}

@pragma('dartc:no-gc')
void _seal() {
  if (rtArenaNext != 0 && rtArenaNext < rtArenaEnd) {
    _free(rtArenaCurrent, rtArenaNext, rtArenaEnd - rtArenaNext);
  }
  rtArenaNext = 0;
  rtArenaEnd = 0;
  rtArenaCurrent = 0;
}

@pragma('dartc:no-gc')
void _open(int size) {
  var capacity = _arenaBytes;
  if (size + rtArenaHeaderBytes > capacity)
    capacity = (size + rtArenaHeaderBytes + 16383) & -16384;
  final arena = rtMap(capacity);
  final bitmapBytes = (((capacity - rtArenaHeaderBytes) ~/ 16 + 31) ~/ 32) * 8;
  nativeStore64(arena, rtArenaHead);
  nativeStore64(arena + 8, capacity);
  nativeStore64(arena + 16, rtMap(bitmapBytes));
  nativeStore64(arena + 24, bitmapBytes);
  rtArenaHead = arena;
  rtArenaCurrent = arena;
  rtArenaNext = arena + rtArenaHeaderBytes;
  rtArenaEnd = arena + capacity;
}

void _reserve(int size) {
  if (_freeHeads == 0) _freeHeads = rtMap(_freeBins * 8);
  _seal();
  if (_allocated >= _budget) rtCollect();
  for (var bin = _bin(size); bin < _freeBins; bin++) {
    var link = _freeHeads + bin * 8;
    var block = nativeLoad64(link);
    while (block != 0) {
      final bytes = nativeLoad64(block + 8);
      if (bytes >= size) {
        nativeStore64(link, nativeLoad64(block));
        rtArenaCurrent = _arenaFor(block);
        _boundary(rtArenaCurrent, block, 0);
        rtArenaNext = block;
        rtArenaEnd = block + bytes;
        return;
      }
      link = block;
      block = nativeLoad64(block);
    }
  }
  _open(size);
}

@pragma('dartc:managed-allocate')
int rtAlloc(int bytes) {
  final size = (bytes + 15) & -16;
  if (rtArenaNext == 0 || rtArenaNext + size > rtArenaEnd) _reserve(size);
  final result = rtArenaNext;
  final cell = (result - rtArenaCurrent - rtArenaHeaderBytes) ~/ 16;
  final word = nativeLoad64(rtArenaCurrent + 16) + (cell ~/ 32) * 8;
  nativeStore64(word, nativeLoad64(word) | (1 << ((cell * 2) & 63)));
  rtArenaNext += size;
  _allocated += size;
  return result;
}

int rtGrowBuffer(int address, int oldBytes, int newBytes) {
  final oldSize = (oldBytes + 15) & -16;
  final newSize = (newBytes + 15) & -16;
  if (address != 0 &&
      address + oldSize == rtArenaNext &&
      address + newSize <= rtArenaEnd) {
    rtArenaNext = address + newSize;
    _allocated += newSize - oldSize;
    return address;
  }
  final mark = rtRootMark();
  rtRootPush(address, storageRef);
  final result = rtAlloc(newBytes);
  var offset = 0;
  while (offset + 8 <= oldBytes) {
    nativeStore64(result + offset, nativeLoad64(address + offset));
    offset += 8;
  }
  while (offset < oldBytes) {
    nativeStore8(result + offset, nativeLoad8(address + offset));
    offset++;
  }
  rtRootRestore(mark);
  return result;
}

// Collection is synchronous and non-moving. Only published object bases may
// occur in the precise roots and edges. Native metadata/worklists are not heap
// objects and never allocate managed storage during this traversal.
@pragma('dartc:may-gc')
@pragma('dartc:no-gc')
void rtCollect() {
  if (_freeHeads == 0) _freeHeads = rtMap(_freeBins * 8);
  _seal();
  final work = rtTraceBufferNew();
  rtTraceRoots(nativeFramePointer(), work);
  // No arena is released during marking. Reuse the two most recent distinct
  // arenas without retaining an address cache across collections.
  var hint = 0;
  var secondHint = 0;
  while (nativeLoad64(work + 8) != 0) {
    final count = nativeLoad64(work + 8) - 1;
    final value = nativeLoad64(nativeLoad64(work) + count * 8);
    nativeStore64(work + 8, count);
    final arena = _arenaFor(value, hint, secondHint);
    if (arena == 0) {
      if ((nativeLoad64(value + objectFlagsOffset) & objectStaticRelative) == 0)
        rtRootFailure();
      continue;
    }
    if (arena != hint) {
      secondHint = hint;
      hint = arena;
    }
    final offset = value - arena - rtArenaHeaderBytes;
    if ((offset & 15) != 0) rtRootFailure();
    final cell = offset ~/ 16;
    final word = nativeLoad64(arena + 16) + (cell ~/ 32) * 8;
    final shift = (cell * 2) & 63;
    final bits = nativeLoad64(word);
    final state = (bits >>> shift) & 3;
    if ((state & 1) == 0) rtRootFailure();
    if (state == 3) continue;
    nativeStore64(word, bits | (3 << shift));
    rtTraceObject(value, work);
  }
  rtTraceBufferFree(work);
  for (var bin = 0; bin < _freeBins; bin++)
    nativeStore64(_freeHeads + bin * 8, 0);
  var live = 0;
  var previous = 0;
  var arena = rtArenaHead;
  while (arena != 0) {
    final next = nativeLoad64(arena);
    final bitmap = nativeLoad64(arena + 16);
    final used = nativeLoad64(arena + 8) - rtArenaHeaderBytes;
    final words = ((used ~/ 16) + 31) ~/ 32;
    var marked = false;
    for (var i = 0; i < words; i++) {
      final bits = nativeLoad64(bitmap + i * 8);
      if ((bits & (bits >>> 1) & 0x5555555555555555) != 0) {
        marked = true;
        break;
      }
    }
    if (!marked) {
      if (previous == 0)
        rtArenaHead = next;
      else
        nativeStore64(previous, next);
      rtUnmap(bitmap, nativeLoad64(arena + 24));
      rtUnmap(arena, nativeLoad64(arena + 8));
    } else {
      final base = arena + rtArenaHeaderBytes;
      var freeStart = base;
      var last = base;
      var lastState = 0;
      for (var i = 0; i < words; i++) {
        var bits = nativeLoad64(bitmap + i * 8);
        final survivors = bits & (bits >>> 1) & 0x5555555555555555;
        nativeStore64(bitmap + i * 8, survivors);
        var cell = i * 32;
        // A word without marked starts contains only dead boundaries. Only
        // the first boundary can terminate a live span from the previous word.
        if (survivors == 0) {
          if (bits != 0) {
            if (lastState == 3) {
              while ((bits & 3) == 0) {
                bits >>>= 2;
                cell++;
              }
              final address = base + cell * 16;
              live += address - last;
              freeStart = address;
            }
            lastState = 0;
          }
          continue;
        }
        while (bits != 0) {
          final state = bits & 3;
          if (state != 0) {
            final address = base + cell * 16;
            if (lastState == 3) {
              live += address - last;
              freeStart = address;
            }
            if (state == 3 && freeStart < address)
              _free(arena, freeStart, address - freeStart);
            last = address;
            lastState = state;
          }
          bits >>>= 2;
          cell++;
        }
      }
      if (lastState == 3) {
        live += base + used - last;
        freeStart = base + used;
      }
      final end = arena + nativeLoad64(arena + 8);
      if (freeStart < end) _free(arena, freeStart, end - freeStart);
      previous = arena;
    }
    arena = next;
  }
  _allocated = 0;
  _budget = live > _arenaBytes ? live : _arenaBytes;
}
