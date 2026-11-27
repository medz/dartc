import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/hir.dart';

import 'types.dart' show isSubclass;

/// Why a function became part of the program.
final class Reason(
  /// What asked for it, in a few words, which happened in [by] if there is
  /// one.
  final String how, {

  /// The function whose translation asked for it.
  final HirFunction? by,

  /// The function that created the first objects that a call reached it on.
  final HirFunction? createdBy,
});

/// Why each function is part of a program, and what declares it, as
/// translating finds out.
final class Reasons() {
  final _reasons = <HirFunction, Reason>{};
  final _owners = <HirFunction, Element>{};
  final _locals = <HirFunction>{};

  /// Why [function] is part of the program, if it is.
  Reason? of(HirFunction function) => _reasons[function];

  /// The reasons from [function] back to where the program starts.
  List<(HirFunction, Reason)> chainTo(HirFunction function) {
    final chain = <(HirFunction, Reason)>[];
    final seen = <HirFunction>{};
    for (
      HirFunction? found = function;
      found != null && seen.add(found);
      found = _reasons[found]?.by
    ) {
      if (_reasons[found] case final reason?) chain.add((found, reason));
    }
    return chain;
  }

  /// The library that declares [function], or null if the compiler made it.
  ///
  /// Local functions belong to what they are in.
  Uri? libraryOf(HirFunction function) => _ownerOf(function)?.library?.uri;

  /// The class, mixin or extension that declares [function], if there is one.
  String? classOf(HirFunction function) =>
      switch (_ownerOf(function)?.enclosingElement) {
        InstanceElement(:final displayName) => displayName,
        _ => null,
      };

  Element? _ownerOf(HirFunction function) {
    final seen = <HirFunction>{};
    for (
      HirFunction? found = function;
      found != null && seen.add(found);
      found = _reasons[found]?.by
    ) {
      if (_owners[found] case final owner?) return owner;
      if (!_locals.contains(found)) return null;
    }
    return null;
  }
}

/// Functions of the program that only grow, only at their end if `atEnd`.
typedef FunctionSource = (Iterable<HirFunction>, {bool atEnd});

/// The work that translating has left, which can record why functions become
/// part of the program.
///
/// The one that records nothing costs nothing more.
abstract base class Worklist() {
  factory of(Reasons? reasons, List<FunctionSource> Function() sources) =>
      reasons == null ? _Silent() : _Recording(reasons, sources);

  final _pending = <(HirFunction, void Function())>[];

  bool get hasWork => _pending.isNotEmpty;

  /// Has [work], which defines [function], done later.
  void schedule(HirFunction function, void Function() work) =>
      _pending.add((function, work));

  /// Does the work that is left, the latest first.
  void drain() {
    while (_pending.isNotEmpty) {
      final (function, work) = _pending.removeLast();
      defining(function, work);
    }
  }

  /// Does each of [phases], which tell what they are for, until one finds
  /// something.
  bool any(List<(String, bool Function())> phases) =>
      phases.any((phase) => root(phase.$1, phase.$2));

  /// Does [work], which [how] tells what it is for, from no function.
  T root<T>(String how, T Function() work);

  /// Does [work], which defines [function].
  void defining(HirFunction function, void Function() work);

  /// Does [work], which adds what calls of [selector] on objects of [class_]
  /// reach.
  void entry(
    InterfaceElement class_,
    HirSelector selector,
    void Function() work,
  );

  /// Notes a call of [selector] on objects of [receiver] or its subclasses,
  /// and gives [selector].
  HirSelector calls(HirSelector selector, InterfaceElement receiver);

  /// Notes that objects of [class_] are created, and gives [class_].
  InterfaceElement creates(InterfaceElement class_);

  /// Notes a function that is local to the one being translated.
  void local(HirFunction function);

  /// Notes what declares functions, and why the rest of [module] is there.
  void finish(HirModule module, Iterable<(Element, HirFunction?)> declared);
}

final class _Silent() extends Worklist {
  @override
  T root<T>(String how, T Function() work) => work();

  @override
  void defining(HirFunction function, void Function() work) => work();

  @override
  void entry(
    InterfaceElement class_,
    HirSelector selector,
    void Function() work,
  ) => work();

  @override
  HirSelector calls(HirSelector selector, InterfaceElement receiver) =>
      selector;

  @override
  InterfaceElement creates(InterfaceElement class_) => class_;

  @override
  void local(HirFunction function) {}

  @override
  void finish(HirModule module, Iterable<(Element, HirFunction?)> declared) {}
}

final class _Recording(
  final Reasons _reasons,
  final List<FunctionSource> Function() _sources,
) extends Worklist {
  final _seen = <HirFunction>{};

  /// How many functions each of [_sources] had when last looked at.
  final _lengths = <int>[];
  HirFunction? _current;
  final _callers = <HirSelector, Map<InterfaceElement, HirFunction?>>{};
  final _creators = <InterfaceElement, HirFunction?>{};

  @override
  T root<T>(String how, T Function() work) {
    final result = _around(null, work);
    _collect(Reason(how));
    return result;
  }

  @override
  void defining(HirFunction function, void Function() work) {
    _seen.add(function);
    _around(function, work);
    _collect(Reason('used', by: function));
  }

  @override
  void entry(
    InterfaceElement class_,
    HirSelector selector,
    void Function() work,
  ) {
    _around(null, work);
    final callers = _callers[selector] ?? const {};
    final receiver = callers.keys.firstWhere(
      (receiver) => isSubclass(class_, receiver),
      orElse: () => class_,
    );
    final name = class_.displayName;
    _collect(
      Reason(
        'a call of ${selector.name} on $name',
        by: callers[receiver],
        createdBy: _creators[class_],
      ),
    );
  }

  T _around<T>(HirFunction? function, T Function() work) {
    final before = _current;
    _current = function;
    try {
      return work();
    } finally {
      _current = before;
    }
  }

  /// Gives [reason] to the functions that are new.
  void _collect(Reason reason) {
    for (final (i, (functions, :atEnd)) in _sources().indexed) {
      if (i == _lengths.length) _lengths.add(0);
      final length = functions.length, before = _lengths[i];
      if (length == before) continue;
      _lengths[i] = length;
      for (final function in atEnd ? functions.skip(before) : functions) {
        if (_seen.add(function)) _reasons._reasons[function] = reason;
      }
    }
  }

  @override
  HirSelector calls(HirSelector selector, InterfaceElement receiver) {
    (_callers[selector] ??= {}).putIfAbsent(receiver, () => _current);
    return selector;
  }

  @override
  InterfaceElement creates(InterfaceElement class_) {
    _creators.putIfAbsent(class_, () => _current);
    return class_;
  }

  @override
  void local(HirFunction function) => _reasons._locals.add(function);

  @override
  void finish(HirModule module, Iterable<(Element, HirFunction?)> declared) {
    for (final (element, function) in declared) {
      if (function != null) _reasons._owners[function] = element;
    }
    final reasons = _reasons._reasons;
    reasons[module.main] ??= Reason('what starts the program');
    for (final MapEntry(key: name, value: function) in module.exports.entries) {
      reasons[function] ??= Reason('exported as $name');
    }
  }
}
