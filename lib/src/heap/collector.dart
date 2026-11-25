// A mark-sweep collector that never moves objects.
//
// Objects start with a 32-bit class number and 32-bit flags. They live in
// blocks of equal cells, each size with its own list of free cells; large ones
// have a block each. The sizes are the multiples of 16 up to some size, and
// then four up to each power of two. This file uses only what the compiler
// supports.
import 'machine.dart';
import 'returns.dart';

/// Where the collector's own state is, or 0 before the first allocation.
int heap = 0;

// Flags of an object. Fixed ones exist from the start of the program.
const _flags = 4, _allocated = 1, _marked = 2, _fixed = 4;

// The state: the blocks, the bytes used up since the last collection and how
// many start the next, the stack of objects to scan, whether any did not fit
// there, lists of free cells, where cells are that were never used, from
// somewhere to the end of a block, lists of blocks with more free cells, and
// the bytes that the free or unused cells were. The last five are for each
// size, of which there are 57. The first stands for those that have a block
// each.
const _blocks = 0, _grown = 8, _limit = 16;
const _pending = 24, _pendingBytes = 32, _pendingEnd = 40;
const _missed = 48, _free = 56, _unused = 512, _unusedEnd = 968;
const _partial = 1424, _given = 1880, _stateBytes = 2336;

// A block: the next one, the size of its cells, its own size, its free cells
// and their bytes, as long as they are not taken, and the next block of the
// size that has any.
const _next = 0, _cellBytes = 8, _blockBytes = 16;
const _ownFree = 24, _freeBytes = 32, _nextPartial = 40, _firstCell = 48;

// Where arrays have their number of elements, and where those are.
const _length = 16, _elements = 24;

// A free cell holds the next one after its header.
const _nextFree = 8;

const _sharedBlock = 262144, _smallCell = 512, _largestCell = 32768;
const _smallestLimit = 4194304;
const _firstPendingBytes = 65536, _garbage = 0x5bad5bad5bad5bad;

/// Zeroed memory for an object of [bytes] bytes, marked as in use, or 0.
int allocate(int bytes) {
  final cell = (bytes + 15) & ~15;
  if (cell <= _smallCell && heap != 0 && !collectsAlways()) {
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

int _allocateSlowly(int bytes) {
  if (heap == 0 && !_start()) return 0;
  if (collectsAlways() || load64(heap + _grown) >= load64(heap + _limit)) {
    collect();
  }
  final cell = _cellFor(bytes), size = heap + _sizeOf(cell) * 8;
  var found = _take(size, cell, bytes);
  if (found == 0) {
    if (!_addBlock(size, cell)) {
      collect();
      // A collection may free cells, or the memory for a block.
      if (load64(size + _partial) == 0 && !_addBlock(size, cell)) return 0;
    }
    found = _take(size, cell, bytes);
  }
  store32(found + _flags, _allocated);
  return found;
}

/// The size of the cell that [bytes] need, which are a multiple of 16.
int _cellFor(int bytes) {
  if (bytes <= _smallCell || bytes > _largestCell) return bytes;
  var step = _smallCell ~/ 4;
  while (bytes > step * 8) {
    step *= 2;
  }
  return (bytes + step - 1) & -step;
}

/// Which of the sizes [cell] is. The large ones are one.
int _sizeOf(int cell) {
  if (cell <= _smallCell) return cell >> 4;
  if (cell > _largestCell) return 0;
  var shift = 7, first = _smallCell ~/ 16;
  while (cell >> shift > 8) {
    shift++;
    first += 4;
  }
  return first + (cell >> shift) - 4;
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

/// A zeroed cell of a size, or 0 if none is left. Only [bytes] of it are used.
int _take(int size, int cell, int bytes) {
  final unused = load64(size + _unused);
  if (unused != load64(size + _unusedEnd)) {
    store64(size + _unused, unused + cell);
    return unused;
  }
  if (load64(size + _free) == 0) _takePartial(size);
  final found = load64(size + _free);
  if (found == 0) return 0;
  store64(size + _free, load64(found + _nextFree));
  _fill(found, bytes, 0);
  return found;
}

/// Takes the free cells of the next block that has any, after all others of the
/// size were used.
void _takePartial(int size) {
  final block = load64(size + _partial);
  if (block == 0) return;
  store64(size + _partial, load64(block + _nextPartial));
  store64(size + _free, load64(block + _ownFree));
  _give(size, load64(block + _freeBytes));
}

/// Counts what was given before, as that is used up.
void _give(int size, int bytes) {
  store64(heap + _grown, load64(heap + _grown) + load64(size + _given));
  store64(size + _given, bytes);
}

/// Maps more cells of a size, if there is memory for them.
bool _addBlock(int size, int cell) {
  final isLarge = cell > _largestCell;
  final bytes = isLarge ? cell + _firstCell : _sharedBlock;
  final block = mapMemory(bytes);
  if (block == 0) return false;
  store64(block + _next, load64(heap + _blocks));
  store64(block + _cellBytes, cell);
  store64(block + _blockBytes, bytes);
  store64(heap + _blocks, block);
  final first = block + _firstCell;
  final cells = isLarge ? cell : (bytes - _firstCell) ~/ cell * cell;
  store64(size + _unused, first);
  store64(size + _unusedEnd, first + cells);
  _give(size, cells);
  // A large one is used up at once.
  if (isLarge) _give(size, 0);
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
    final record = findStackMap(stackMaps(), load64(frame + 8) - codeStart());
    if (record == 0) {
      // C called this. What called C is further out, if there is anything.
      if (native == 0) return;
      frame = native;
      native = load64(native - 8);
      continue;
    }
    // The record tells about the caller, whose frame is stored first.
    frame = load64(frame);
    _markFrame(frame, record);
  }
}

/// Marks what [record] tells of the function with [frame].
void _markFrame(int frame, int record) {
  final first = load32(record), count = first & 0x7fff;
  if (first & 0x8000 != 0) {
    for (var i = 1; i <= count; i++) {
      _mark(load64(frame + load32Signed(record + i * 4) * 8));
    }
    return;
  }
  for (var i = 1; i <= count; i++) {
    final word = load32Signed(record + (i >> 1) * 4);
    // The lower half keeps its sign where it is moved up and down.
    final offset = i & 1 != 0 ? word >> 16 : word << 48 >> 48;
    _mark(load64(frame + offset * 8));
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
  _fill(heap + _free, _stateBytes - _free, 0);
  var kept = 0, link = heap + _blocks;
  while (load64(link) != 0) {
    final block = load64(link), used = _sweepBlock(block);
    if (used == 0) {
      store64(link, load64(block + _next));
      unmapMemory(block, load64(block + _blockBytes));
    } else {
      if (load64(block + _ownFree) != 0) {
        final size = heap + _sizeOf(load64(block + _cellBytes)) * 8;
        store64(block + _nextPartial, load64(size + _partial));
        store64(size + _partial, block);
      }
      kept += used;
      link = block + _next;
    }
  }
  return kept;
}

/// Collects the free cells of [block], returning the size of the others.
int _sweepBlock(int block) {
  final cell = load64(block + _cellBytes);
  final end = block + load64(block + _blockBytes);
  var used = 0, free = 0, freeBytes = 0;
  for (var at = block + _firstCell; at + cell <= end; at += cell) {
    if (load32(at + _flags) & _marked != 0) {
      store32(at + _flags, _allocated);
      used += cell;
    } else {
      if (collectsAlways()) _fill(at, cell, _garbage);
      store64(at, 0);
      store64(at + _nextFree, free);
      free = at;
      freeBytes += cell;
    }
  }
  store64(block + _ownFree, free);
  store64(block + _freeBytes, freeBytes);
  return used;
}
