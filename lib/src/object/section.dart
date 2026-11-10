import 'dart:typed_data';

/// The storage and loading permissions of an object section.
enum SectionKind() {
  code,
  readOnlyData,
  data,
  zeroFill,
  finalizers,
}

/// Immutable section contents with independent file and memory sizes.
final class Section._(
  /// The storage permissions and initialization mode.
  final SectionKind kind,
  List<int> bytes,

  /// The number of bytes occupied in memory.
  final int size,

  /// The required power-of-two byte alignment.
  final int alignment,
) {
  /// The initialized bytes; empty for zero-initialized storage.
  final Uint8List bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// Creates executable machine code.
  factory code(List<int> bytes, {int alignment = 16}) =>
      ._(.code, bytes, bytes.length, alignment);

  /// Creates initialized, non-writable data.
  factory readOnlyData(List<int> bytes, {int alignment = 1}) =>
      ._(.readOnlyData, bytes, bytes.length, alignment);

  /// Creates initialized, writable data.
  factory data(List<int> bytes, {int alignment = 1}) =>
      ._(.data, bytes, bytes.length, alignment);

  /// Creates loader finalizer pointers, each supplied by an address relocation.
  factory finalizers(List<int> bytes) =>
      ._(.finalizers, bytes, bytes.length, 8);

  /// Reserves writable memory initialized to zero, without file contents.
  factory zeroFill(int size, {int alignment = 1}) =>
      ._(.zeroFill, const [], size, alignment);

  this {
    RangeError.checkNotNegative(size, 'size');
    if (kind == .finalizers && size % 8 != 0) {
      throw ArgumentError('Finalizers require whole 8-byte pointers.');
    }
    if (alignment <= 0 || alignment & (alignment - 1) != 0) {
      throw ArgumentError.value(
        alignment,
        'alignment',
        'Expected a power of two.',
      );
    }
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Expected bytes in the range 0..255.');
    }
  }
}
