// Finalizers, which the collector tells what is gone.
import 'dart:_heap/collector.dart' show countOutside;
import 'dart:_heap/objects.dart' show registerEvents;

@patch
class FinalizerBase {
  @patch
  static List<WeakReference<FinalizerBase>>? _isolateFinalizers;

  /// The entries whose values are gone, which are not handled yet.
  FinalizerEntry? _collected;

  @patch
  late Set<FinalizerEntry> _allEntries;

  @patch
  Expando<Set<FinalizerEntry>>? _detachments;

  @patch
  _setIsolate() {
    _finalization;
  }

  @patch
  FinalizerEntry? _exchangeEntriesCollectedWithNull() {
    final result = _collected;
    _collected = null;
    return result;
  }

  /// Does what is done for those.
  void handleCollected() {}

  /// Uses every entry of every finalizer.
  static void eachEntry(void Function(FinalizerEntry entry) use) {
    for (final weak in _isolateFinalizers ?? const []) {
      weak.target?._allEntries.forEach(use);
    }
  }
}

@patch
@pragma('dartc:weak', 'entries')
class FinalizerEntry {
  // The collector knows the order of these.
  @pragma('dartc:weak')
  Object? _value, _detach;

  /// Whose entry this is.
  @pragma('dartc:weak')
  FinalizerBase? finalizer;

  /// The function of C to call, or 0, and what it takes.
  int function = 0, argument = 0;
  int _externalSize = 0, _link = 0;
  Object? _token;
  FinalizerEntry? _next;

  FinalizerEntry._(this._value, this._token, this._detach, this.finalizer);

  @patch
  static FinalizerEntry allocate(
    Object value,
    Object? token,
    Object? detach,
    FinalizerBase finalizer,
  ) => FinalizerEntry._(value, token, detach, finalizer);

  @patch
  Object? get value => _value;

  @patch
  Object? get detach => _detach;

  @patch
  FinalizerEntry? get next => _next;

  @patch
  int get externalSize => _externalSize;

  @patch
  Object? get token => _token;

  /// Is set where it is detached.
  @patch
  set token(Object? value) {
    _token = value;
    function = 0;
  }

  @patch
  void setExternalSize(int size) {
    countOutside(size - _externalSize);
    _externalSize = size;
  }
}

/// Has the entries whose values are gone, the first of which the collector sets.
@pragma('dartc:weak', 'queues')
final class _Finalization implements EventSource {
  FinalizerEntry? _first;
  final List<FinalizerBase> _ready = [];

  bool get keepsAlive => false;

  int get happened {
    var entry = _first;
    _first = null;
    while (entry != null) {
      final next = entry._next, finalizer = entry.finalizer;
      if (finalizer != null) {
        entry._next = finalizer._collected;
        finalizer._collected = entry;
        if (!_ready.contains(finalizer)) _ready.add(finalizer);
      }
      entry = next;
    }
    return _ready.length;
  }

  bool runOne() {
    if (_ready.isEmpty) return false;
    _ready.removeAt(0).handleCollected();
    return true;
  }

  void wait(int microseconds) {}

  void end() {}
}

final _Finalization _finalization = _registerFinalization();

_Finalization _registerFinalization() {
  final source = _Finalization();
  registerEvents(source);
  return source;
}
