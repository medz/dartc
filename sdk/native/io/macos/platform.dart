import 'dart:ffi' show DynamicLibrary, DynamicLibraryExtension, Uint8;

@Native<Int64 Function()>(symbol: '_NSGetEnviron')
external int _environmentAddress();

@Native<Int32 Function(Int64, Int64, Int64, Int64, Int64)>(
  symbol: 'sysctlbyname',
)
external int _systemValue(int name, int buffer, int size, int set, int count);

@Native<Int32 Function(Int64, Int64)>(symbol: '_NSGetExecutablePath')
external int _programPath(int buffer, int size);

const _systemName = 'macos', _processorsName = 58;

/// What the system calls [name].
String _systemText(String name) {
  final bytes = FileSystemEntity._toUtf8Array(name);
  store64(_buffer, _bufferBytes - 8);
  final result = _systemValue(dataAddress(bytes), _buffer + 8, _buffer, 0, 0);
  return result < 0 ? '' : _textAt(_buffer + 8);
}

String _systemVersion() =>
    'Version ${_systemText('kern.osproductversion')} '
    '(Build ${_systemText('kern.osversion')})';

/// Where the program is, if that is known.
String? _programFile() {
  store32(_buffer, _bufferBytes - 8);
  return _programPath(_buffer + 8, _buffer) < 0 ? null : _textAt(_buffer + 8);
}

int _environmentStart() => load64(_environmentAddress());

String _language() => _preferredLanguage() ?? 'en-US';

/// The first language that the user wants, if that is known.
String? _preferredLanguage() {
  const path =
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation';
  const isUtf8 = 0x08000100;
  final library = DynamicLibrary.open(path);
  final languages = library.lookupFunction<Int64 Function(), int Function()>(
    'CFLocaleCopyPreferredLanguages',
  )();
  if (languages == 0) return null;
  final count = library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'CFArrayGetCount',
      )(languages);
  if (count == 0) return null;
  final first = library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'CFArrayGetValueAtIndex',
      )(languages, 0);
  final result = library
      .lookupFunction<
        Uint8 Function(Int64, Int64, Int64, Uint32),
        int Function(int, int, int, int)
      >('CFStringGetCString')(first, _buffer, _bufferBytes, isUtf8);
  return result == 0 ? null : _textAt(_buffer);
}

/// The task of the program.
@Native<Uint32>(symbol: 'mach_task_self_')
external int _task;

@Native<Int32 Function(Uint32, Int32, Int64, Int64)>(symbol: 'task_info')
external int _taskInfo(int task, int flavor, int info, int count);

/// What the largest resident size is counted in.
const _largestUnit = 1;

int _residentBytes() {
  // `struct mach_task_basic_info` has 12 words; the resident size is second.
  const basicInfo = 20, words = 12, resident = 8;
  store32(_buffer, words);
  final result = _taskInfo(_task, basicInfo, _buffer + 8, _buffer);
  if (result != 0) throw OSError('task_info failed', result);
  return load64(_buffer + 8 + resident);
}

@Native<Int32 Function()>(symbol: 'kqueue')
external int _kernelQueue();

@Native<Int32 Function(Int32, Int64, Int32, Int64, Int32, Int64)>(
  symbol: 'kevent',
)
external int _kernelEvents(
  int queue,
  int changes,
  int changeCount,
  int events,
  int eventCount,
  int timeout,
);

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'sigaction')
external int _setSignalAction(int signal, int action, int previous);

const _spawnSignalDefaults = 0x04, _spawnSignalMask = 0x08;
const _spawnDetached = 0x0400 | 0x4000;
const _nonBlocking = 0x0004, _eWouldBlock = 35;

// POSIX_SPAWN_CLOEXEC_DEFAULT closes descriptors not mapped by the actions.
int _closeDetachedFiles(int _) => 0;

/// The numbers used by Darwin for the SDK's signal constants.
int _nativeSignalNumber(ProcessSignal signal) => switch (signal) {
  ProcessSignal.sigbus => 10,
  ProcessSignal.sigusr1 => 30,
  ProcessSignal.sigusr2 => 31,
  ProcessSignal.sigchld => 20,
  ProcessSignal.sigcont => 19,
  ProcessSignal.sigstop => 17,
  ProcessSignal.sigtstp => 18,
  ProcessSignal.sigurg => 16,
  ProcessSignal.sigpoll => -1,
  ProcessSignal.sigsys => 12,
  _ => signal.signalNumber,
};

/// A queue of the kernel that tells about [ident] of [filter].
int _kernelQueueFor(int ident, int filter, int flags, int notes) {
  final queue = _kernelQueue();
  if (queue < 0) return -1;
  final event = _buffer;
  store64(event, ident);
  store16(event + 8, filter & 0xffff);
  store16(event + 10, flags);
  store32(event + 12, notes);
  store64(event + 16, 0);
  store64(event + 24, 0);
  final result = _kernelEvents(queue, event, 1, 0, 0, 0);
  if (result >= 0) return queue;
  _closeFile(queue);
  return -1;
}

/// A file that is ready when the program [pid] ends, or -1 if it has.
int _whenEnded(int pid) {
  const process = -5, add = 0x1, once = 0x10, exit = 0x80000000;
  return _kernelQueueFor(pid, process, add | once, exit);
}

/// A file that is ready when [signal] comes, which then does nothing else.
_SignalRegistration? _signalFile(int signal) {
  const kind = -6, add = 0x1, ignore = 1;
  final previous = _buffer + 16;
  store64(_buffer, ignore);
  store64(_buffer + 8, 0);
  if (_setSignalAction(signal, _buffer, previous) < 0) return null;
  final handler = load64(previous), options = load64(previous + 8);
  return _SignalRegistration.opened(_kernelQueueFor(signal, kind, add, 0), () {
    store64(_buffer, handler);
    store64(_buffer + 8, options);
    _setSignalAction(signal, _buffer, 0);
  });
}

/// How many times the signal of [file] came since this was last asked.
int _signalsOf(int file) {
  final event = _buffer;
  // It does not wait.
  store64(event + 32, 0);
  store64(event + 40, 0);
  final result = _kernelEvents(file, 0, 0, event, 1, event + 32);
  return result > 0 ? load64(event + 16) : 0;
}
