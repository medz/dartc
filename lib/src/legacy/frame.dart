// Final code and stack layout for one emitted function. A negative frame size
// marks the frameless startup boundary; unwinding must stop there.
class EmittedFrame {
  final int start;
  final int end;
  final int bytes;
  final int savedOffset;
  final int savedMask;
  final int function;

  EmittedFrame(
    this.start,
    this.end,
    this.bytes,
    this.savedOffset,
    this.savedMask,
    this.function,
  );
}

final List<EmittedFrame> emittedFrames = <EmittedFrame>[];

// One potentially throwing call and its exceptional edge-copy trampoline.
class EmittedHandler {
  int returnOffset = -1;
  int landingOffset = -1;
}

final List<EmittedHandler> emittedHandlers = <EmittedHandler>[];

int alignFrame(int size) => (size + 15) & -16;
