import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'memory.dart';
import 'stack_frames.dart';

/// Captures the calling Dart frame before entering the allocating stack walker.
@Primitive(.captureStackTrace)
external StackTrace currentStackTrace();

/// An immutable snapshot; its links remain traced after the original stack exits.
final class CapturedStackTrace(
  final int pc,
  final CapturedStackTrace? caller,
  final String? description,
) implements StackTrace {
  @override
  String toString() {
    final names = <String>[];
    for (
      CapturedStackTrace? frame = this;
      frame != null;
      frame = frame.caller
    ) {
      names.add(frame.description ?? '0x${frame.pc.toRadixString(16)}');
    }
    return [
      for (var i = names.length - 1; i >= 0; i--)
        '#${names.length - i - 1} ${names[i]}',
    ].join('\n');
  }
}

@RuntimeEntry(.captureStackTrace)
StackTrace captureStackTrace(int sp, int pc) {
  final frames = StackFrames(Memory.context())..start(sp, pc);
  CapturedStackTrace? head;
  while (frames.moveNext()) {
    if (!frames.isBoundary) {
      head = CapturedStackTrace(frames.pc, head, frames.description);
    }
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
