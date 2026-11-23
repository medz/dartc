// There is one thread only.

/// The values of all variables, by their numbers.
final List<Object?> _values = [];

/// What variables without a value have.
const _none = _None();

final class _None {
  const _None();
}

@patch
class ThreadLocal<T> {
  @patch
  static int _allocateId() {
    _values.add(_none);
    return _values.length - 1;
  }

  @patch
  static bool _hasValue(int id) => !identical(_values[id], _none);

  @patch
  static Object? _getValue(int id) => _values[id];

  @patch
  static void _setValue(int id, Object? value) {
    _values[id] = value;
  }

  @patch
  static void _clearValue(int id) {
    _values[id] = _none;
  }
}
