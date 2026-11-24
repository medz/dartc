import 'package:dartc/hir.dart';

/// The parameters of [blocks] that always have the same value, and those.
///
/// [entry] is the first of the blocks, which all can be reached.
Map<HirParameter, HirValue> findAliases(
  HirBlock entry,
  Iterable<HirBlock> blocks,
) {
  final given = <HirParameter, List<HirValue>>{};
  final mixed = <HirParameter>{};
  for (final block in blocks) {
    final end = block.terminator!;
    for (final edge in end.edges) {
      final parameters = edge.target.parameters;
      final implicit = end.implicit(edge).length;
      mixed.addAll(parameters.take(implicit));
      for (final (i, argument) in edge.arguments.indexed) {
        (given[parameters[implicit + i]] ??= []).add(argument);
      }
    }
  }
  final aliases = <HirParameter, HirValue>{};
  HirValue resolve(HirValue value) {
    final next = aliases[value];
    return next == null ? value : resolve(next);
  }

  bool changed;
  do {
    changed = false;
    given.forEach((parameter, arguments) {
      if (mixed.contains(parameter) || aliases.containsKey(parameter)) return;
      HirValue? only;
      for (final argument in arguments) {
        final value = resolve(argument);
        if (identical(value, parameter) || identical(value, only)) continue;
        if (only != null) return;
        only = value;
      }
      if (only == null) return;
      aliases[parameter] = only;
      changed = true;
    });
  } while (changed);
  return {for (final key in aliases.keys) key: resolve(key)};
}
