import 'block.dart';
import 'class.dart';
import 'global.dart';
import 'value.dart';

/// A function, which may be called before its body is known.
final class HirFunction(
  @override final String name,
  Iterable<HirType> parameters, [
  @override final HirType? result,
]) extends HirCallable {
  @override
  final List<HirType> parameters = .unmodifiable(parameters);
  List<HirBlock>? _blocks;

  /// The body, whose first block is its entry.
  List<HirBlock> get blocks =>
      _blocks ?? (throw StateError('$name has no body.'));
  HirBlock get entry => blocks.first;

  /// Supplies the body, once.
  void define(Iterable<HirBlock> blocks) {
    if (_blocks != null) throw StateError('$name already has a body.');
    _blocks = .unmodifiable(blocks);
  }
}

/// A whole program, started by [main], which takes no arguments.
///
/// [functions] includes [main] and everything it can call, and [classes] every
/// class it creates objects of. [dispatch] gives the function for a selector
/// and a class whose objects can receive it; its first parameter is the
/// receiver. [allocate] gives the address of memory for an object, of the size
/// it takes.
final class HirModule(
  final HirFunction main,
  Iterable<HirFunction> functions, {
  Iterable<HirClass> classes = const [],
  Map<HirSelector, Map<HirClass, HirFunction>> dispatch = const {},
  Iterable<HirGlobal> globals = const [],
  final HirFunction? allocate,
}) {
  final List<HirGlobal> globals = .unmodifiable(globals);
  final List<HirClass> classes = .unmodifiable(classes);
  final Map<HirSelector, Map<HirClass, HirFunction>> dispatch = .unmodifiable({
    for (final MapEntry(:key, :value) in dispatch.entries)
      key: Map<HirClass, HirFunction>.unmodifiable(value),
  });
  final List<HirFunction> functions = .unmodifiable(functions);
}
