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
}
