import '../layout.dart';
import '../runtime.dart';

Never rtRootFailure() => rtHostExit(70);

int rtRootValues = 0;
int rtRootCount = 0;
int rtRootCapacity = 0;
int rtGlobalRoots = 0;
int rtGlobalRootCount = 0;
int rtGlobalRootCapacity = 0;

@pragma('dartc:no-gc')
int rtRootBuffer(int previous, int count, int capacity) {
  var buffer = rtMap(capacity * 16);
  var i = 0;
  while (i < count) {
    nativeStore64(buffer + i * 16, nativeLoad64(previous + i * 16));
    nativeStore64(buffer + i * 16 + 8, nativeLoad64(previous + i * 16 + 8));
    i = i + 1;
  }
  return buffer;
}

@pragma('dartc:no-gc')
int rtRootMark() {
  return rtRootCount;
}

@pragma('dartc:no-gc')
int rtRootPush(int value, int kind) {
  if (kind == storageRef) {
    if (value == 0) return 0;
  } else if (kind == storageTagged) {
    if (value <= valueTrue || (value & 1) != 0) return 0;
  } else {
    return rtRootFailure();
  }
  if (rtRootCount == rtRootCapacity) {
    var capacity = rtRootCapacity * 2;
    if (capacity == 0) capacity = 1024;
    var previous = rtRootValues;
    var oldCapacity = rtRootCapacity;
    rtRootValues = rtRootBuffer(previous, rtRootCount, capacity);
    rtRootCapacity = capacity;
    rtUnmap(previous, oldCapacity * 16);
  }
  var slot = rtRootValues + rtRootCount * 16;
  nativeStore64(slot, value);
  nativeStore64(slot + 8, kind);
  rtRootCount = rtRootCount + 1;
  return 0;
}

@pragma('dartc:no-gc')
int rtRootPushValue(int value, int type) {
  var representation = nativeLoad64(type + typeValueRepOffset);
  if (representation == storageWord) return 0;
  return rtRootPush(value, representation);
}

@pragma('dartc:no-gc')
int rtRootRestore(int mark) {
  if (mark < 0 || mark > rtRootCount) return rtRootFailure();
  rtRootCount = mark;
  return 0;
}

@pragma('dartc:no-gc')
int rtGlobalRootNew(int value, int kind) {
  if (kind != storageRef && kind != storageTagged) return rtRootFailure();
  if (rtGlobalRootCount == rtGlobalRootCapacity) {
    var capacity = rtGlobalRootCapacity * 2;
    if (capacity == 0) capacity = 1024;
    var previous = rtGlobalRoots;
    var oldCapacity = rtGlobalRootCapacity;
    rtGlobalRoots = rtRootBuffer(previous, rtGlobalRootCount, capacity);
    rtGlobalRootCapacity = capacity;
    rtUnmap(previous, oldCapacity * 16);
  }
  var slot = rtGlobalRoots + rtGlobalRootCount * 16;
  nativeStore64(slot, value);
  nativeStore64(slot + 8, kind);
  rtGlobalRootCount = rtGlobalRootCount + 1;
  return rtGlobalRootCount;
}

@pragma('dartc:no-gc')
int rtGlobalRootValue(int index) {
  if (index <= 0 || index > rtGlobalRootCount) return rtRootFailure();
  return nativeLoad64(rtGlobalRoots + (index - 1) * 16);
}

@pragma('dartc:no-gc')
int rtGlobalRootSet(int index, int value) {
  if (index <= 0 || index > rtGlobalRootCount) return rtRootFailure();
  nativeStore64(rtGlobalRoots + (index - 1) * 16, value);
  return 0;
}

// Native worklist: data0/count8/capacity16. It may grow without entering the
// managed allocator, including while the collector is visiting a large array.
@pragma('dartc:no-gc')
int rtTraceBufferNew() => rtMap(24);

@pragma('dartc:no-gc')
void rtTraceBufferFree(int buffer) {
  rtUnmap(nativeLoad64(buffer), nativeLoad64(buffer + 16) * 8);
  rtUnmap(buffer, 24);
}

@pragma('dartc:no-gc')
void rtTraceAppend(int value, int kind, int buffer) {
  if (kind == storageRef) {
    if (value == 0) return;
  } else if (kind == storageTagged) {
    if (value <= valueTrue || (value & 1) != 0) return;
  } else {
    rtRootFailure();
  }
  final count = nativeLoad64(buffer + 8);
  var data = nativeLoad64(buffer);
  final capacity = nativeLoad64(buffer + 16);
  if (count == capacity) {
    final nextCapacity = capacity == 0 ? 256 : capacity * 2;
    final next = rtMap(nextCapacity * 8);
    for (var i = 0; i < count; i++)
      nativeStore64(next + i * 8, nativeLoad64(data + i * 8));
    rtUnmap(data, capacity * 8);
    data = next;
    nativeStore64(buffer, data);
    nativeStore64(buffer + 16, nextCapacity);
  }
  nativeStore64(data + count * 8, value);
  nativeStore64(buffer + 8, count + 1);
}

@pragma('dartc:no-gc')
void rtTraceRoots(int frame, int buffer) {
  final metadata = nativeMetadataAddress(metadataRoots);
  final table = metadata + nativeLoad64(metadata + metadataRootTableOffset);
  final callCount = nativeLoad64(table + rootTableCallCountOffset);
  final calls = table + nativeLoad64(table + rootTableCallsOffset);
  final globalCount = nativeLoad64(table + rootTableGlobalCountOffset);
  final globals = table + nativeLoad64(table + rootTableGlobalsOffset);
  for (var i = 0; i < rtGlobalRootCount; i++) {
    final slot = rtGlobalRoots + i * 16;
    rtTraceAppend(nativeLoad64(slot), nativeLoad64(slot + 8), buffer);
  }
  for (var i = 0; i < rtRootCount; i++) {
    final slot = rtRootValues + i * 16;
    rtTraceAppend(nativeLoad64(slot), nativeLoad64(slot + 8), buffer);
  }
  for (var i = 0; i < globalCount; i++) {
    final record = globals + i * globalRootBytes;
    final slot = record + nativeLoad64(record + globalRootAddressOffset);
    rtTraceAppend(
      nativeLoad64(slot),
      nativeLoad64(record + globalRootKindOffset),
      buffer,
    );
  }
  while (true) {
    final pc = nativeLoad64(frame + 8);
    var low = 0;
    var high = callCount;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final record = calls + middle * rootCallBytes;
      final returnPc = record + nativeLoad64(record + rootCallReturnOffset);
      if (returnPc < pc)
        low = middle + 1;
      else
        high = middle;
    }
    if (low == callCount) rtRootFailure();
    final call = calls + low * rootCallBytes;
    if (call + nativeLoad64(call + rootCallReturnOffset) != pc) rtRootFailure();
    final roots = nativeLoad64(call + rootCallCountOffset);
    if (roots == -1) return;
    final caller = nativeLoad64(frame);
    if (caller == 0 || roots < 0) rtRootFailure();
    final slots = call + nativeLoad64(call + rootCallSlotsOffset);
    for (var i = 0; i < roots; i++) {
      final record = slots + i * rootSlotBytes;
      rtTraceAppend(
        nativeLoad64(caller + nativeLoad64(record + rootSlotFrameOffset)),
        nativeLoad64(record + rootSlotKindOffset),
        buffer,
      );
    }
    frame = caller;
  }
}

@pragma('dartc:no-gc')
void rtTraceBitmap(int value, int fields, int bitmap, int kind, int buffer) {
  for (var field = 0; field < fields; field += 64) {
    var bits = nativeLoad64(bitmap + (field ~/ 64) * 8);
    var index = field;
    while (bits != 0 && index < fields) {
      if ((bits & 1) != 0)
        rtTraceAppend(
          nativeLoad64(value + objectHeaderBytes + index * 8),
          kind,
          buffer,
        );
      bits >>>= 1;
      index++;
    }
  }
}

@pragma('dartc:no-gc')
void rtTraceType(int type, int buffer) {
  if ((nativeLoad64(type + objectFlagsOffset) & objectStaticRelative) == 0)
    rtTraceAppend(type, storageRef, buffer);
}

// Append strong outgoing edges; the worklist and object remain unmanaged
// addresses throughout this NoGC traversal.
@pragma('dartc:no-gc')
void rtTraceObject(int value, int buffer) {
  if (value == 0) return;
  final descriptor = rtObjectDescriptor(value);
  final kind = nativeLoad64(descriptor + descriptorKindOffset);
  switch (kind) {
    case descriptorString ||
        descriptorIntBox ||
        descriptorDoubleBox ||
        descriptorWordArray:
      return;
    case descriptorList:
      rtTraceAppend(
        nativeLoad64(value + listBackingOffset),
        storageRef,
        buffer,
      );
      rtTraceType(nativeLoad64(value + listTypeOffset), buffer);
    case descriptorType:
      if ((nativeLoad64(value + objectFlagsOffset) & objectStaticRelative) != 0)
        return;
      final typeKind = nativeLoad64(value + typeKindOffset);
      if (typeKind == typeKindList || typeKind == typeKindNullable) {
        rtTraceType(rtTypeArgument(value), buffer);
      } else if (typeKind == typeKindFunction &&
          nativeLoad64(value + typeArgumentOffset) != 0) {
        final signature = rtTypeArgument(value);
        rtTraceType(
          signature + nativeLoad64(signature + functionSignatureResultOffset),
          buffer,
        );
        final count = nativeLoad64(signature + functionSignatureCountOffset);
        for (var i = 0; i < count; i++) {
          final entry = signature + functionSignatureParametersOffset + i * 8;
          rtTraceType(entry + nativeLoad64(entry), buffer);
        }
      }
    case descriptorClass || descriptorFunction:
      if (kind == descriptorFunction)
        rtTraceType(rtFunctionType(value), buffer);
      final fields = nativeLoad64(descriptor + descriptorFieldsOffset);
      final refs = nativeLoad64(descriptor + descriptorRefBitmapOffset);
      final tagged = nativeLoad64(descriptor + descriptorTaggedBitmapOffset);
      if (refs != 0)
        rtTraceBitmap(value, fields, descriptor + refs, storageRef, buffer);
      if (tagged != 0)
        rtTraceBitmap(
          value,
          fields,
          descriptor + tagged,
          storageTagged,
          buffer,
        );
    case descriptorRefArray || descriptorTaggedArray:
      final representation = kind == descriptorRefArray
          ? storageRef
          : storageTagged;
      final length = nativeLoad64(value + arrayLengthOffset);
      for (var i = 0; i < length; i++)
        rtTraceAppend(
          nativeLoad64(value + arrayDataOffset + i * 8),
          representation,
          buffer,
        );
    default:
      rtRootFailure();
  }
}
