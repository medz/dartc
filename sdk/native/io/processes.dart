// Other programs that are started, and signals.
import 'dart:_heap/machine.dart' show load32, load64, store32, store64, store8;
import 'dart:_heap/objects.dart' show dataAddress;
import 'dart:ffi' show Int16, Int32, Int64, Native, Void;

@Native<Int32 Function(Int64, Int64, Int64, Int64, Int64, Int64)>(
  symbol: 'posix_spawnp',
)
external int _spawn(
  int pid,
  int file,
  int actions,
  int attributes,
  int arguments,
  int environment,
);

@Native<Int32 Function(Int64)>(symbol: 'posix_spawn_file_actions_init')
external int _initActions(int actions);

@Native<Int32 Function(Int64)>(symbol: 'posix_spawn_file_actions_destroy')
external int _destroyActions(int actions);

@Native<Int32 Function(Int64, Int32, Int32)>(
  symbol: 'posix_spawn_file_actions_adddup2',
)
external int _addDuplicate(int actions, int from, int to);

@Native<Int32 Function(Int64, Int32)>(
  symbol: 'posix_spawn_file_actions_addclose',
)
external int _addClose(int actions, int file);

@Native<Int32 Function(Int64, Int64)>(
  symbol: 'posix_spawn_file_actions_addchdir_np',
)
external int _addDirectory(int actions, int path);

@Native<Int32 Function(Int64)>(symbol: 'posix_spawnattr_init')
external int _initAttributes(int attributes);

@Native<Int32 Function(Int64)>(symbol: 'posix_spawnattr_destroy')
external int _destroyAttributes(int attributes);

@Native<Int32 Function(Int64, Int16)>(symbol: 'posix_spawnattr_setflags')
external int _setSpawnFlags(int attributes, int flags);

@Native<Int32 Function(Int64, Int64)>(symbol: 'posix_spawnattr_setsigmask')
external int _setSpawnMask(int attributes, int mask);

@Native<Int32 Function(Int64, Int64)>(symbol: 'posix_spawnattr_setsigdefault')
external int _setSpawnDefaults(int attributes, int signals);

@Native<Int32 Function(Int64)>(symbol: 'sigemptyset')
external int _emptySignals(int set);

@Native<Int32 Function(Int64)>(symbol: 'sigfillset')
external int _fillSignals(int set);

@Native<Int32 Function(Int64, Int32)>(symbol: 'sigaddset')
external int _addSignal(int set, int signal);

@Native<Int32 Function(Int32, Int64, Int32)>(symbol: 'waitpid')
external int _waitFor(int pid, int status, int options);

@Native<Int32 Function(Int32, Int32)>(symbol: 'kill')
external int _signal(int pid, int signal);

@Native<Int32 Function(Int64, Int32)>(symbol: 'access')
external int _access(int path, int mode);

@Native<Void Function(Int64)>(symbol: 'free')
external void _freeBytes(int address);

const _noHang = 1, _setDescriptorFlags = 2, _closeOnRun = 1;

/// The bytes of [text] that a 0 ends, outside the heap.
int _cString(String text) {
  final bytes = utf8.encode(text);
  final address = _allocateBytes(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    store8(address + i, bytes[i]);
  }
  store8(address + bytes.length, 0);
  return address;
}

/// An array of [texts] that null ends, outside the heap.
int _cStrings(List<String> texts) {
  final array = _allocateBytes((texts.length + 1) * 8);
  for (var i = 0; i < texts.length; i++) {
    store64(array + i * 8, _cString(texts[i]));
  }
  store64(array + texts.length * 8, 0);
  return array;
}

void _freeStrings(int array) {
  for (var at = array; load64(at) != 0; at += 8) {
    _freeBytes(load64(at));
  }
  _freeBytes(array);
}

/// The code that the status of a program that ended tells.
int _codeOf(int status) {
  final signal = status & 0x7f;
  return signal == 0 ? status >> 8 & 0xff : -signal;
}

/// A pipe, whose ends are not given to programs that are started.
(int, int) _pipe() {
  final ends = _allocateBytes(8);
  if (_makePipe(ends) < 0) {
    _freeBytes(ends);
    throw _failure();
  }
  final read = load32(ends), write = load32(ends + 4);
  _freeBytes(ends);
  _controlFile(read, _setDescriptorFlags, _closeOnRun);
  _controlFile(write, _setDescriptorFlags, _closeOnRun);
  return (read, write);
}

/// What is needed to start a program.
final class _Start {
  final String path;
  final List<String> arguments;
  final String? directory;
  final List<String> environment;

  _Start(
    String executable,
    List<String> given,
    this.directory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
  ) : path = runInShell ? '/bin/sh' : executable,
      arguments = runInShell ? _shellArguments(executable, given) : given,
      environment = [
        for (final MapEntry(:key, :value) in (environment ?? const {}).entries)
          '$key=$value',
        if (includeParentEnvironment)
          for (final MapEntry(:key, :value) in Platform.environment.entries)
            if (environment == null || !environment.containsKey(key))
              '$key=$value',
      ];

  static List<String> _shellArguments(String executable, List<String> given) {
    String quoted(String text) => "'${text.replaceAll("'", "'\"'\"'")}'";
    return [
      '-c',
      [quoted(executable), ...given.map(quoted)].join(' '),
    ];
  }

  /// The error that starting the program would give, if it is known to.
  int? _cannotRun() {
    const executable = 1, noEntry = 2;
    bool runs(String path) {
      final text = _cString(path);
      final result = _access(text, executable);
      _freeBytes(text);
      return result == 0;
    }

    if (directory case final place?) {
      final bytes = FileSystemEntity._toUtf8Array(place);
      if (_anyTypeAt(bytes, true) != _typeDirectory) return noEntry;
    }
    if (path.contains('/')) return null;
    final paths = Platform.environment['PATH'] ?? '/usr/bin:/bin';
    return paths.split(':').any((at) => runs('${at.isEmpty ? '.' : at}/$path'))
        ? null
        : noEntry;
  }

  /// Starts the program with [files] as its standard ones, unless null, and
  /// gives its number. Throws a [ProcessException] if it cannot.
  int spawn(
    String executable,
    List<String> given,
    List<int>? files, {
    bool isDetached = false,
    List<int> others = const [],
  }) {
    // Not all systems tell when the program cannot be run, so this is found
    // out first.
    if (_cannotRun() case final code?) {
      throw ProcessException(executable, given, _failure(code).message, code);
    }
    final actions = _allocateBytes(512), attributes = _allocateBytes(512);
    final signals = _allocateBytes(256);
    _initActions(actions);
    _initAttributes(attributes);
    if (files != null) {
      for (final (i, file) in files.indexed) {
        _addDuplicate(actions, file, i);
      }
    }
    // Ends of pipes that are this program's.
    for (final file in {...?files, ...others}) {
      if (file > 2) _addClose(actions, file);
    }
    final place = directory == null ? 0 : _cString(directory!);
    if (place != 0) _addDirectory(actions, place);
    // What is ignored or blocked here is not there.
    _emptySignals(signals);
    _setSpawnMask(attributes, signals);
    _fillSignals(signals);
    _setSpawnDefaults(attributes, signals);
    _setSpawnFlags(
      attributes,
      _spawnSignalMask |
          _spawnSignalDefaults |
          (isDetached ? _spawnSession : 0),
    );
    final file = _cString(path);
    final argv = _cStrings([path, ...arguments]);
    final envp = _cStrings(environment);
    final number = _allocateBytes(8);
    final result = _spawn(number, file, actions, attributes, argv, envp);
    final pid = load32(number);
    for (final address in [file, number, actions, attributes, signals]) {
      _freeBytes(address);
    }
    if (place != 0) _freeBytes(place);
    _freeStrings(argv);
    _freeStrings(envp);
    if (result != 0) {
      throw ProcessException(
        executable,
        given,
        _failure(result).message,
        result,
      );
    }
    return pid;
  }
}

/// Writes to a file that a program reads, as it is given.
final class _PipeConsumer implements StreamConsumer<List<int>> {
  final int _file;
  _PipeConsumer(this._file);

  void _write(List<int> data) {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    var at = 0;
    while (at < bytes.length) {
      final count = _writeFile(
        _file,
        dataAddress(bytes) + at,
        bytes.length - at,
      );
      if (count < 0) {
        if (_errno == _eInterrupted) continue;
        throw _failure();
      }
      at += count;
    }
  }

  Future addStream(Stream<List<int>> stream) => stream.forEach(_write);

  Future close() {
    _closeFile(_file);
    return Future.value();
  }
}

/// Waits for a program to end.
final class _EndTask extends _Task {
  final int _pid;
  int _ready;
  final Completer<int> _ended;

  _EndTask(this._pid, this._ended) : _ready = _whenEnded(_pid);

  int get file => _ready;

  bool advance() {
    final status = _allocateBytes(8);
    final result = _waitFor(_pid, status, _noHang);
    final code = _codeOf(load32(status));
    _freeBytes(status);
    if (result == 0) return false;
    if (_ready >= 0) _closeFile(_ready);
    _ready = -1;
    _ended.complete(code);
    return true;
  }
}

final class _ChildProcess implements Process {
  final int pid;
  final IOSink? _in;
  final Stream<List<int>>? _out, _error;
  final Completer<int>? _ended;
  bool _hasEnded = false;

  _ChildProcess._(this.pid, this._in, this._out, this._error, this._ended) {
    _ended?.future.then((_) => _hasEnded = true);
  }

  static Future<Process> start(
    String executable,
    List<String> arguments,
    _Start start,
    ProcessStartMode mode,
  ) async {
    await null;
    final hasPipes =
        mode == ProcessStartMode.normal ||
        mode == ProcessStartMode.detachedWithStdio;
    final isDetached =
        mode == ProcessStartMode.detached ||
        mode == ProcessStartMode.detachedWithStdio;
    final ends = hasPipes ? [_pipe(), _pipe(), _pipe()] : null;
    final int pid;
    try {
      pid = start.spawn(
        executable,
        arguments,
        ends == null ? null : [ends[0].$1, ends[1].$2, ends[2].$2],
        isDetached: isDetached,
        others: ends == null ? const [] : [ends[0].$2, ends[1].$1, ends[2].$1],
      );
    } finally {
      if (ends != null) {
        _closeFile(ends[0].$1);
        _closeFile(ends[1].$2);
        _closeFile(ends[2].$2);
      }
    }
    final ended = isDetached ? null : Completer<int>();
    if (ended != null) _Tasks._instance.add(_EndTask(pid, ended));
    return _ChildProcess._(
      pid,
      ends == null ? null : IOSink(_PipeConsumer(ends[0].$2)),
      ends == null ? null : _InputStream(ends[1].$1),
      ends == null ? null : _InputStream(ends[2].$1),
      ended,
    );
  }

  Never _detached() => throw StateError('Process is detached');

  Future<int> get exitCode => _ended?.future ?? _detached();
  IOSink get stdin => _in ?? _detached();
  Stream<List<int>> get stdout => _out ?? _detached();
  Stream<List<int>> get stderr => _error ?? _detached();

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_hasEnded) return false;
    return _signal(pid, signal.signalNumber) == 0;
  }
}

/// Runs a program to its end, and gives what it wrote.
ProcessResult _runToEnd(
  String executable,
  List<String> arguments,
  _Start start,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
) {
  final ends = [_pipe(), _pipe(), _pipe()];
  final int pid;
  try {
    pid = start.spawn(
      executable,
      arguments,
      [ends[0].$1, ends[1].$2, ends[2].$2],
      others: [ends[0].$2, ends[1].$1, ends[2].$1],
    );
  } finally {
    _closeFile(ends[0].$1);
    _closeFile(ends[1].$2);
    _closeFile(ends[2].$2);
    _closeFile(ends[0].$2);
  }
  final out = BytesBuilder(copy: false), error = BytesBuilder(copy: false);
  _readAll([(ends[1].$1, out), (ends[2].$1, error)]);
  final status = _allocateBytes(8);
  while (_waitFor(pid, status, 0) < 0 && _errno == _eInterrupted) {}
  final code = _codeOf(load32(status));
  _freeBytes(status);
  Object decoded(BytesBuilder bytes, Encoding? encoding) {
    final all = bytes.takeBytes();
    return encoding == null ? all : encoding.decode(all);
  }

  return ProcessResult(
    pid,
    code,
    decoded(out, stdoutEncoding),
    decoded(error, stderrEncoding),
  );
}

/// Reads each file into its builder until all end, then closes them.
void _readAll(List<(int, BytesBuilder)> files) {
  const setBytes = 128;
  final sets = _allocateBytes(setBytes), block = Uint8List(_blockSize);
  final open = [...files];
  while (open.isNotEmpty) {
    for (var i = 0; i < setBytes; i += 8) {
      store64(sets + i, 0);
    }
    var count = 0;
    for (final (file, _) in open) {
      store8(sets + (file >> 3), load8(sets + (file >> 3)) | 1 << (file & 7));
      if (file >= count) count = file + 1;
    }
    if (_select(count, sets, 0, 0, 0) < 0) continue;
    for (final entry in [...open]) {
      final (file, bytes) = entry;
      if (load8(sets + (file >> 3)) >> (file & 7) & 1 == 0) continue;
      final read = _readFile(file, dataAddress(block), block.length);
      if (read < 0 && _errno == _eInterrupted) continue;
      if (read <= 0) {
        _closeFile(file);
        open.remove(entry);
      } else {
        bytes.add(Uint8List.sublistView(block, 0, read).sublist(0));
      }
    }
  }
  _freeBytes(sets);
}

@patch
class Process {
  @patch
  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => _ChildProcess.start(
    executable,
    arguments,
    _Start(
      executable,
      arguments,
      workingDirectory,
      environment,
      includeParentEnvironment,
      runInShell,
    ),
    mode,
  );

  @patch
  static bool killPid(
    int pid, [
    ProcessSignal signal = ProcessSignal.sigterm,
  ]) => _signal(pid, signal.signalNumber) == 0;
}

@patch
ProcessResult _runNonInteractiveProcessSync(
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
) => _runToEnd(
  executable,
  arguments,
  _Start(
    executable,
    arguments,
    workingDirectory,
    environment,
    includeParentEnvironment,
    runInShell,
  ),
  stdoutEncoding,
  stderrEncoding,
);
