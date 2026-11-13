import '../runtime/allocator.dart' as allocator;
import '../runtime/stack_trace.dart' as traces;
import '../runtime/memory.dart';
import '../../lib/runtime/contracts.dart' as runtime;

@patch
class _SuspendState(this._data, this._step) implements traces.AsyncStack {
  Object _data;
  void Function(dynamic)? _then;
  dynamic Function(Object, StackTrace)? _error;
  void Function(Object?, Object?, StackTrace?)? _step;
  bool _suspended = false;
  String? _stackLocation;

  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
  bool Function(Object) Function()? _syncFactory;
  bool Function(Object)? _syncStep;

  @patch
  _SuspendState _clone() =>
      _SuspendState(_data, null).._syncStep = _syncFactory!();

  @patch
  Object get _functionData => _data;
  @patch
  set _functionData(Object value) => _data = value;
  @patch
  void Function(dynamic)? get _thenCallback => _then;
  @patch
  set _thenCallback(void Function(dynamic)? value) => _then = value;
  @patch
  dynamic Function(Object, StackTrace)? get _errorCallback => _error;
  @patch
  set _errorCallback(dynamic Function(Object, StackTrace)? value) =>
      _error = value;

  @patch
  Object? _resume(Object? value, Object? exception, StackTrace? stackTrace) {
    if (_syncStep case final step?) return step(_functionData);
    _stackLocation = null;
    try {
      _step?.call(value, exception, stackTrace);
    } catch (error, trace) {
      _step = null;
      _handleException(_suspended ? this : _data, error, trace);
    }
    return _data;
  }

  @patch
  @runtime.Primitive(.instantiateClosure)
  external static Function _instantiateClosureWithFutureTypeArgument(
    dynamic Function<T>(T) closure,
    Future future,
  );
}

@runtime.RuntimeEntry(.asyncCreate)
Object _asyncCreate<T>(void Function(Object?, Object?, StackTrace?) step) =>
    _SuspendState(_SuspendState._initAsync<T>()!, step);

@runtime.RuntimeEntry(.asyncStart)
Future<T> _asyncStart<T>(Object state) {
  final activation = state as _SuspendState;
  activation._resume(null, null, null);
  return activation._functionData as Future<T>;
}

@runtime.RuntimeEntry(.asyncAwait)
void _asyncAwait<T>(Object state, Object? value, String? location) {
  final activation = state as _SuspendState;
  activation._suspended = true;
  activation._stackLocation = location;
  activation._awaitWithTypeCheck<T>(value);
}

@runtime.RuntimeEntry(.asyncReturn)
void _asyncReturn(Object state, Object? value) {
  final activation = state as _SuspendState;
  activation._step = null;
  _SuspendState._returnAsync(activation, value);
}

@patch
void _trySetStackTrace(Object error, StackTrace stackTrace) =>
    traces.recordError(error, stackTrace);

@patch
class _AsyncRun {
  @patch
  static void _scheduleImmediate(void Function() callback) =>
      allocator.events().scheduleMicrotasks(callback);
}

@runtime.RuntimeEntry(.syncCreate)
Iterable<T> _syncCreate<T>(bool Function(Object) Function() create) {
  final value = _SuspendState._initSyncStar<T>()!;
  final state = _SuspendState(value, null).._syncFactory = create;
  return state._suspendSyncStarAtStart(null) as Iterable<T>;
}

@runtime.RuntimeEntry(.syncYield)
void _syncYield(Object iterator, Object? value) {
  (iterator as _SyncStarIterator<dynamic>)._current = value;
}

@patch
class _SyncStarIterable<T> {
  @patch
  @pragma(
    'dartc:patch',
    'storage: guard reentry into a native suspension frame',
  )
  Iterator<T> get iterator =>
      _GuardedSyncStarIterator<T>(_stateAtStart!._clone());
}

// Reject recursive resume before the SDK iterator unwinds its active state.
class _GuardedSyncStarIterator<T> extends _SyncStarIterator<T> {
  _GuardedSyncStarIterator(super.state);
  bool _running = false;

  @override
  bool moveNext() {
    if (_running) throw StateError('Iterator is already running');
    _running = true;
    try {
      return super.moveNext();
    } finally {
      _running = false;
    }
  }
}

@patch
_fatal(dynamic msg) => Memory.fail();

@runtime.RuntimeEntry(.asyncStarCreate)
Object _asyncStarCreate<T>(void Function(Object?, Object?, StackTrace?) step) =>
    _SuspendState(_SuspendState._initAsyncStar<T>()!, step);

@runtime.RuntimeEntry(.asyncStarStart)
Stream<T> _asyncStarStart<T>(Object state) =>
    (state as _SuspendState)._yieldAsyncStar(null) as Stream<T>;

@runtime.RuntimeEntry(.asyncStarYield)
bool _asyncStarYield(Object state, Object? value, String? location) {
  final activation = state as _SuspendState;
  activation._stackLocation = location;
  return (activation._functionData as _AsyncStarStreamController<dynamic>).add(
    value,
  );
}

@runtime.RuntimeEntry(.asyncStarYieldStream)
bool _asyncStarYieldStream(Object state, Object stream, String? location) {
  final activation = state as _SuspendState;
  activation._stackLocation = location;
  final controller =
      activation._functionData as _AsyncStarStreamController<dynamic>;
  try {
    return controller.addStream(stream as Stream<dynamic>);
  } catch (_) {
    // The VM leaves isAdding set when listen throws, blocking later yields.
    controller.isAdding = false;
    rethrow;
  }
}

@runtime.RuntimeEntry(.asyncStarReturn)
void _asyncStarReturn(Object state, Object? value) {
  final activation = state as _SuspendState;
  activation._step = null;
  _SuspendState._returnAsyncStar(activation, value);
}

@patch
class _Future<T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

@patch
class _FutureListener<S, T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

@patch
class _Completer<T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

@patch
class _AsyncStarStreamController<T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

@patch
class _StreamController<T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

@patch
class _StreamIterator<T> implements traces.AsyncStack {
  @override
  traces.CapturedStackTrace? asynchronousCaller(
    traces.CapturedStackTrace trace,
  ) => _captureAsyncStack(this, trace);
}

// Follow the pinned SDK's continuation graph; never run a callback to find a link.
traces.CapturedStackTrace? _captureAsyncStack(
  Object initial,
  traces.CapturedStackTrace synchronous,
) {
  Object? next = initial;
  if (initial is _SuspendState) {
    if (initial._error == null &&
        initial._data is! _AsyncStarStreamController) {
      return null;
    }
    next = initial._data;
  } else if (initial is _FutureListener) {
    next = initial.result;
  }
  var trace = synchronous;
  Object? fallback;
  final visited = Set<Object>.identity();
  while (next != null && visited.add(next)) {
    switch (next) {
      case _SuspendState state:
        if (state._stackLocation case final location?) {
          trace = trace.followedBy(location);
        }
        next = state._data;
      case _Completer completer:
        next = completer.future;
      case _Future future:
        final listeners = future._resultOrListeners;
        next = listeners is _FutureListener ? listeners : null;
      case _FutureListener listener:
        fallback = switch (listener.state) {
          _FutureListener.stateThen ||
          _FutureListener.stateThenOnerror ||
          _FutureListener.stateThenAwait ||
          _FutureListener.stateCatchError ||
          _FutureListener.stateWhenComplete => listener.result,
          _ => null,
        };
        next = listener.callback ?? fallback;
      case _AsyncStarStreamController controller:
        next = controller.controller;
      case _StreamIterator iterator:
        next = iterator._hasValue ? null : iterator._stateData;
      case _StreamController controller:
        if (!controller.hasListener) {
          next = null;
          break;
        }
        final data = controller._varData;
        final subscription = data is _StreamControllerAddStreamState
            ? data._varData
            : data;
        if (subscription is! _BufferingStreamSubscription) {
          next = null;
          break;
        }
        // Reading a contravariant callback must not widen its argument type.
        final callback = unsafeCast<_BufferingStreamSubscription<Never>>(
          subscription,
        )._onData;
        final receiver = traces.closureLink(callback);
        if (receiver is _StreamIterator) {
          next = receiver;
        } else if (receiver is _StreamController &&
            receiver._varData is _AddStreamState) {
          final added = receiver._varData as _AddStreamState;
          final listener = added.addStreamFuture._resultOrListeners;
          Object? link = listener is _FutureListener ? listener.callback : null;
          while (link is Function && visited.add(link)) {
            link = traces.closureLink(link);
          }
          next = link is _AsyncStarStreamController
              ? link.asyncStarBody
              : callback;
        } else {
          next = callback;
          if (receiver == null) {
            fallback =
                traces.closureLink(subscription._onError) ??
                traces.closureLink(subscription._onDone);
          }
        }
      case Function callback:
        var closure = callback;
        var link = traces.closureLink(closure);
        while (link is Function && visited.add(link)) {
          closure = link;
          link = traces.closureLink(closure);
        }
        if (link is! _SuspendState) {
          if (traces.closureDescription(closure) case final description?) {
            trace = trace.followedBy(description);
          }
        }
        next = link is Function ? null : link ?? fallback;
        fallback = null;
      default:
        next = null;
    }
  }
  return identical(trace, synchronous)
      ? null
      : traces.CapturedStackTrace(0, trace, null);
}
