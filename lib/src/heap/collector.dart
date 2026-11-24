// A mark-sweep collector that never moves objects.
//
// Objects start with a 32-bit class number and 32-bit flags. Small objects
// live in blocks of equal cells, each size with its own list of free cells;
// large ones have a block each. This file uses only what the compiler supports.
import 'machine.dart';
import 'returns.dart';

/// Where the collector's own state is, or 0 before the first allocation.
int heap = 0;

// Flags of an object. Fixed ones exist from the start of the program.
const _flags = 4, _allocated = 1, _marked = 2, _fixed = 4;

// The state: the blocks, the bytes mapped since the last collection and how
// many start the next, the stack of objects to scan, whether any did not fit
// there, lists of free cells, and where cells are that were never used, from
// somewhere to the end of a block. All three are for each size.
const _blocks = 0, _grown = 8, _limit = 16;
const _pending = 24, _pendingBytes = 32, _pendingEnd = 40;
const _missed = 48, _free = 56, _unused = 328, _unusedEnd = 600;
const _stateBytes = 1024;

// A block: the next one, the size of its cells, and its own size.
const _next = 0, _cellBytes = 8, _blockBytes = 16, _firstCell = 32;

// Where arrays have their number of elements, and where those are.
const _length = 16, _elements = 24;

// A free cell holds the next one after its header.
const _nextFree = 8;

const _smallBlock = 262144, _largestCell = 512, _smallestLimit = 4194304;
const _firstPendingBytes = 65536, _garbage = 0x5bad5bad5bad5bad;

/// Zeroed memory for an object of [bytes] bytes, marked as in use, or 0.
int allocate(int bytes) {
  final cell = (bytes + 15) & ~15;
  if (cell <= _largestCell && heap != 0 && !collectsAlways()) {
    final size = heap + (cell >> 4) * 8, found = load64(size + _free);
    if (found != 0) {
      store64(size + _free, load64(found + _nextFree));
      store64(found, _allocated << 32);
      _fill(found + 8, cell - 8, 0);
      return found;
    }
    final unused = load64(size + _unused);
    if (unused != load64(size + _unusedEnd)) {
      store64(size + _unused, unused + cell);
      store64(unused, _allocated << 32);
      return unused;
    }
  }
  return _allocateSlowly(cell);
}

int _allocateSlowly(int cell) {
  if (heap == 0 && !_start()) return 0;
  if (collectsAlways() || load64(heap + _grown) >= load64(heap + _limit)) {
    collect();
  }
  var found = _takeFree(cell);
  if (found == 0) {
    if (!_addBlock(cell)) {
      collect();
      // A collection may free cells, or the memory for a block.
      if (load64(_freeList(cell)) == 0 && !_addBlock(cell)) return 0;
    }
    found = _takeFree(cell);
  }
  _fill(found, cell, 0);
  store32(found + _flags, _allocated);
  return found;
}

/// Creates the state, if there is memory for it.
bool _start() {
  final state = mapMemory(_stateBytes);
  if (state == 0) return false;
  final pending = mapMemory(_firstPendingBytes);
  if (pending == 0) {
    unmapMemory(state, _stateBytes);
    return false;
  }
  heap = state;
  store64(heap + _limit, _smallestLimit);
  store64(heap + _pending, pending);
  store64(heap + _pendingBytes, _firstPendingBytes);
  return true;
}

void _fill(int address, int bytes, int value) {
  for (var at = address; at < address + bytes; at += 8) {
    store64(at, value);
  }
}

/// Where the list of free cells of a size is. All large sizes share one, which
/// holds a cell only between adding its block and taking it.
int _freeList(int cell) =>
    heap + _free + (cell > _largestCell ? 0 : (cell >> 4) * 8);

int _takeFree(int cell) {
  final list = _freeList(cell), found = load64(list);
  if (found != 0) {
    store64(list, load64(found + _nextFree));
    return found;
  }
  if (cell > _largestCell) return 0;
  final size = heap + (cell >> 4) * 8, unused = load64(size + _unused);
  if (unused == load64(size + _unusedEnd)) return 0;
  store64(size + _unused, unused + cell);
  return unused;
}

void _giveFree(int cell, int address) {
  final list = _freeList(cell);
  store64(address, 0);
  store64(address + _nextFree, load64(list));
  store64(list, address);
}

/// Maps more cells of a size, if there is memory for them.
bool _addBlock(int cell) {
  final isLarge = cell > _largestCell;
  final bytes = isLarge ? cell + _firstCell : _smallBlock;
  final block = mapMemory(bytes);
  if (block == 0) return false;
  store64(block + _next, load64(heap + _blocks));
  store64(block + _cellBytes, cell);
  store64(block + _blockBytes, bytes);
  store64(heap + _blocks, block);
  store64(heap + _grown, load64(heap + _grown) + bytes);
  final first = block + _firstCell;
  if (isLarge) {
    _giveFree(cell, first);
  } else {
    final size = heap + (cell >> 4) * 8;
    store64(size + _unused, first);
    store64(size + _unusedEnd, first + (bytes - _firstCell) ~/ cell * cell);
  }
  return true;
}

/// Frees every object that the program cannot reach.
void collect() {
  if (heap == 0) return;
  _markStack();
  final roots = globalRoots(), count = globalRootCount();
  for (var i = 0; i < count; i++) {
    _mark(load64(roots + i * 8));
  }
  _scan();
  while (load64(heap + _missed) != 0) {
    store64(heap + _missed, 0);
    _scanMarked();
  }
  final kept = _sweep();
  store64(heap + _grown, 0);
  store64(heap + _limit, kept > _smallestLimit ? kept : _smallestLimit);
}

/// Marks what the functions that are running refer to.
void _markStack() {
  var frame = frameAddress(), native = load64(nativeFrame());
  while (true) {
    final table = stackMaps();
    final at = findReturn(table, load64(frame + 8) - codeStart());
    if (at == 0) {
      // C called this. What called C is further out, if there is anything.
      if (native == 0) return;
      frame = native;
      native = load64(native - 8);
      continue;
    }
    final record = table + at;
    // The record tells about the caller, whose frame is stored first.
    frame = load64(frame);
    final count = load32(record);
    for (var i = 0; i < count; i++) {
      _mark(load64(frame + load32Signed(record + 4 + i * 4)));
    }
  }
}

/// Marks [object], if it is one, to be scanned.
void _mark(int object) {
  // Odd ones are numbers.
  if (object == 0 || object & 1 != 0) return;
  final flags = load32(object + _flags);
  if (flags & (_marked | _fixed) != 0) return;
  store32(object + _flags, flags | _marked);
  final end = load64(heap + _pendingEnd);
  if (end == load64(heap + _pendingBytes) && !_growPending()) {
    // Scanning what is marked again finds it.
    store64(heap + _missed, 1);
    return;
  }
  store64(load64(heap + _pending) + end, object);
  store64(heap + _pendingEnd, end + 8);
}

bool _growPending() {
  final old = load64(heap + _pending), bytes = load64(heap + _pendingBytes);
  final grown = mapMemory(bytes * 2);
  if (grown == 0) return false;
  for (var at = 0; at < bytes; at += 8) {
    store64(grown + at, load64(old + at));
  }
  unmapMemory(old, bytes);
  store64(heap + _pending, grown);
  store64(heap + _pendingBytes, bytes * 2);
  return true;
}

/// Marks everything that marked objects refer to.
void _scan() {
  while (load64(heap + _pendingEnd) > 0) {
    final end = load64(heap + _pendingEnd) - 8;
    store64(heap + _pendingEnd, end);
    _markFields(load64(load64(heap + _pending) + end));
  }
}

void _markFields(int object) {
  final table = classTable();
  final record = table + load32(table + load32(object) * 4);
  final count = load32(record);
  for (var i = 0; i < count; i++) {
    _mark(load64(object + load32(record + 8 + i * 4)));
  }
  if (load32(record + 4) == 0) return;
  final length = load64(object + _length);
  for (var i = 0; i < length; i++) {
    _mark(load64(object + _elements + i * 8));
  }
}

/// Marks everything that any marked object refers to.
void _scanMarked() {
  var block = load64(heap + _blocks);
  while (block != 0) {
    final cell = load64(block + _cellBytes);
    final end = block + load64(block + _blockBytes);
    for (var at = block + _firstCell; at + cell <= end; at += cell) {
      if (load32(at + _flags) & _marked != 0) {
        _markFields(at);
        _scan();
      }
    }
    block = load64(block + _next);
  }
}

/// Frees unmarked objects and unmarks the others, returning their size.
///
/// The lists of free cells are made anew, without blocks that become unused.
int _sweep() {
  _fill(heap + _free, _largestCell ~/ 16 * 8 + 8, 0);
  _fill(heap + _unused, _stateBytes - _unused, 0);
  var kept = 0, link = heap + _blocks;
  while (load64(link) != 0) {
    final block = load64(link), used = _usedBytes(block);
    if (used == 0) {
      store64(link, load64(block + _next));
      unmapMemory(block, load64(block + _blockBytes));
    } else {
      _sweepBlock(block);
      kept += used;
      link = block + _next;
    }
  }
  return kept;
}

int _usedBytes(int block) {
  final cell = load64(block + _cellBytes);
  final end = block + load64(block + _blockBytes);
  var used = 0;
  for (var at = block + _firstCell; at + cell <= end; at += cell) {
    if (load32(at + _flags) & _marked != 0) used += cell;
  }
  return used;
}

void _sweepBlock(int block) {
  final cell = load64(block + _cellBytes);
  final end = block + load64(block + _blockBytes);
  for (var at = block + _firstCell; at + cell <= end; at += cell) {
    if (load32(at + _flags) & _marked != 0) {
      store32(at + _flags, _allocated);
    } else {
      if (collectsAlways()) _fill(at, cell, _garbage);
      _giveFree(cell, at);
    }
  }
}
