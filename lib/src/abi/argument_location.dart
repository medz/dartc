/// The location of one value at a native call boundary.
sealed class const ArgumentLocation<R>() {
  /// Registers read or written by this location, including indirect addresses.
  Iterable<R> get registers => switch (this) {
    RegisterArgument(:final register) => [register],
    RegisterAggregate(:final parts) => parts.map((part) => part.register),
    IndirectArgument(:final pointer) => pointer.registers,
    StackArgument() => const [],
  };
}

/// A scalar argument passed in [register].
final class const RegisterArgument<R>(final R register)
    extends ArgumentLocation<R>;

/// Bytes of an aggregate carried in one register, with no scalar conversion.
final class RegisterPart<R>(
  final R register,
  final int offset,
  final int size,
) {
  this {
    if (offset < 0 || size < 1 || size > 8) {
      throw ArgumentError('Invalid aggregate register fragment.');
    }
  }
}

/// An aggregate split across registers in native byte order.
final class RegisterAggregate<R>(Iterable<RegisterPart<R>> parts)
    extends ArgumentLocation<R> {
  final List<RegisterPart<R>> parts = .unmodifiable(parts);
  this {
    final registers = <R>{};
    var end = 0;
    for (final part in this.parts) {
      if (part.offset < end || !registers.add(part.register)) {
        throw ArgumentError('Overlapping aggregate register fragments.');
      }
      end = part.offset + part.size;
    }
    if (this.parts.isEmpty) {
      throw ArgumentError('Expected aggregate fragments.');
    }
  }
}

/// Caller-owned value storage whose address is passed in [pointer].
///
/// [returnedAddress] is used by conventions that echo a hidden result address.
final class IndirectArgument<R>(
  final ArgumentLocation<R> pointer, {
  final R? returnedAddress,
}) extends ArgumentLocation<R> {
  this {
    if (pointer is! RegisterArgument<R> && pointer is! StackArgument<R> ||
        pointer is StackArgument<R> &&
            (pointer as StackArgument<R>).size != 8) {
      throw ArgumentError('An indirect value requires a scalar address.');
    }
  }
}

/// [size] bytes at [offset] from the caller's stack pointer.
final class StackArgument<R>(
  final int offset, {
  final int size = 8,
  int? alignment,
}) extends ArgumentLocation<R> {
  final int alignment = alignment ?? size;
  this {
    if (size < 1 ||
        this.alignment < 1 ||
        this.alignment & (this.alignment - 1) != 0 ||
        offset < 0 ||
        offset % this.alignment != 0) {
      throw ArgumentError('Invalid native stack slot.');
    }
  }
}
