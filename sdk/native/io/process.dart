import 'dart:_heap/objects.dart' as heap show exit, pause;

@Native<Int32 Function()>(symbol: 'getpid')
external int _processNumber();

int _codeAtEnd = 0;

/// The code that the program ends with.
int _exitCode() => _codeAtEnd;

/// The directory that paths start at.
Uri _currentUri() => _uriBaseClosure();

@patch
class _ProcessUtils {
  @patch
  static Never _exit(int status) => heap.exit(status);

  @patch
  static void _setExitCode(int status) {
    _codeAtEnd = status;
  }

  @patch
  static int _getExitCode() => _codeAtEnd;

  @patch
  static void _sleep(int millis) {
    // The system does not wait for longer at once.
    const most = 1000;
    for (var rest = millis; rest > 0; rest -= most) {
      heap.pause(min(rest, most) * 1000);
    }
  }

  @patch
  static int _pid(Process? process) => process?.pid ?? _processNumber();

  @patch
  static Stream<ProcessSignal> _watchSignal(ProcessSignal signal) {
    const watched = [
      ProcessSignal.sighup,
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sigusr1,
      ProcessSignal.sigusr2,
      ProcessSignal.sigwinch,
    ];
    if (!watched.contains(signal)) {
      throw SignalException('Listening for signal $signal is not supported');
    }
    return (_watches[signal.signalNumber] ??= _SignalWatch(signal)).stream;
  }
}

/// The signals that are listened for, by their numbers.
final Map<int, _SignalWatch> _watches = {};

/// A signal descriptor and the action that restores the state before watching.
final class _SignalRegistration {
  final int file;
  final void Function()? _restore;

  _SignalRegistration._(this.file, this._restore);

  static _SignalRegistration? opened(int file, void Function()? restore) {
    if (file >= 0) return _SignalRegistration._(file, restore);
    restore?.call();
    return null;
  }

  void close() {
    _closeFile(file);
    _restore?.call();
  }
}

/// Tells when a signal comes, while it is listened for.
final class _SignalWatch extends _Task {
  final ProcessSignal _signal;
  late final StreamController<ProcessSignal> _controller =
      StreamController.broadcast(onListen: _start, onCancel: _stop);
  _SignalRegistration? _registration;

  _SignalWatch(this._signal);

  Stream<ProcessSignal> get stream => _controller.stream;

  int get file => _registration?.file ?? -1;

  void _start() {
    _registration = _signalFile(_nativeSignalNumber(_signal));
    if (_registration == null) {
      _controller.addError(SignalException('Failed to listen for $_signal'));
      return;
    }
    _Tasks._instance.add(this);
  }

  void _stop() {
    final registration = _registration;
    if (registration == null) return;
    _registration = null;
    _Tasks._instance.remove(this);
    registration.close();
  }

  bool advance() {
    for (var count = _signalsOf(file); count > 0; count--) {
      _controller.add(_signal);
    }
    return false;
  }
}

@Native<Int32 Function(Int32, Int64)>(symbol: 'getrusage')
external int _resourceUse(int who, int usage);

@patch
class ProcessInfo {
  @patch
  static int get maxRss {
    // The largest resident size follows two times in `struct rusage`.
    const self = 0, largest = 32;
    if (_resourceUse(self, _buffer) < 0) throw _failure();
    return load64(_buffer + largest) * _largestUnit;
  }

  @patch
  static int get currentRss => _residentBytes();
}
