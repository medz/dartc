import 'dart:typed_data';

import 'signature.dart';

/// The checked query and terminal leaf owning one module's runtime context.
///
/// This marks explicit compiler-introduced ownership; ordinary native data and
/// ABI register bindings never acquire this contract by their shape or address.
final class NativeContextOwner(
  final FunctionTarget? query,
  final FunctionTarget failure,
);

/// One identity-bearing native storage block initialized when a module loads.
///
/// Equal contents do not merge declarations or their addresses. Address reads do
/// not repeat initialization; writes to a writable block persist until unload.
/// These are untraced bytes, not a managed object or a root registration.
final class NativeData(
  List<int> bytes, {

  /// The required power-of-two target byte alignment.
  final int alignment = 1,

  /// Whether the loader permits subsequent writes to the storage.
  final bool writable = true,

  /// Explicit runtime ownership, when this storage is a native lifecycle context.
  final NativeContextOwner? contextOwner,
}) {
  /// Immutable initial contents, copied independently of the caller's list.
  final Uint8List bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  this {
    if (bytes.isEmpty || bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Native data requires nonempty bytes in 0..255.');
    }
    if (alignment <= 0 || alignment & (alignment - 1) != 0) {
      throw ArgumentError('Native data alignment must be a power of two.');
    }
  }
}
