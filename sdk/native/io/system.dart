// What the system does for programs. Paths are bytes that a 0 ends.
import 'dart:_heap/machine.dart' show load32, load64, load8, store32, store64;
import 'dart:_heap/machine.dart' show store8;
import 'dart:_heap/objects.dart' show dataAddress, load16, store16;
import 'dart:ffi' show Int32, Int64, Native, Uint16, Uint32, VarArgs, Void;

@Native<Int64 Function(Int64)>(symbol: 'malloc')
external int _allocateBytes(int bytes);

@Native<Int32 Function(Int64, Int32, VarArgs<(Int32,)>)>(symbol: 'open')
external int _openPath(int path, int flags, int mode);

@Native<Int32 Function(Int32)>(symbol: 'close')
external int _closeFile(int file);

@Native<Int64 Function(Int32, Int64, Int64)>(symbol: 'read')
external int _readFile(int file, int address, int count);

@Native<Int64 Function(Int32, Int64, Int64)>(symbol: 'write')
external int _writeFile(int file, int address, int count);

@Native<Int64 Function(Int32, Int64, Int32)>(symbol: 'lseek')
external int _seekFile(int file, int offset, int origin);

@Native<Int32 Function(Int32, Int64)>(symbol: 'ftruncate')
external int _truncateFile(int file, int length);

@Native<Int32 Function(Int32)>(symbol: 'fsync')
external int _syncFile(int file);

@Native<Int32 Function(Int32, Int32, VarArgs<(Int64,)>)>(symbol: 'fcntl')
external int _controlFile(int file, int request, int address);

@Native<Int32 Function(Int64)>(symbol: 'pipe')
external int _makePipe(int files);

@Native<Int32 Function(Int64, Int64)>(symbol: 'utimes')
external int _setTimes(int path, int times);

@Native<Int32 Function(Int64)>(symbol: 'unlink')
external int _unlink(int path);

@Native<Int32 Function(Int64, Int64)>(symbol: 'rename')
external int _renamePath(int from, int to);

@Native<Int32 Function(Int64, Int64)>(symbol: 'symlink')
external int _makeLink(int target, int path);

@Native<Int64 Function(Int64, Int64, Int64)>(symbol: 'readlink')
external int _readLink(int path, int buffer, int size);

@Native<Int64 Function(Int64, Int64)>(symbol: 'realpath')
external int _realPath(int path, int buffer);

@Native<Int32 Function(Int64, Uint16)>(symbol: 'mkdir')
external int _makeDirectory(int path, int mode);

@Native<Int32 Function(Int64)>(symbol: 'rmdir')
external int _removeDirectory(int path);

@Native<Int64 Function(Int64)>(symbol: 'mkdtemp')
external int _makeTemporary(int path);

@Native<Int64 Function(Int64, Int64)>(symbol: 'getcwd')
external int _currentDirectory(int buffer, int size);

@Native<Int32 Function(Int64)>(symbol: 'chdir')
external int _changeDirectory(int path);

@Native<Int64 Function(Int64)>(symbol: 'opendir')
external int _openDirectory(int path);

@Native<Int64 Function(Int64)>(symbol: 'readdir')
external int _readDirectory(int directory);

@Native<Int32 Function(Int64)>(symbol: 'closedir')
external int _closeDirectory(int directory);

@Native<Int32 Function(Int32, Int64, Int64, Int64, Int64)>(symbol: 'select')
external int _select(int count, int reading, int writing, int failed, int time);

const _eInterrupted = 4, _eNotDirectory = 20, _eIsDirectory = 21;
const _eInvalid = 22;

const _bufferBytes = 4096;

/// Memory for what is needed only until the next call.
final int _buffer = _allocateBytes(_bufferBytes);

int get _errno => load32(_errorAddress());

void _setErrno(int code) => store32(_errorAddress(), code);

/// The error that [code] stands for, or else the last one.
OSError _failure([int? code]) {
  final number = code ?? _errno;
  _errorText(number, _buffer, _bufferBytes);
  return OSError(_textAt(_buffer), number);
}

/// [value], or the last error if [result] is negative.
Object _valueIf(int result, Object value) => result < 0 ? _failure() : value;

/// The number of bytes at [address] before a 0.
int _lengthAt(int address) {
  var length = 0;
  while (load8(address + length) != 0) {
    length++;
  }
  return length;
}

Uint8List _bytesAt(int address, int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = load8(address + i);
  }
  return bytes;
}

String _textAt(int address) =>
    utf8.decode(_bytesAt(address, _lengthAt(address)), allowMalformed: true);

int _microseconds(int address) =>
    load64(address) * 1000000 + load64(address + 8) ~/ 1000;

/// The numbers of [FileSystemEntityType], and what modes mean.
const _typeFile = 0, _typeDirectory = 1, _typeLink = 2, _typeSocket = 3;
const _typePipe = 4, _typeNone = 5;

/// Something else.
const _typeDevice = 6;

const _modeType = 0xf000, _modePipe = 0x1000, _modeDirectory = 0x4000;
const _modeFile = 0x8000, _modeLink = 0xa000, _modeSocket = 0xc000;

int _typeOf(int mode) => switch (mode & _modeType) {
  _modeDirectory => _typeDirectory,
  _modeLink => _typeLink,
  _modeSocket => _typeSocket,
  _modePipe => _typePipe,
  _modeFile => _typeFile,
  _ => _typeDevice,
};

/// The type that programs are told instead of [type].
int _told(int type) => type == _typeDevice ? _typeNone : type;

int _typeAt(Uint8List path, bool followLinks) =>
    _told(_anyTypeAt(path, followLinks));

/// What is at [path], which can be a link only if [followLinks] is false.
int _anyTypeAt(Uint8List path, bool followLinks) {
  final address = dataAddress(path);
  final result = followLinks ? _statPath(address) : _statLink(address);
  return result == 0 ? _typeOf(_statMode) : _typeNone;
}

@Native<Int32 Function(Int32, Int32)>(symbol: 'dup2')
external int _duplicateFile(int from, int to);
