import 'instruction.dart';
import 'module.dart';

/// A malformed program: always a compiler bug, never a user error.
final class HirError(final String message) implements Exception {
  @override
  String toString() => 'HirError: $message';
}

/// Throws [HirError] unless [module] satisfies every HIR rule.
void verifyHir(HirModule module) {
  final function = module.main;
  Never fail(String message) => throw HirError('${function.name}: $message');
  final defined = <HirInstruction>{};
  void use(Iterable<HirInstruction> values) {
    if (!defined.containsAll(values)) fail('use of an undefined value');
  }

  for (final instruction in function.body.instructions) {
    use(instruction.inputs);
    if (!defined.add(instruction)) fail('a value is defined twice');
  }
  final end = function.body.terminator;
  if (end == null) fail('no terminator');
  use(end.inputs);
}
