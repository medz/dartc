/// The location of one 64-bit argument at a native call boundary.
sealed class const ArgumentLocation<R>();

/// An argument passed in [register].
final class const RegisterArgument<R>(final R register)
    extends ArgumentLocation<R>;

/// An eight-byte argument at [offset] from the caller's stack pointer.
///
/// A callee adds its frame's incoming-argument base to this offset.
final class StackArgument<R>(final int offset) extends ArgumentLocation<R> {
  this {
    if (offset < 0 || offset % 8 != 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Expected an aligned stack word.',
      );
    }
  }
}
