import 'block.dart';
import 'class.dart';
import 'global.dart';
import 'value.dart';

/// A function, which may be called before its body is known.
///
/// One that [checksStack] throws instead of running where the stack is used up.
final class HirFunction(
  @override final String name,
  Iterable<HirType> parameters, [
  @override final HirType? result,
  final bool checksStack = true,
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

  /// Replaces the body by one that does the same.
  void redefine(Iterable<HirBlock> blocks) {
    if (_blocks == null) throw StateError('$name has no body.');
    _blocks = .unmodifiable(blocks);
  }
}

/// A whole program, started by [main], which takes no arguments.
///
/// [functions] includes [main] and everything it can call, and [classes] every
/// class it creates objects of. [dispatch] gives the function for a selector
/// and a class whose objects can receive it; its first parameter is the
/// receiver, and [tests] the classes that pass a test.
///
/// A library has [exports], which do the work of functions of C by their names,
/// given the addresses of the block of the call and of what is passed on the
/// stack, and [eventLoop], which does what those left to be done later.
///
/// Objects that receive calls of a selector are often of the classes that
/// [likely] gives for it.
///
/// Integers are boxed in objects of [integers], or in references themselves.
///
/// The remaining functions do the work of the runtime. [allocate] gives the
/// address of memory for an object, of the size it takes, or 0. [raise] throws
/// an exception with its trace. [stackOverflow] and [outOfMemory] throw theirs.
/// [uncaught] reports an exception that ends the program. [callback] does what
/// a function of C that the program made does, given its number, the address
/// of the block of the call, and that of what is passed on the stack.
final class HirModule(
  final HirFunction main,
  Iterable<HirFunction> functions, {
  Iterable<HirClass> classes = const [],
  Map<HirSelector, Map<HirClass, HirFunction>> dispatch = const {},
  Iterable<HirGlobal> globals = const [],
  Map<HirTypeTest, Set<HirClass>> tests = const {},
  final Map<HirSelector, List<HirClass>> likely = const {},
  final HirClass? integers,
  final HirFunction? allocate,
  final HirFunction? raise,
  final HirFunction? stackOverflow,
  final HirFunction? outOfMemory,
  final HirFunction? uncaught,
  final HirFunction? callback,
  Map<String, HirFunction> exports = const {},
  final HirFunction? eventLoop,
}) {
  final Map<String, HirFunction> exports = .unmodifiable(exports);
  final Map<HirTypeTest, Set<HirClass>> tests = .unmodifiable(tests);
  final List<HirGlobal> globals = .unmodifiable(globals);
  final List<HirClass> classes = .unmodifiable(classes);
  final Map<HirSelector, Map<HirClass, HirFunction>> dispatch = .unmodifiable({
    for (final MapEntry(:key, :value) in dispatch.entries)
      key: Map<HirClass, HirFunction>.unmodifiable(value),
  });
  final List<HirFunction> functions = .unmodifiable(functions);
}
