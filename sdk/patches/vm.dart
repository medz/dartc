@patch
class ThreadLocal<T> {
  static int _nextId = 0;
  // shortcut: module-local storage, replace when thread entry is supported.
  static final _values = <int, Object?>{};

  @patch
  static int _allocateId() => _nextId++;
  @patch
  static bool _hasValue(int id) => _values.containsKey(id);
  @patch
  static Object? _getValue(int id) => _values[id];
  @patch
  static void _setValue(int id, Object? value) => _values[id] = value;
  @patch
  static void _clearValue(int id) => _values.remove(id);
}
