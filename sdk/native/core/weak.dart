// What the collector clears when objects are gone.

@patch
@pragma('dartc:weak', 'properties')
class _WeakProperty {
  @patch
  @pragma('dartc:weak')
  var key;
  @patch
  @pragma('dartc:weak')
  var value;
  int _link = 0;
}

@patch
@pragma('dartc:weak', 'references')
class _WeakReference<T> {
  @patch
  @pragma('dartc:weak')
  T? target;
  int _link = 0;

  @patch
  set _target(T? value) {
    target = value;
  }
}

@patch
class _FinalizerImpl<T> {
  @patch
  late void Function(T) _callback;

  void handleCollected() => _runFinalizers();
}

@patch
class StackTrace {
  @patch
  static StackTrace get current => _traceHere();
}
