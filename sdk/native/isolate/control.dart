// What other isolates, or this one, tell an isolate through its control port.
import 'dart:_heap/objects.dart' show exit;
import 'dart:_heap/unwind.dart' show raiseTo;
import 'dart:_internal' show EventOrder, isFirstIsolate, writeText;

// The messages, each a list that starts with one of these.
const _pauseMessage = 1, _resumeMessage = 2, _pingMessage = 3;
const _killMessage = 4, _addExitMessage = 5, _removeExitMessage = 6;
const _addErrorMessage = 7, _removeErrorMessage = 8, _fatalMessage = 9;

/// Whether errors that nothing catches end this isolate.
bool _errorsAreFatal = true;

/// Those that are told when this isolate ends, and what they are told.
final List<(SendPort, Object?)> _exitListeners = [];

/// Those that are told of errors that nothing catches here.
final List<SendPort> _errorListeners = [];

/// The capabilities that resume this isolate, while it is paused.
final List<Capability> _pauses = [];

/// The frame of the function that runs this isolate, if it is not the first.
int _spawnedFrame = 0;

/// What ends an isolate other than the first.
final class _Termination {
  const _Termination();
}

/// Tells this isolate [message] through [port], its control port.
void _sendControl(SendPort port, List<Object?> message) => port.send(message);

void _handleControl(Object? message) {
  if (message is! List || message.isEmpty) return;
  final current = Isolate.current;
  switch (message) {
    case [_pauseMessage, final pause, final Capability resume]
        when pause == current.pauseCapability:
      _pauses.add(resume);
      EventOrder.isPaused = true;
    case [_resumeMessage, final pause, final Capability resume]
        when pause == current.pauseCapability:
      _pauses.remove(resume);
      EventOrder.isPaused = _pauses.isNotEmpty;
    case [_pingMessage, final SendPort port, final int priority, final answer]:
      if (priority == Isolate.immediate) {
        port.send(answer);
      } else {
        _Inbox.current.beforeNext(() => port.send(answer));
      }
    case [_killMessage, final terminate, _]
        when terminate == current.terminateCapability:
      _terminate('Isolate.kill');
    case [_addExitMessage, final SendPort port, final response]:
      _exitListeners
        ..removeWhere((listener) => listener.$1 == port)
        ..add((port, response));
    case [_removeExitMessage, final SendPort port]:
      _exitListeners.removeWhere((listener) => listener.$1 == port);
    case [_addErrorMessage, final SendPort port]:
      if (!_errorListeners.contains(port)) _errorListeners.add(port);
    case [_removeErrorMessage, final SendPort port]:
      _errorListeners.remove(port);
    case [_fatalMessage, final terminate, final bool isFatal]
        when terminate == current.terminateCapability:
      _errorsAreFatal = isFatal;
  }
}

/// Ends this isolate, which [how] did. The first one ends the program, like the
/// official runtime does.
Never _terminate(String how) {
  if (isFirstIsolate) {
    writeText(2, 'isolate terminated by $how', true);
    exit(255);
  }
  raiseTo(_spawnedFrame, const _Termination(), StackTrace.empty);
}

/// Tells the error listeners about [error], and returns whether the isolate
/// goes on.
bool _handleUncaught(Object error, StackTrace trace) {
  if (_errorListeners.isNotEmpty) {
    final message = [error.toString(), trace.toString()];
    for (final port in _errorListeners) {
      port.send(message);
    }
  }
  if (!_errorsAreFatal) return true;
  // The official runtime ends then without telling more.
  if (isFirstIsolate && _errorListeners.isNotEmpty) exit(0);
  return false;
}

/// Tells about [error], which ends this isolate, unless listeners were told.
void _reportFatal(Object error, StackTrace trace) {
  if (_errorListeners.isNotEmpty) return;
  writeText(2, 'Unhandled exception:', true);
  writeText(2, error.toString(), true);
  writeText(2, trace.toString(), false);
}

/// Tells those that listen that this isolate ends.
void _tellExit() {
  for (final (port, response) in _exitListeners) {
    try {
      port.send(response);
    } catch (_) {}
  }
}
