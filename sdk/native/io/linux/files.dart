// Files, as Linux has them.
@Native<Int64 Function()>(symbol: '__errno_location')
external int _errorAddress();

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: '__xpg_strerror_r')
external int _errorText(int code, int buffer, int size);

@Native<Int32 Function(Int32, Int64, Int32, Uint32, Int64)>(symbol: 'statx')
external int _statAt(int place, int path, int flags, int mask, int result);

const _createFlag = 0x40, _truncateFlag = 0x200, _exclusiveFlag = 0x80;
const _closeOnExec = 0x80000;
const _eOverflow = 75;

/// The directory that paths start at.
const _here = -100;
const _basicFacts = 0x7ff;

int _statFile(int file) {
  const pathIsEmpty = 0x1000, path = 1024;
  store8(_buffer + path, 0);
  return _statAt(file, _buffer + path, pathIsEmpty, _basicFacts, _buffer);
}

int _statPath(int path) => _statAt(_here, path, 0, _basicFacts, _buffer);

int _statLink(int path) {
  const notFollowing = 0x100;
  return _statAt(_here, path, notFollowing, _basicFacts, _buffer);
}

/// The type and mode of what [_statPath] and the like found.
int get _statMode => load16(_buffer + 28);
int get _statDevice => load64(_buffer + 136);
int get _statNumber => load64(_buffer + 32);
int get _statAccessed => _microseconds(_buffer + 64);
int get _statModified => _microseconds(_buffer + 112);
int get _statChanged => _microseconds(_buffer + 96);
int get _statSize => load64(_buffer + 40);

/// Where [_readDirectory] gives names.
const _entryName = 19;

int _copyFile(Uint8List from, Uint8List to) {
  final source = _openPath(dataAddress(from), _readOnly | _closeOnExec, 0);
  if (source < 0) return source;
  final mode = _statFile(source) < 0 ? 0x1b6 : _statMode & 0xfff;
  const flags = _writeOnly | _createFlag | _truncateFlag | _closeOnExec;
  final target = _openPath(dataAddress(to), flags, mode);
  var result = target;
  if (target >= 0) {
    result = _copyContents(source, target);
    final code = _errno;
    _closeFile(target);
    if (result < 0) _unlink(dataAddress(to));
    _setErrno(code);
  }
  final code = _errno;
  _closeFile(source);
  _setErrno(code);
  return result;
}

int _copyContents(int source, int target) {
  while (true) {
    final count = _readFile(source, _buffer, _bufferBytes);
    if (count <= 0) return count;
    for (var at = 0; at < count;) {
      final written = _writeFile(target, _buffer + at, count - at);
      if (written < 0) return written;
      at += written;
    }
  }
}

const _setLock = 6, _setLockWaiting = 7;
const _sharedLock = 0, _noLock = 2, _exclusiveLock = 1;

void _storeLock(int type, int start, int length) {
  store16(_buffer, type);
  store16(_buffer + 2, _fromStart);
  store64(_buffer + 8, start);
  store64(_buffer + 16, length);
  store32(_buffer + 24, 0);
}

/// What tells where temporary files are.
const _temporaryVariables = ['TMPDIR', 'TMP'];

const _echoBit = 8, _echoNewlineBit = 0x40, _lineBit = 2;
const _sizeOfWindow = 0x5413;

/// The modes of the terminal that were read.
int _loadModes() => load32(_buffer + 12);
void _storeModes(int modes) => store32(_buffer + 12, modes);
