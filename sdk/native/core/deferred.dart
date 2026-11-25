// Libraries that the program loads itself. They are part of it from the start.

/// The name of such a library in one that imports it.
@patch
class _LibraryPrefix {
  final String _name;
  bool _hasLoaded = false;

  _LibraryPrefix._(this._name);

  @patch
  bool _isLoaded() => _hasLoaded;

  @patch
  void _setLoaded() {
    _hasLoaded = true;
  }

  // What is there from the start.
  @patch
  Object _loadingUnit() => 1;

  @patch
  static void _issueLoad(Object unit) => throw UnsupportedError('Loading');

  String toString() => _name;
}

_LibraryPrefix _deferredPrefix(String name) => _LibraryPrefix._(name);
