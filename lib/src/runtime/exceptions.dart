import '../layout.dart';
import '../runtime.dart';
import 'frames.dart';

// The current runtime has one execution domain. Managed fields retain pending
// values while the stack is unwound; catch entries copy them into local roots.
class _ExceptionState {
  Object? value;
  StackTrace? trace;
  int context = 0;
}

final _ExceptionState _state = _ExceptionState();

Object rtExceptionValue() => _state.value!;
StackTrace rtExceptionTrace() => _state.trace!;

int rtClearPendingException() {
  _state.value = null;
  _state.trace = null;
  return 0;
}

Never rtRaiseException(Object value, StackTrace trace) {
  final state = _state;
  state.value = value;
  state.trace = trace;
  if (state.context == 0) state.context = rtMap(unwindContextBytes);
  final context = state.context;
  nativeCaptureContext(context);
  rtUnwindContext(context);
  rtWriteExceptionText('Unhandled exception:\n');
  rtWriteExceptionText(value.toString());
  rtWriteExceptionText('\n');
  rtWriteExceptionText(trace.toString());
  nativeExit(255);
}

void rtWriteExceptionText(String text) {
  final encoded = rtStringEncodeUtf8(nativeValueBits(text));
  rtWriteAll(2, encoded + 8, nativeLoad64(encoded));
  rtUtf8Release();
}

@pragma('dartc:no-gc')
int rtExceptionHandler(int pc) {
  final metadata = nativeMetadataAddress(metadataHandlers);
  final table = metadata + nativeLoad64(metadata + metadataHandlerTableOffset);
  final entries = table + nativeLoad64(table + handlerTableEntriesOffset);
  var low = 0;
  var high = nativeLoad64(table + handlerTableCountOffset);
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final record = entries + middle * handlerEntryBytes;
    final address = record + nativeLoad64(record + handlerReturnOffset);
    if (address == pc)
      return record + nativeLoad64(record + handlerLandingOffset);
    if (address < pc)
      low = middle + 1;
    else
      high = middle;
  }
  return 0;
}

// The captured register set belongs to the initial frame. Undo each frame's
// actual saves before inspecting its caller. Resume at a fixed frame SP, even
// if the throwing call had placed extra arguments below that frame.
@pragma('dartc:no-gc')
int rtUnwindContext(int context) {
  var frame = nativeLoad64(context + unwindFrameOffset);
  var descriptor = rtFrameDescriptor(nativeLoad64(context + unwindPcOffset));
  if (descriptor == 0) nativeExit(70);
  while (nativeLoad64(descriptor + frameSizeOffset) >= 0) {
    var saved = frame + nativeLoad64(descriptor + frameSavedOffset);
    var mask = nativeLoad64(descriptor + frameSavedMaskOffset);
    var register = unwindRegistersOffset;
    while (register < unwindContextBytes) {
      if ((mask & 1) != 0) {
        nativeStore64(context + register, nativeLoad64(saved));
        saved -= 8;
      }
      mask >>>= 1;
      register += 8;
    }
    final pc = nativeLoad64(frame + 8);
    descriptor = rtFrameDescriptor(pc);
    if (descriptor == 0) nativeExit(70);
    final size = nativeLoad64(descriptor + frameSizeOffset);
    if (size < 0) return 0;
    frame = nativeLoad64(frame);
    nativeStore64(context + unwindFrameOffset, frame);
    nativeStore64(context + unwindStackOffset, frame - size);
    nativeStore64(context + unwindPcOffset, pc);
    final landing = rtExceptionHandler(pc);
    if (landing != 0) {
      nativeStore64(context + unwindPcOffset, landing);
      nativeResumeContext(context);
    }
  }
  nativeExit(70);
}
