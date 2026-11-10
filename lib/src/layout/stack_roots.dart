import 'dart:typed_data';

/// Stack locations of live managed references while a call is suspended.
///
/// All offsets are bytes from that caller's body SP. A zero [callerStackOffset]
/// ends the managed walk at a native entry. Other records locate the saved
/// return address and the preceding frame's body SP. Incoming stack arguments
/// may occupy root locations beyond [callerStackOffset].
final class StackRoots(
  /// The distance to the preceding caller's body SP, or zero at native entry.
  final int callerStackOffset,

  /// The saved return address location; zero when the walk ends here.
  final int returnAddressOffset,
  Iterable<int> offsets,
) {
  /// Strictly increasing, aligned locations containing initialized references.
  final List<int> offsets = .unmodifiable(offsets);

  this {
    if (callerStackOffset < 0 ||
        callerStackOffset % 8 != 0 ||
        returnAddressOffset < 0 ||
        returnAddressOffset % 8 != 0 ||
        (callerStackOffset == 0
            ? returnAddressOffset != 0
            : returnAddressOffset >= callerStackOffset)) {
      throw ArgumentError('Invalid stack frame linkage.');
    }
    var previous = -1;
    for (final offset in this.offsets) {
      if (offset < 0 ||
          offset % 8 != 0 ||
          offset <= previous ||
          callerStackOffset != 0 && offset == returnAddressOffset) {
        throw ArgumentError('Invalid or repeated stack root offset.');
      }
      previous = offset;
    }
  }

  /// The encoded byte size, including linkage and root count.
  int get size => (3 + offsets.length) * 8;

  /// Writes three little-endian header words followed by the root offsets.
  void writeTo(ByteData data, int offset) {
    RangeError.checkValidRange(offset, offset + size, data.lengthInBytes);
    data
      ..setUint64(offset, callerStackOffset, .little)
      ..setUint64(offset + 8, returnAddressOffset, .little)
      ..setUint64(offset + 16, offsets.length, .little);
    for (final (i, root) in offsets.indexed) {
      data.setUint64(offset + 24 + i * 8, root, .little);
    }
  }

  /// Reads and validates one record within [data].
  factory read(ByteData data, int offset) {
    RangeError.checkValidRange(offset, offset + 24, data.lengthInBytes);
    final count = data.getUint64(offset + 16, .little);
    if (count < 0 || count > (data.lengthInBytes - offset - 24) ~/ 8) {
      throw FormatException('Truncated stack roots.');
    }
    return .new(
      data.getUint64(offset, .little),
      data.getUint64(offset + 8, .little),
      [
        for (var i = 0; i < count; i++)
          data.getUint64(offset + 24 + i * 8, .little),
      ],
    );
  }
}
