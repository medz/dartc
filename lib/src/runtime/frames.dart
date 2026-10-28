import '../layout.dart';
import '../runtime.dart';

// Returns the immutable descriptor containing pc, or zero for an address
// outside generated Dart code. The startup descriptor has a negative size.
@pragma('dartc:no-gc')
int rtFrameDescriptor(int pc) {
  final metadata = nativeMetadataAddress(metadataFrames);
  final table = metadata + nativeLoad64(metadata + metadataFrameTableOffset);
  final count = nativeLoad64(table + frameTableCountOffset);
  final frames = table + nativeLoad64(table + frameTableDescriptorsOffset);
  var low = 0;
  var high = count;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final record = frames + middle * frameDescriptorBytes;
    final start = record + nativeLoad64(record + frameStartOffset);
    if (start <= pc)
      low = middle + 1;
    else
      high = middle;
  }
  if (low == 0) return 0;
  final record = frames + (low - 1) * frameDescriptorBytes;
  final end = record + nativeLoad64(record + frameEndOffset);
  return pc < end ? record : 0;
}

// Start with the caller of frame. The supplied frame and its callers stay on
// the native stack throughout capture; allocations only grow the stack below
// them. A return PC is looked up before following FP, including at startup.
String rtStackTraceString(int frame) {
  final trace = StringBuffer();
  var depth = 0;
  while (true) {
    final pc = nativeLoad64(frame + 8);
    final descriptor = rtFrameDescriptor(pc);
    if (descriptor == 0) rtHostExit(70);
    if (nativeLoad64(descriptor + frameSizeOffset) < 0) return trace.toString();
    final name = descriptor + nativeLoad64(descriptor + frameNameOffset);
    trace.write('#');
    trace.write(depth);
    trace.write(' ');
    trace.writeln(nativeValueFromBits(name) as String);
    depth++;
    frame = nativeLoad64(frame);
  }
}
