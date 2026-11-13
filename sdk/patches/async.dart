import '../runtime/allocator.dart' as allocator;
import '../runtime/stack_trace.dart' as traces;
import '../runtime/memory.dart';
import '../../lib/runtime/contracts.dart' as runtime;

@patch
class _SuspendState(this._data, this._step) {
  Object _data;
  void Function(dynamic)? _then;
  dynamic Function(Object, StackTrace)? _error;
  void Function(Object?, Object?, StackTrace?)? _step;
  bool _suspended = false;
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
void _asyncAwait<T>(Object state, Object? value) {
  final activation = state as _SuspendState;
  activation._suspended = true;
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
bool _asyncStarYield(Object state, Object? value) =>
    ((state as _SuspendState)._functionData
            as _AsyncStarStreamController<dynamic>)
        .add(value);

@runtime.RuntimeEntry(.asyncStarYieldStream)
bool _asyncStarYieldStream(Object state, Object stream) {
  final controller =
      (state as _SuspendState)._functionData
          as _AsyncStarStreamController<dynamic>;
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
