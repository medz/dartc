import 'package:dartc/target.dart';

/// Immutable stack positions measured from SP after the prologue.
///
/// Layouts come from a calling convention's frame query. Outgoing arguments
/// begin at offset zero. Frame and return-address preservation are included in
/// [savedRegisters], without consuming the requested local storage.
final class FrameLayout<R>._(
  final Target target, {

  /// The total reduction of SP from function entry to the body.
  required final int stackBytes,

  /// The beginning of the local storage region.
  required final int localOffset,

  /// The requested local storage size.
  required final int localBytes,

  /// The reserved outgoing argument area.
  required final int outgoingStackBytes,

  /// The start of incoming stack arguments relative to the body SP.
  required final int incomingStackOffset,

  /// The saved return address relative to SP after the prologue.
  required final int returnAddressOffset,
  required Map<R, int> savedRegisters,
}) {
  /// Saved register positions, including the platform frame record.
  final Map<R, int> savedRegisters = Map.unmodifiable(savedRegisters);
}

FrameLayout<R> scalarFrame<R>(
  Target target, {
  required int localBytes,
  required int localAlignment,
  required Iterable<R> savedRegisters,
  required int outgoingStackBytes,
  required List<R> frameRegisters,
  required Set<R> calleeSaved,
}) {
  final arm = target.architecture == .arm64;
  final limit = arm ? 0xffffe0 : 0x7ffffff0;
  RangeError.checkValueInInterval(localBytes, 0, limit, 'localBytes');
  RangeError.checkValueInInterval(
    outgoingStackBytes,
    0,
    limit,
    'outgoingStackBytes',
  );
  if (localAlignment <= 0 ||
      localAlignment > 16 ||
      localAlignment & (localAlignment - 1) != 0) {
    throw ArgumentError(
      'Expected a power-of-two alignment of at most 16 bytes.',
    );
  }
  final localOffset =
      (outgoingStackBytes + localAlignment - 1) & -localAlignment;
  var offset = (localOffset + localBytes + 7) & ~7;
  final positions = <R, int>{};
  for (final register in savedRegisters) {
    if (!calleeSaved.contains(register) || positions.containsKey(register)) {
      throw ArgumentError('Invalid or duplicate saved register: $register');
    }
    positions[register] = offset;
    offset += 8;
  }
  offset = (offset + 15) & ~15;
  if (offset > limit) {
    throw ArgumentError('Frame exceeds the supported stack range.');
  }
  for (final register in frameRegisters) {
    positions[register] = offset;
    offset += 8;
  }
  final stackBytes = offset;
  final incomingStackOffset = stackBytes + (arm ? 0 : 8);
  return FrameLayout._(
    target,
    stackBytes: stackBytes,
    localOffset: localOffset,
    localBytes: localBytes,
    outgoingStackBytes: outgoingStackBytes,
    incomingStackOffset: incomingStackOffset,
    returnAddressOffset: stackBytes - (arm ? 8 : 0),
    savedRegisters: positions,
  );
}
