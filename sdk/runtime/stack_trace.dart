import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'memory.dart';
import 'stack_frames.dart';

/// Captures the calling Dart frame before entering the allocating stack walker.
@Primitive(.captureStackTrace)
external StackTrace currentStackTrace();

/// An immutable snapshot; its links remain traced after the original stack exits.
final class CapturedStackTrace(final int pc, final CapturedStackTrace? caller)
    implements StackTrace {
  @override
  String toString() {
    final addresses = <int>[];
    for (
      CapturedStackTrace? frame = this;
      frame != null;
      frame = frame.caller
    ) {
      addresses.add(frame.pc);
    }
    return [
      for (var i = addresses.length - 1; i >= 0; i--)
        '#${addresses.length - i - 1} 0x${addresses[i].toRadixString(16)}',
    ].join('\n');
  }
}

@RuntimeEntry(.captureStackTrace)
StackTrace captureStackTrace(int sp, int pc) {
  final frames = StackFrames(Memory.context())..start(sp, pc);
  CapturedStackTrace? head;
  while (frames.moveNext()) {
    if (!frames.isBoundary) head = CapturedStackTrace(frames.pc, head);
  }
  return head ?? StackTrace.empty;
}

int _traceOffset(Object error) {
  final descriptor = Memory.read(
    Memory.addressOf(error) + ObjectHeader.descriptorOffset,
  );
  final references = Memory.read(
    descriptor + ObjectDescriptor.referenceCount * 8,
  );
  return Memory.read(
    descriptor + (ObjectDescriptor.traceBase + references) * 8,
  );
}

/// Reads runtime trace storage without invoking an override of Error.stackTrace.
StackTrace? errorTrace(Object error) {
  final offset = _traceOffset(error);
  return offset == 0
      ? null
      : Memory.readReference(error, offset) as StackTrace?;
}

/// Records only the first throw on Error subclasses, including explicit traces.
@RuntimeEntry(.recordError)
@NonAllocating()
void recordError(Object error, StackTrace trace) {
  final offset = _traceOffset(error);
  if (offset != 0 && Memory.readReference(error, offset) == null) {
    Memory.writeReference(error, offset, trace);
  }
}
