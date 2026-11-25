/// LIR that this version cannot translate yet.
final class EmitUnsupported(final String function, final String what)
    implements Exception {
  @override
  String toString() => 'EmitUnsupported: $function: $what';
}
