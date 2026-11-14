import 'dart:ffi';

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
  /// Adds an asynchronous gap followed by the next suspended frame.
  CapturedStackTrace followedBy(String description) =>
      CapturedStackTrace(0, CapturedStackTrace(0, this, null), description);

  @override
  String toString() {
    final names = <String>[];
    for (
      CapturedStackTrace? frame = this;
      frame != null;
      frame = frame.caller
    ) {
      names.add(
        frame.description ??
            (frame.pc == 0
                ? '<asynchronous suspension>'
                : '0x${frame.pc.toRadixString(16)}'),
      );
    }
    var index = 0;
    return [
      for (final frame in names.reversed)
        for (final name in frame.split('\n'))
          name == '<asynchronous suspension>' ? name : '#${index++} $name',
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
      var context = frames.continuation;
      if (context is Function) {
        final visited = Set<Function>.identity();
        while (context is Function && visited.add(context)) {
          context = closureLink(context);
        }
      }
      if (context is AsyncStack) {
        final async = context.asynchronousCaller(head);
        if (async != null) return async;
      }
    }
  }
  return head ?? StackTrace.empty;
}

/// A suspended SDK continuation whose links remain in ordinary Dart storage.
@StackContext()
abstract interface class AsyncStack() {
  CapturedStackTrace? asynchronousCaller(CapturedStackTrace synchronous);
}

int _closureMetadata(Function closure) {
  final descriptor = Pointer<Int64>.fromAddress(Memory.addressOf(closure))
      .value;
  final references = Pointer<Int64>.fromAddress(
    descriptor + ObjectDescriptor.referenceCount * 8,
  ).value;
  return Pointer<Int64>.fromAddress(
    descriptor + (ObjectDescriptor.asyncBase + references) * 8,
  ).value;
}

/// Reads a compiler-described capture without evaluating a late initializer.
Object? closureLink(Function closure) {
  final metadata = _closureMetadata(closure);
  if (metadata == 0) return null;
  final link = Pointer<Int64>.fromAddress(metadata + ClosureTraceMetadata.link)
      .value;
  if (link == 0) return null;
  final value = Memory.readReference(closure, link);
  final offset = Pointer<Int64>.fromAddress(
    metadata + ClosureTraceMetadata.value,
  ).value;
  if (value == null || offset == 0) return value;
  final bound = Pointer<Int64>.fromAddress(
    metadata + ClosureTraceMetadata.bound,
  ).value;
  if (bound != 0 &&
      Pointer<Int64>.fromAddress(Memory.addressOf(value) + bound).value == 0) {
    return null;
  }
  return Memory.readReference(value, offset);
}

/// The source callable behind a continuation, if it has source provenance.
String? closureDescription(Function closure) {
  final metadata = _closureMetadata(closure);
  if (metadata == 0) return null;
  final name = Pointer<Int64>.fromAddress(
    metadata + ClosureTraceMetadata.description,
  ).value;
  return name == 0 ? null : Memory.objectAt<String>(name);
}

int _traceOffset(Object error) {
  final descriptor = Pointer<Int64>.fromAddress(
    Memory.addressOf(error) + ObjectHeader.descriptorOffset,
  ).value;
  final references = Pointer<Int64>.fromAddress(
    descriptor + ObjectDescriptor.referenceCount * 8,
  ).value;
  return Pointer<Int64>.fromAddress(
    descriptor + (ObjectDescriptor.traceBase + references) * 8,
  ).value;
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
