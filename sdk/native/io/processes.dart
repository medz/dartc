// Other programs that are started, and signals.
import 'dart:_heap/machine.dart' show load32, load64, store32, store64, store8;
import 'dart:_heap/objects.dart' show dataAddress;
import 'dart:ffi' show Int16, Int32, Int64, Native;

typedef _SpawnSignature = Int32 Function(
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
  Int64,
);

@Native<_SpawnSignature>(symbol: 'posix_spawn')
external int _spawn(
  int pid,
  int file,
  int actions,
  int attributes,
  int arguments,
  int environment,
);

@Native<_SpawnSignature>(symbol: 'posix_spawnp')
external int _spawnOnPath(
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

@Native<Int32 Function(Int64, Int32, Int64, Int32, Int32)>(
  symbol: 'posix_spawn_file_actions_addopen',
)
external int _addOpen(int actions, int file, int path, int flags, int mode);

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

const _noHang = 1, _setDescriptorFlags = 2, _closeOnRun = 1;
const _executePermission = 1, _executeBits = 0x49;
const _eNoEntry = 2, _eExecFormat = 8;
const _eAccess = 13;

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
  if (_makePipe(_buffer) < 0) throw _failure();
  final read = load32(_buffer), write = load32(_buffer + 4);
  if (_controlFile(read, _setDescriptorFlags, _closeOnRun) < 0 ||
      _controlFile(write, _setDescriptorFlags, _closeOnRun) < 0) {
    final error = _failure();
    _closeFile(read);
    _closeFile(write);
    throw error;
  }
  return (read, write);
}

/// What is needed to start a program.
final class _Start {
  final String executable;
  final List<String> arguments;
  final String? directory;
  final Map<String, String> environment;
  final bool runInShell;

  _Start(
    this.executable,
    List<String> arguments,
    this.directory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    this.runInShell,
  ) : arguments = List.of(arguments),
      environment = {
        ...?environment,
        if (includeParentEnvironment)
          for (final MapEntry(:key, :value) in Platform.environment.entries)
            if (environment == null || !environment.containsKey(key))
              key: value,
      };

  static List<String> _shellArguments(String executable, List<String> given) {
    String quoted(String text) => "'${text.replaceAll("'", "'\"'\"'")}'";
    return [
      '-c',
      [quoted(executable), ...given.map(quoted)].join(' '),
    ];
  }

  int _launch(int pid, int actions, int attributes, int envp) {
    const shell = '/bin/sh';
    final program = runInShell ? shell : executable;
    if (program.isEmpty) return _eNoEntry;
    final args = [
      program,
      ...(runInShell ? _shellArguments(executable, arguments) : arguments),
    ];
    final place = directory;
    final folder = place != null && !place.startsWith('/')
        ? '${Directory.current.path}/$place'
        : place;
    String inDirectory(String path) =>
        path.startsWith('/') ? path : '${folder ?? '.'}/$path';

    int launch(
      String target,
      List<String> arguments, {
      bool searchesPath = false,
    }) {
      final file = _cString(target);
      try {
        // Emulated x64 Linux can report a successful spawn for a failed exec.
        if (Platform.isLinux) {
          if (_statPath(file) < 0) return _errno;
          final mode = _statMode;
          if (mode & _modeType != _modeFile || mode & _executeBits == 0) {
            return _eAccess;
          }
          if (_access(file, _executePermission) < 0) return _errno;
        }
        final argv = _cStrings(arguments);
        try {
          return searchesPath
              ? _spawnOnPath(pid, file, actions, attributes, argv, envp)
              : _spawn(pid, file, actions, attributes, argv, envp);
        } finally {
          _freeStrings(argv);
        }
      } finally {
        _freeBytes(file);
      }
    }

    final searchesPath = !program.contains('/');
    if (!Platform.isLinux) {
      return searchesPath
          ? launch(program, args, searchesPath: true)
          : launch(inDirectory(program), args);
    }

    int launchLinux(String target) {
      final result = launch(target, args);
      return result == _eExecFormat
          ? launch(shell, [shell, target, ...args.skip(1)])
          : result;
    }

    if (!searchesPath) return launchLinux(inDirectory(program));
    var denied = false;
    for (final entry in (environment['PATH'] ?? '/bin:/usr/bin').split(':')) {
      final candidate = entry.isEmpty ? program : '$entry/$program';
      switch (launchLinux(inDirectory(candidate))) {
        case _eAccess:
          denied = true;
        case _eNoEntry || _eNotDirectory:
          break;
        case final result:
          return result;
      }
    }
    return denied ? _eAccess : _eNoEntry;
  }

  /// Starts the program with [files] as its standard ones, unless null, and
  /// gives its number. Throws a [ProcessException] if it cannot.
  int spawn(List<int>? files, {bool isDetached = false}) {
    void check(int code) {
      if (code != 0) {
        throw ProcessException(
          executable,
          arguments,
          _failure(code).message,
          code,
        );
      }
    }

    final actions = _allocateBytes(512), attributes = _allocateBytes(512);
    final signals = _allocateBytes(256);
    final place = directory == null ? 0 : _cString(directory!);
    final nullDevice = isDetached && files == null ? _cString('/dev/null') : 0;
    final envp = _cStrings([
      for (final MapEntry(:key, :value) in environment.entries) '$key=$value',
    ]);
    final number = _allocateBytes(8);
    final actionResult = _initActions(actions);
    final attributeResult = _initAttributes(attributes);
    try {
      check(actionResult);
      check(attributeResult);
      if (files != null) {
        for (final (i, file) in files.indexed) {
          check(_addDuplicate(actions, file, i));
        }
      } else if (nullDevice != 0) {
        for (var i = 0; i < 3; i++) {
          check(_addOpen(actions, i, nullDevice, _readWrite, 0));
        }
      }
      if (isDetached) check(_closeDetachedFiles(actions));
      if (place != 0) {
        if (Platform.isLinux) {
          if (_statPath(place) < 0) check(_errno);
          if (_statMode & _modeType != _modeDirectory) check(_eNotDirectory);
          if (_access(place, _executePermission) < 0) check(_errno);
        }
        check(_addDirectory(actions, place));
      }
      // What is ignored or blocked here is not there.
      _emptySignals(signals);
      check(_setSpawnMask(attributes, signals));
      _fillSignals(signals);
      check(_setSpawnDefaults(attributes, signals));
      check(
        _setSpawnFlags(
          attributes,
          _spawnSignalMask |
              _spawnSignalDefaults |
              (isDetached ? _spawnDetached : 0),
        ),
      );
      check(_launch(number, actions, attributes, envp));
      return load32(number);
    } finally {
      if (actionResult == 0) _destroyActions(actions);
      if (attributeResult == 0) _destroyAttributes(attributes);
      for (final address in [number, actions, attributes, signals]) {
        _freeBytes(address);
      }
      if (place != 0) _freeBytes(place);
      if (nullDevice != 0) _freeBytes(nullDevice);
      _freeStrings(envp);
    }
  }
}

/// Writes to a file that a program reads, as it is given.
final class _PipeConsumer implements StreamConsumer<List<int>> {
  final _SystemFile _target;
  _PipeConsumer(int file) : _target = _SystemFile(file + 1);

  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      if (data.isEmpty) continue;
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      final written = Completer<Object?>();
      _Tasks._instance.add(
        _WriteTask(written, _target, bytes, 0, bytes.length, null),
      );
      _checkForErrorResponse(await written.future, 'write failed', '');
    }
  }

  Future<void> close() async {
    _closeFile(_target.fd);
  }
}

/// The exit code if the child has ended. With no options, waits for it.
int? _waitForExit(int pid, int options) {
  int result;
  do {
    result = _waitFor(pid, _buffer, options);
  } while (result < 0 && _errno == _eInterrupted);
  if (result < 0) throw _failure();
  return result == 0 ? null : _codeOf(load32(_buffer));
}

/// Waits for a program to end.
final class _EndTask extends _Task {
  final int _pid;
  final _ChildProcess? _process;

  _EndTask(this._pid, [this._process]) : file = _whenEnded(_pid);

  final int file;

  bool get keepsAlive => _process?._ended != null;

  bool advance() {
    final code = _waitForExit(_pid, _noHang);
    if (code == null) return false;
    if (file >= 0) _closeFile(file);
    if (_process case final process?) {
      process._hasEnded = true;
      process._ended?.complete(code);
    }
    return true;
  }
}

/// Starts a child and transfers the parent's ends of its pipes to the caller.
({int pid, int stdin, int stdout, int stderr}) _startWithPipes(
  _Start start, {
  bool isDetached = false,
}) {
  final parent = <int>[], child = <int>[];
  try {
    final (input, writer) = _pipe();
    child.add(input);
    parent.add(writer);
    for (var i = 0; i < 2; i++) {
      final (reader, output) = _pipe();
      parent.add(reader);
      child.add(output);
    }
    const getFlags = 3, setFlags = 4;
    final flags = _controlFile(writer, getFlags, 0);
    if (flags < 0 || _controlFile(writer, setFlags, flags | _nonBlocking) < 0) {
      throw _failure();
    }
    final pid = start.spawn(child, isDetached: isDetached);
    return (pid: pid, stdin: writer, stdout: parent[1], stderr: parent[2]);
  } catch (_) {
    for (final file in parent) {
      _closeFile(file);
    }
    rethrow;
  } finally {
    for (final file in child) {
      _closeFile(file);
    }
  }
}

final class _ChildProcess implements Process {
  final int pid;
  final IOSink? _in;
  final Stream<List<int>>? _out, _error;
  final Completer<int>? _ended;
  bool _hasEnded = false;

  _ChildProcess._(this.pid, this._in, this._out, this._error, this._ended);

  static Future<Process> start(_Start start, ProcessStartMode mode) async {
    await null;
    final hasPipes =
        mode == ProcessStartMode.normal ||
        mode == ProcessStartMode.detachedWithStdio;
    final isDetached =
        mode == ProcessStartMode.detached ||
        mode == ProcessStartMode.detachedWithStdio;
    final pipes = hasPipes
        ? _startWithPipes(start, isDetached: isDetached)
        : null;
    final pid = pipes?.pid ?? start.spawn(null, isDetached: isDetached);
    final process = _ChildProcess._(
      pid,
      pipes == null ? null : IOSink(_PipeConsumer(pipes.stdin)),
      pipes == null ? null : _InputStream(pipes.stdout),
      pipes == null ? null : _InputStream(pipes.stderr),
      isDetached ? null : Completer<int>(),
    );
    _Tasks._instance.add(_EndTask(pid, process));
    return process;
  }

  Never _detached() => throw StateError('Process is detached');

  Future<int> get exitCode => _ended?.future ?? _detached();
  IOSink get stdin => _in ?? _detached();
  Stream<List<int>> get stdout => _out ?? _detached();
  Stream<List<int>> get stderr => _error ?? _detached();

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_hasEnded) return false;
    return _signal(pid, _nativeSignalNumber(signal)) == 0;
  }
}

/// Runs a program to its end, and gives what it wrote.
ProcessResult _runToEnd(
  _Start start,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
) {
  final pipes = _startWithPipes(start);
  _closeFile(pipes.stdin);
  final out = BytesBuilder(copy: false), error = BytesBuilder(copy: false);
  try {
    _readAll([(pipes.stdout, out), (pipes.stderr, error)]);
  } catch (_) {
    _Tasks._instance.add(_EndTask(pipes.pid));
    rethrow;
  }
  final code = _waitForExit(pipes.pid, 0)!;
  Object decoded(BytesBuilder bytes, Encoding? encoding) {
    final all = bytes.takeBytes();
    return encoding == null ? all : encoding.decode(all);
  }

  return ProcessResult(
    pipes.pid,
    code,
    decoded(out, stdoutEncoding),
    decoded(error, stderrEncoding),
  );
}

/// Reads each file into its builder until all end, then closes them.
void _readAll(List<(int, BytesBuilder)> files) {
  final table = _allocateBytes(files.length * _pollEntryBytes);
  final block = Uint8List(_blockSize);
  try {
    while (files.isNotEmpty) {
      for (final (index, (file, _)) in files.indexed) {
        _pollFile(table, index, file);
      }
      if (_pollFiles(table, files.length, -1) < 0) continue;
      for (var index = files.length - 1; index >= 0; index--) {
        if (!_pollReady(table, index)) continue;
        final (file, bytes) = files[index];
        final read = _readFile(file, dataAddress(block), block.length);
        if (read < 0) {
          if (_errno == _eInterrupted) continue;
          throw _failure();
        }
        if (read == 0) {
          _closeFile(file);
          files.removeAt(index);
        } else {
          bytes.add(block.sublist(0, read));
        }
      }
    }
  } finally {
    for (final (file, _) in files) {
      _closeFile(file);
    }
    _freeBytes(table);
  }
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
  ]) => _signal(pid, _nativeSignalNumber(signal)) == 0;
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
