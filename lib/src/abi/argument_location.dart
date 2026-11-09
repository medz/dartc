/// The location of one scalar argument at a native call boundary.
sealed class const ArgumentLocation<R>();

/// An argument passed in [register].
final class const RegisterArgument<R>(final R register)
    extends ArgumentLocation<R>;

/// An argument occupying [size] bytes at [offset] from the caller's stack pointer.
///
/// A callee adds its frame's incoming-argument base to this offset.
final class StackArgument<R>(final int offset, {final int size = 8})
    extends ArgumentLocation<R> {
  this {
    if (![1, 2, 4, 8].contains(size) || offset < 0 || offset % size != 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Expected a naturally aligned scalar stack slot.',
      );
    }
  }
}
