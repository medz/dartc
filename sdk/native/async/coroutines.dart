// What `async` functions and generators are compiled to use.
import 'dart:_heap/machine.dart'
    show codeStart, frameAddress, load64, sourcePlaces;
import 'dart:_internal' show tellAwaiters;

/// What a function does until it is left or ends, given what it waited for or
/// an exception.
typedef _Body = Object? Function(
  _SuspendState state,
  Object? value,
  Object? exception,
  StackTrace? stackTrace,
);

/// Makes a body that has not started.
typedef _Starter = _Body Function();

@patch
void _trySetStackTrace(Object error, StackTrace stackTrace) {
  if (error is! Error || error.stackTrace != null) return;
  // Only throwing sets it.
  try {
    Error.throwWithStackTrace(error, stackTrace);
  } catch (_) {}
}

@patch
_fatal(msg) => throw StateError('$msg');

@patch
class _SuspendState {
  Object? _data;
  void Function(dynamic)? _onValue;
  dynamic Function(Object, StackTrace)? _onError;
  _Body? _body;
  _Starter? _starter;

  /// Where its body waited last, as where that call returns to, and the state
  /// that waits for what it completes, for traces of the stack.
  int _awaitedAt = 0;
  _SuspendState? _awaiter;

  @patch
  set _functionData(Object value) {
    _data = value;
  }

  @patch
  Object get _functionData => _data!;

  @patch
  set _thenCallback(void Function(dynamic)? value) {
    _onValue = value;
  }

  @patch
  void Function(dynamic)? get _thenCallback => _onValue;

  @patch
  set _errorCallback(dynamic Function(Object, StackTrace)? value) {
    _onError = value;
  }

  @patch
  dynamic Function(Object, StackTrace)? get _errorCallback => _onError;

  @patch
  Object? _resume(Object? value, Object? exception, StackTrace? stackTrace) {
    if (_data is _SyncStarIterator) {
      return _body!(this, value, exception, stackTrace);
    }
    final before = _running;
    _running = this;
    tellAwaiters ??= _awaitersOfRunning;
    try {
      return _body!(this, value, exception, stackTrace);
    } catch (error, trace) {
      return _handleException(this, error, trace);
    } finally {
      _running = before;
    }
  }

  @patch
  _SuspendState _clone() => _SuspendState().._body = _starter!();

  @patch
  static Function _instantiateClosureWithFutureTypeArgument(
    dynamic Function<T>(T) closure,
    Future future,
  ) =>
      (dynamic value) => closure<dynamic>(value);
}

/// The state whose body goes on after it waited, if one does.
_SuspendState? _running;

/// Where the bodies that wait for [_running] waited, innermost first.
List<int> _awaitersOfRunning() => [
  for (var state = _running?._awaiter; state != null; state = state._awaiter)
    state._awaitedAt,
];

@patch
class _Future {
  /// The state of the `async` function that completes it, if one does.
  _SuspendState? _completer;
}

Future<T> _startAsync<T>(_Body body) {
  final future = _Future<T>();
  final state = _SuspendState()
    .._data = future
    .._body = body;
  future._completer = state;
  try {
    body(state, null, null, null);
  } catch (error, trace) {
    _SuspendState._handleException(future, error, trace);
  }
  return future;
}

void _finishAsync(_SuspendState state, Object? value) {
  _SuspendState._returnAsync(state, value);
}

void _await(_SuspendState state, Object? value) {
  if (sourcePlaces() != 0) _noteAwait(state, value, load64(frameAddress() + 8));
  state._await(value);
}

void _awaitChecked<T>(_SuspendState state, Object? value) {
  if (sourcePlaces() != 0) _noteAwait(state, value, load64(frameAddress() + 8));
  state._awaitWithTypeCheck<T>(value);
}

/// Notes that [state] waits for [value] at [code], for traces of the stack.
void _noteAwait(_SuspendState state, Object? value, int code) {
  state._awaitedAt = code - codeStart();
  if (value is _Future) value._completer?._awaiter = state;
}

Stream<T> _startAsyncStar<T>(_Body body) {
  final controller = _AsyncStarStreamController<T>();
  final state = _SuspendState()
    .._data = controller
    .._body = body;
  state._createAsyncStarCallback(controller);
  return controller.stream;
}

_AsyncStarStreamController _controllerOf(_SuspendState state) =>
    unsafeCast<_AsyncStarStreamController>(state._data);

void _finishAsyncStar(_SuspendState state) {
  _SuspendState._returnAsyncStar(state, null);
}

/// Adds [value] to the stream. Returns whether to end.
bool _yieldAsyncStar(_SuspendState state, Object? value) =>
    _controllerOf(state).add(value);

bool _yieldAllAsyncStar(_SuspendState state, Object? stream) =>
    _controllerOf(state).addStream(unsafeCast<Stream>(stream));

Iterable<T> _startSyncStar<T>(_Starter starter) =>
    _SyncStarIterable<T>()
      .._stateAtStart = (_SuspendState().._starter = starter);

_SyncStarIterator _iteratorOf(_SuspendState state) =>
    unsafeCast<_SyncStarIterator>(state._data);

void _yieldSyncStar(_SuspendState state, Object? value) {
  _iteratorOf(state)._current = value;
}

void _yieldAllSyncStar(_SuspendState state, Object? iterable) {
  _iteratorOf(state)._yieldStarIterable = unsafeCast<Iterable>(iterable);
}

// What `await for` uses.

_StreamIterator<T> _iterateStream<T>(Stream<T> stream) =>
    _StreamIterator<T>(stream);

Object _moveStream(_StreamIterator iterator) => iterator.moveNext();

Object? _currentOfStream(_StreamIterator iterator) => iterator.current;

bool _isStreamOpen(_StreamIterator iterator) => iterator._subscription != null;

Object _cancelStream(_StreamIterator iterator) => iterator.cancel();
