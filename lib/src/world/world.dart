/// Collects the classes [C] a program creates and the selectors [S] it calls,
/// and finds every pair of them that can meet.
///
/// Both collections only grow and are bounded by the program, so taking
/// entries until there are none terminates.
final class World<C extends Object, S extends Object>(
  final bool Function(C sub, C superclass) _isSubclass,
) {
  final _classes = <C>{};
  final _receivers = <S, Set<C>>{};
  final _found = <(C, S)>{};
  final _pending = <(C, S)>{};

  /// The classes with objects, in the order they were found.
  List<C> get classes => List.unmodifiable(_classes);

  /// The selectors called, in the order they were found.
  List<S> get selectors => List.unmodifiable(_receivers.keys);

  /// Records that objects of class [created] can exist.
  void instantiate(C created) {
    if (!_classes.add(created)) return;
    _receivers.forEach((selector, receivers) {
      if (receivers.any((receiver) => _isSubclass(created, receiver))) {
        _meet(created, selector);
      }
    });
  }

  /// Records a call of [selector] on objects of [receiver] or its subclasses.
  void call(S selector, C receiver) {
    if (!(_receivers[selector] ??= {}).add(receiver)) return;
    for (final created in _classes) {
      if (_isSubclass(created, receiver)) _meet(created, selector);
    }
  }

  void _meet(C created, S selector) {
    if (_found.add((created, selector))) _pending.add((created, selector));
  }

  /// The pairs found since the last time, each given once.
  Set<(C, S)> takeEntries() {
    final entries = Set.of(_pending);
    _pending.clear();
    return entries;
  }
}
