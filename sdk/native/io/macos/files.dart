// Files, as macOS has them.
@Native<Int64 Function()>(symbol: '__error')
external int _errorAddress();

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'strerror_r')
external int _errorText(int code, int buffer, int size);

@Native<Int32 Function(Int32, Int64)>(symbol: 'fstat')
external int _statFileTo(int file, int result);

@Native<Int32 Function(Int64, Int64)>(symbol: 'stat')
external int _statPathTo(int path, int result);

@Native<Int32 Function(Int64, Int64)>(symbol: 'lstat')
external int _statLinkTo(int path, int result);

@Native<Int32 Function(Int64, Int64, Int64, Int32)>(symbol: 'copyfile')
external int _copyPath(int from, int to, int state, int flags);

const _createFlag = 0x200, _truncateFlag = 0x400, _exclusiveFlag = 0x800;
const _closeOnExec = 0x1000000;
const _eOverflow = 84;

int _statFile(int file) => _statFileTo(file, _buffer);
int _statPath(int path) => _statPathTo(path, _buffer);
int _statLink(int path) => _statLinkTo(path, _buffer);

/// The type and mode of what [_statPath] and the like found.
int get _statMode => load16(_buffer + 4);
int get _statDevice => load32(_buffer);
int get _statNumber => load64(_buffer + 8);
int get _statAccessed => _microseconds(_buffer + 32);
int get _statModified => _microseconds(_buffer + 48);
int get _statChanged => _microseconds(_buffer + 64);
int get _statSize => load64(_buffer + 96);

/// Where [_readDirectory] gives names.
const _entryName = 21;

int _copyFile(Uint8List from, Uint8List to) {
  const all = 15;
  return _copyPath(dataAddress(from), dataAddress(to), 0, all);
}

const _setLock = 8, _setLockWaiting = 9;
const _sharedLock = 1, _noLock = 2, _exclusiveLock = 3;

void _storeLock(int type, int start, int length) {
  store64(_buffer, start);
  store64(_buffer + 8, length);
  store32(_buffer + 16, 0);
  store16(_buffer + 20, type);
  store16(_buffer + 22, _fromStart);
}

/// What tells where temporary files are.
const _temporaryVariables = ['TMPDIR'];

const _echoBit = 8, _echoNewlineBit = 0x10, _lineBit = 0x100;
const _sizeOfWindow = 0x40087468;

/// The modes of the terminal that were read.
int _loadModes() => load64(_buffer + 24);
void _storeModes(int modes) => store64(_buffer + 24, modes);
