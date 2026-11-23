import 'block.dart';
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
/// [functions] includes [main] and everything it can call.
final class HirModule(final HirFunction main, Iterable<HirFunction> functions) {
  final List<HirFunction> functions = .unmodifiable(functions);
}
