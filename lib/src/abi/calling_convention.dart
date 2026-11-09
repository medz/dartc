import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'call_layout.dart';
import 'frame_layout.dart';

/// Classifies native calls and stack frames for one explicit target.
abstract interface class CallingConvention<R>() {
  /// The platform whose calling rules apply.
  Target get target;

  /// Assigns parameter and result locations for a supported native signature.
  CallLayout<R> classify(NativeSignature signature);

  /// Places local storage, outgoing arguments and saved registers in one frame.
  FrameLayout<R> frameLayout({
    required int localBytes,
    required int localAlignment,
    required Iterable<R> savedRegisters,
    required int outgoingStackBytes,
  });
}
