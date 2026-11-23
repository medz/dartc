// Throwing leaves the functions between the throw and the innermost call that
// has a handler. They need not do anything themselves.
import 'machine.dart';
import 'returns.dart';

/// Throws [exception] with [trace].
Never raise(Object exception, Object trace) {
  var frame = frameAddress();
  while (frame != 0) {
    // A frame starts with the caller's, then where it returns to.
    final target = findReturn(handlers(), load64(frame + 8) - codeStart());
    frame = load64(frame);
    if (target != 0) resume(frame, codeStart() + target, exception, trace);
  }
  trap();
}
