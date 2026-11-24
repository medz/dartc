@Native<Int32 Function(Int32)>(symbol: 'isatty')
external int _isTerminal(int file);

@Native<Int32 Function(Int32, Int64)>(symbol: 'tcgetattr')
external int _terminalModes(int file, int result);

@Native<Int32 Function(Int32, Int32, Int64)>(symbol: 'tcsetattr')
external int _setTerminalModes(int file, int when, int modes);

@Native<Int32 Function(Int32, Int64, VarArgs<(Int64,)>)>(symbol: 'ioctl')
external int _controlDevice(int file, int request, int address);

/// What is read from a file as it comes, if that is not a plain file.
class _InputStream extends Stream<List<int>> {
  final int _file;
  late final StreamController<Uint8List> _controller = StreamController(
    sync: true,
    onListen: _start,
    onPause: _stop,
    onResume: _start,
    onCancel: _close,
  );
  _InputTask? _task;
  bool _isClosed = false;

  _InputStream(this._file);

  StreamSubscription<Uint8List> listen(
    void onData(Uint8List event)?, {
    Function? onError,
    void onDone()?,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void _start() {
    if (_task != null || _isClosed) return;
    _Tasks._instance.add(_task = _InputTask(this));
  }

  void _stop() {
    final task = _task;
    if (task == null) return;
    _Tasks._instance.remove(task);
    _task = null;
  }

  void _close() {
    if (_isClosed) return;
    _stop();
    _isClosed = true;
    _closeFile(_file);
  }

  void _advance() {
    _task = null;
    final bytes = _SystemFile(_file + 1).read(_blockSize);
    if (bytes is! Uint8List) {
      _close();
      _controller.addError(FileSystemException('read failed', '', bytes));
      _controller.close();
    } else if (bytes.isEmpty) {
      _close();
      _controller.close();
    } else {
      _controller.add(bytes);
      if (!_controller.isPaused) _start();
    }
  }
}

class _InputTask extends _Task {
  final _InputStream _stream;

  _InputTask(this._stream);

  int get file => _stream._file;

  bool advance() {
    _stream._advance();
    return true;
  }
}

@patch
class _StdIOUtils {
  @patch
  static Stdin _getStdioInputStream(int fd) => Stdin._(
    _typeOfStandard(fd) == _stdioHandleTypeFile
        ? _FileStream.forStdin()
        : _InputStream(fd),
    fd,
  );

  @patch
  static _getStdioOutputStream(int fd) {
    _typeOfStandard(fd);
    return Stdout._(IOSink(_StdConsumer._(fd)), fd);
  }

  static int _typeOfStandard(int fd) {
    final type = _getStdioHandleType(fd);
    if (type is! OSError) return type;
    throw FileSystemException(
      'Failed to get type of stdio handle (fd $fd)',
      '',
      type,
    );
  }

  @patch
  static _getStdioHandleType(int fd) {
    if (_statFile(fd) < 0) return _failure();
    return switch (_statMode & _modeType) {
      _modePipe => _stdioHandleTypePipe,
      _modeSocket => _stdioHandleTypeSocket,
      _modeFile => _stdioHandleTypeFile,
      _ when _isTerminal(fd) == 1 => _stdioHandleTypeTerminal,
      _ => _stdioHandleTypeOther,
    };
  }
}

@patch
StdioType stdioType(object) {
  if (object is _StdStream) object = object._stream;
  if (object is _InputStream && object._isClosed) {
    throw FileSystemException('Socket is closed');
  }
  final file = object is _InputStream
      ? object._file
      : object == stdout
      ? _stdoutFD
      : object == stderr
      ? _stderrFD
      : null;
  if (file != null) {
    switch (_StdIOUtils._typeOfStandard(file)) {
      case _stdioHandleTypeTerminal:
        return StdioType.terminal;
      case _stdioHandleTypePipe:
        return StdioType.pipe;
      case _stdioHandleTypeFile:
        return StdioType.file;
    }
  }
  final isFile =
      object is _FileStream ||
      object is _IOSinkImpl && object._target is _FileStreamConsumer;
  return isFile ? StdioType.file : StdioType.other;
}

Object _terminalMode(int file, int bit) =>
    _terminalModes(file, _buffer) < 0 ? _failure() : _loadModes() & bit != 0;

Object _setTerminalMode(int file, int bit, bool enabled) {
  if (_terminalModes(file, _buffer) < 0) return _failure();
  final modes = _loadModes();
  _storeModes(enabled ? modes | bit : modes & ~bit);
  return _succeeded(_setTerminalModes(file, 0, _buffer));
}

bool _showsEscapes(int file) {
  const known = ['xterm', 'screen', 'rxvt'];
  final terminal = Platform.environment['TERM'];
  return _isTerminal(file) == 1 &&
      terminal != null &&
      known.any(terminal.contains);
}

@patch
class Stdin {
  @patch
  static _echoMode(int fd) => _terminalMode(fd, _echoBit);

  @patch
  static _setEchoMode(int fd, bool enabled) =>
      _setTerminalMode(fd, _echoBit, enabled);

  @patch
  static _echoNewlineMode(int fd) => _terminalMode(fd, _echoNewlineBit);

  @patch
  static _setEchoNewlineMode(int fd, bool enabled) =>
      _setTerminalMode(fd, _echoNewlineBit, enabled);

  @patch
  static _lineMode(int fd) => _terminalMode(fd, _lineBit);

  @patch
  static _setLineMode(int fd, bool enabled) =>
      _setTerminalMode(fd, _lineBit, enabled);

  @patch
  static _readByte(int fd) => _SystemFile(fd + 1).readByte();

  @patch
  static _supportsAnsiEscapes(int fd) => _showsEscapes(fd);
}

@patch
class Stdout {
  @patch
  static _getTerminalSize(int fd) {
    if (_controlDevice(fd, _sizeOfWindow, _buffer) < 0) return _failure();
    final lines = load16(_buffer), columns = load16(_buffer + 2);
    return lines == 0 && columns == 0 ? _failure() : [columns, lines];
  }

  @patch
  static _getAnsiSupported(int fd) => _showsEscapes(fd);
}
