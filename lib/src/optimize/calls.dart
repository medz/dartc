import 'package:dartc/hir.dart';

import 'cold.dart';
import 'rewriter.dart';

/// What a function calls, and others use.
Iterable<HirCalling> callsOf(HirFunction function) => [
  for (final block in function.blocks) ...[
    ...block.instructions.whereType<HirCalling>(),
    if (block.terminator case HirInvoke(:final call)) call,
  ],
];

/// The functions of [module] such that those that a function calls come before
/// it, apart from calls around.
List<HirFunction> calleesFirst(HirModule module) {
  final order = <HirFunction>[], visited = <HirFunction>{};
  for (final root in module.functions) {
    if (!visited.add(root)) continue;
    final stack = [(root, _targets(root).iterator)];
    while (stack.isNotEmpty) {
      final (function, next) = stack.last;
      if (!next.moveNext()) {
        order.add(function);
        stack.removeLast();
      } else if (visited.add(next.current)) {
        stack.add((next.current, _targets(next.current).iterator));
      }
    }
  }
  return order;
}

Iterable<HirFunction> _targets(HirFunction function) =>
    callsOf(function)
        .whereType<HirCall>()
        .map((call) => call.target)
        .whereType<HirFunction>();

/// How much a function does, and the parameters that it branches on.
typedef _Shape = ({int size, bool hasCalls, List<int> tested});

/// Replaces calls where only one function can be called, and small functions.
final class Calls(
  final HirModule _module, {
  required final bool devirtualizes,
  required final bool inlinesSmall,
  @override required final bool decidesTypes,
}) implements CallPolicy {
  /// The largest functions whose bodies replace calls, and the most functions
  /// one in the other.
  static const _small = 12, _simpler = 40, _depth = 6;

  late final _onlyTargets = {
    for (final MapEntry(key: selector, value: functions)
        in _module.dispatch.entries)
      if (functions.values.toSet() case final all when all.length == 1)
        selector: all.single,
  };

  /// How many classes are told apart before calls, and how many of many.
  static const _mostClasses = 3, _mostLikely = 2;

  late final _special = {
    _module.main,
    ?_module.allocate,
    ?_module.raise,
    ?_module.stackOverflow,
    ?_module.outOfMemory,
    ?_module.uncaught,
    ?_module.callback,
    ?_module.spawned,
    ?_module.eventLoop,
    ?_module.isInstance,
    ..._module.exports.values,
  };

  static const Targets _unknown = (first: [], rest: null, isAll: false);

  @override
  bool mayBeInteger(HirSelector selector) =>
      _module.dispatch[selector]!.containsKey(_module.integers);

  @override
  Targets targetsOf(HirVirtualCall call, Set<HirClass>? classes) {
    if (!devirtualizes) return _unknown;
    final HirVirtualCall(:selector, :bound) = call;
    if (_onlyTargets[selector] case final only?) {
      return (first: const [], rest: only, isAll: true);
    }
    final functions = _module.dispatch[selector]!;
    final possible = classes ?? (bound == null ? null : _module.tests[bound]!);
    if (possible != null) {
      final found = {for (final class_ in possible) class_: ?functions[class_]};
      if (found.values.toSet().length <= 1) {
        return (first: const [], rest: found.values.firstOrNull, isAll: true);
      }
      if (found.length <= _mostClasses) {
        final MapEntry(:key, :value) = found.entries.last;
        return (
          first: [
            for (final MapEntry(key: class_, value: function) in found.entries)
              if (class_ != key) (class_, function),
          ],
          rest: value,
          isAll: true,
        );
      }
    }
    final likely = _module.likely[selector] ?? const [];
    return (
      first: [
        for (final class_ in likely.take(_mostLikely))
          if (possible == null || possible.contains(class_))
            (class_, functions[class_]!),
      ],
      rest: null,
      isAll: false,
    );
  }

  @override
  bool inlines(
    HirFunction callee,
    List<HirFunction> around,
    bool Function(int parameter) isKnown,
  ) {
    if (!inlinesSmall || around.length > _depth) return false;
    if (around.contains(callee) || _special.contains(callee)) return false;
    final (:size, :hasCalls, :tested) = _shapeOf(callee);
    // Functions without checks of the stack may have no calls of others.
    if (hasCalls && callee.checksStack && !around.first.checksStack) {
      return false;
    }
    if (size <= _small) return true;
    return size <= _simpler && tested.any(isKnown);
  }

  final _shapes = <HirFunction, _Shape>{};

  _Shape _shapeOf(HirFunction function) {
    final known = _shapes[function];
    if (known != null) return known;
    // Calls around of it tell nothing.
    _shapes[function] = (size: 1 << 20, hasCalls: true, tested: const []);
    return _shapes[function] = _measure(function);
  }

  /// Forgets what [function] was before.
  void changed(HirFunction function) => _shapes.remove(function);

  _Shape _measure(HirFunction function) {
    const tooMuch = 1 << 20;
    final cold = coldBlocks(function.blocks);
    var size = 0;
    for (final block in function.blocks) {
      var own = block.terminator is HirJump ? 0 : 1;
      if (block.terminator case HirInvoke(:final call)) own += _costOf(call);
      for (final instruction in block.instructions) {
        own += _needsFrame(instruction) ? tooMuch : _costOf(instruction);
      }
      // What leads to throws is not worth calls, and takes only space.
      size += cold.contains(block) ? (own + 2) ~/ 3 : own;
    }
    return (
      size: size,
      hasCalls: callsOf(function).isNotEmpty,
      tested: _testedBy(function),
    );
  }

  /// The parameters of [function] whose values or classes it branches on.
  List<int> _testedBy(HirFunction function) {
    final tested = <HirValue>{};
    for (final block in function.blocks) {
      for (final instruction in block.instructions) {
        switch (instruction) {
          case HirIsInstance() || HirHasClass() || HirVirtualCall():
            tested.add(instruction.inputs.first);
          case HirCall(:final HirFunction target, :final arguments):
            final (:size, hasCalls: _, tested: inner) = _shapeOf(target);
            if (size > _simpler) continue;
            tested.addAll(inner.map((i) => arguments[i]));
          default:
            break;
        }
      }
      if (block.terminator case HirBranch(:final condition)) {
        tested.add(condition);
      }
    }
    return [
      for (final (i, parameter) in function.entry.parameters.indexed)
        if (tested.contains(parameter)) i,
    ];
  }

  static int _costOf(HirInstruction instruction) => switch (instruction) {
    HirConst() || HirNull() || HirStatic() || HirClassNumber() => 0,
    HirRefine() => 0,
    HirCall(:final arguments) => 1 + arguments.length ~/ 2,
    HirVirtualCall() => 3,
    HirNew() || HirNewArray() || HirBox() => 2,
    _ => 1,
  };

  /// Whether [instruction] depends on the frame that it is done in.
  static bool _needsFrame(HirInstruction instruction) => switch (instruction) {
    HirMachine(:final op) =>
      op == .frameAddress ||
          op == .resume ||
          op == .trap ||
          op == .callNative ||
          op == .callBlock ||
          op == .nativeFrame,
    _ => false,
  };
}
