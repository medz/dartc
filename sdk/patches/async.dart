import '../runtime/allocator.dart' as allocator;
import '../runtime/stack_trace.dart' as traces;
import '../../lib/runtime/contracts.dart' as runtime;

@patch
class _SuspendState(this._data, this._step) {
  Object _data;
  void Function(dynamic)? _then;
  dynamic Function(Object, StackTrace)? _error;
  void Function(Object?, Object?, StackTrace?)? _step;
  bool _suspended = false;

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
