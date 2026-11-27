import 'package:dartc/hir.dart';

import 'calls.dart';
import 'dead.dart';
import 'rewriter.dart';
import 'threading.dart';

/// What can be left out.
enum Optimization() {
  /// Calls of the only function that can be called are direct.
  devirtualize,

  /// Calls of small functions are replaced by their bodies.
  inline,

  /// Tests of types that the classes of objects decide are answered.
  decideTypes,
}

/// How often each function is made anew.
const _rounds = 2;

/// Makes [module] do the same with less, by what is [enabled].
///
/// Its functions change; what is not needed any more is not in the result.
HirModule optimizeProgram(
  HirModule module, {
  Set<Optimization> enabled = const {...Optimization.values},
}) {
  if (enabled.isEmpty) return module;
  final calls = Calls(
    module,
    devirtualizes: enabled.contains(Optimization.devirtualize),
    inlinesSmall: enabled.contains(Optimization.inline),
    decidesTypes: enabled.contains(Optimization.decideTypes),
  );
  for (var round = 0; round < _rounds; round++) {
    for (final function in calleesFirst(module)) {
      threadJumps(function.blocks);
      function.redefine(removeDead(rewrite(function, module, calls).first));
      calls.changed(function);
    }
  }
  return _withoutUnused(module);
}

/// [module] with only the functions that can be called.
HirModule _withoutUnused(HirModule module) {
  final found = <HirFunction>{}, selectors = <HirSelector>{};
  final pending = <HirFunction>[];
  void need(HirFunction? function) {
    if (function != null && found.add(function)) pending.add(function);
  }

  [
    module.main,
    module.allocate,
    module.raise,
    module.stackOverflow,
    module.uncaught,
    module.callback,
    module.spawned,
    module.eventLoop,
    module.isInstance,
    ...module.exports.values,
  ].forEach(need);
  while (pending.isNotEmpty) {
    for (final call in callsOf(pending.removeLast())) {
      switch (call) {
        case HirCall(:final HirFunction target):
          need(target);
        case HirVirtualCall(:final selector) when selectors.add(selector):
          module.dispatch[selector]!.values.forEach(need);
        default:
          break;
      }
    }
  }
  return HirModule(
    module.main,
    module.functions.where(found.contains),
    classes: module.classes,
    dispatch: {
      for (final selector in module.dispatch.keys)
        if (selectors.contains(selector)) selector: module.dispatch[selector]!,
    },
    globals: module.globals,
    tests: module.tests,
    likely: module.likely,
    integers: module.integers,
    allocate: module.allocate,
    raise: module.raise,
    stackOverflow: module.stackOverflow,
    uncaught: module.uncaught,
    callback: module.callback,
    spawned: module.spawned,
    exports: module.exports,
    eventLoop: module.eventLoop,
    isInstance: module.isInstance,
    sealedTypes: module.sealedTypes,
  );
}
