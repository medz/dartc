// The collector keeps what these refer to, so nothing is ever finalized.

@patch
class _WeakProperty {
  @patch
  var key;
  @patch
  var value;
}

@patch
class _WeakReference<T> {
  @patch
  T? target;

  @patch
  set _target(T? value) {
    target = value;
  }
}

@patch
abstract class Finalizer<T> {
  @patch
  factory Finalizer(void Function(T) callback) = _IdleFinalizer<T>;
}

final class _IdleFinalizer<T> implements Finalizer<T> {
  _IdleFinalizer(void Function(T) callback);

  void attach(Object value, T finalizationToken, {Object? detach}) {
    checkValidWeakTarget(value, 'value');
    if (detach != null) checkValidWeakTarget(detach, 'detach');
  }

  void detach(Object detach) => checkValidWeakTarget(detach, 'detach');
}

@patch
class StackTrace {
  @patch
  static StackTrace get current => StackTrace.empty;
}
