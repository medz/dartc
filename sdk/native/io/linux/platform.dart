@Native<Int32 Function(Int64)>(symbol: 'uname')
external int _systemNames(int result);

@Native<Int64 Function(Int64, Int64)>(symbol: 'dlsym')
external int _symbolAddress(int library, int name);

const _systemName = 'linux', _processorsName = 84;

String _systemVersion() {
  // Each name has as many bytes.
  const bytes = 65, system = 0, release = 2, version = 3;
  if (_systemNames(_buffer) < 0) return '';
  String name(int index) => _textAt(_buffer + index * bytes);
  return '${name(system)} ${name(release)} ${name(version)}';
}

/// Where the program is, if that is known.
String? _programFile() {
  final link = FileSystemEntity._toUtf8Array('/proc/self/exe');
  final length = _readLink(dataAddress(link), _buffer, _bufferBytes);
  return length < 0
      ? null
      : utf8.decode(_bytesAt(_buffer, length), allowMalformed: true);
}

int _environmentStart() {
  final name = FileSystemEntity._toUtf8Array('environ');
  return load64(_symbolAddress(0, dataAddress(name)));
}

String _language() => Platform.environment['LANG'] ?? 'en_US';

@Native<Int32 Function()>(symbol: 'getpagesize')
external int _pageBytes();

/// What the largest resident size is counted in.
const _largestUnit = 1024;

int _residentBytes() {
  // The second number is how many pages are resident.
  final path = FileSystemEntity._toUtf8Array('/proc/self/statm');
  final file = _openPath(dataAddress(path), 0, 0);
  if (file < 0) throw _failure();
  final count = _readFile(file, _buffer, _bufferBytes);
  _closeFile(file);
  if (count < 0) throw _failure();
  final [_, pages, ...] = latin1.decode(_bytesAt(_buffer, count)).split(' ');
  return int.parse(pages) * _pageBytes();
}

@Native<Int64 Function(Int64, VarArgs<(Int64, Int64)>)>(symbol: 'syscall')
external int _systemCall(int number, int first, int second);

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'sigprocmask')
external int _maskSignals(int how, int set, int old);

@Native<Int32 Function(Int32, Int64, Int32)>(symbol: 'signalfd')
external int _openSignalFile(int file, int set, int flags);

const _spawnSignalDefaults = 0x04, _spawnSignalMask = 0x08;
const _spawnSession = 0x80;

/// A file that is ready when the program [pid] ends, or -1 if there is none.
int _whenEnded(int pid) {
  const openProcess = 434;
  final file = _systemCall(openProcess, pid, 0);
  return file < 0 ? -1 : file;
}

/// Does [how] with the set of [signal] alone.
void _withSignalSet(int signal, void Function(int set) use) {
  final set = _allocateBytes(128);
  _emptySignals(set);
  _addSignal(set, signal);
  use(set);
  _freeBytes(set);
}

/// A file that is ready when [signal] comes, which then does nothing else.
int _signalFile(int signal) {
  const block = 0, noWait = 0x800, closeOnExec = 0x80000;
  var file = -1;
  _withSignalSet(signal, (set) {
    _maskSignals(block, set, 0);
    file = _openSignalFile(-1, set, noWait | closeOnExec);
  });
  return file;
}

/// How many times the signal of [file] came since this was last asked.
int _signalsOf(int file) {
  const record = 128;
  final buffer = _allocateBytes(record);
  var count = 0;
  while (_readFile(file, buffer, record) == record) {
    count++;
  }
  _freeBytes(buffer);
  return count;
}

void _endSignalFile(int signal, int file) {
  const unblock = 1;
  _closeFile(file);
  _withSignalSet(signal, (set) => _maskSignals(unblock, set, 0));
}
