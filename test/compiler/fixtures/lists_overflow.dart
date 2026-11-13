void main() {
  for (final length in [
    0x4000000000000000,
    // Fits the size encoding but exceeds the supported targets' address space.
    0x100000000000000,
  ]) {
    var cleaned = false;
    try {
      try {
        List<int>.filled(length, 1);
      } finally {
        cleaned = true;
      }
    } on OutOfMemoryError catch (error, trace) {
      print(
        '$cleaned:${error.stackTrace == null}:${identical(trace, StackTrace.empty)}',
      );
    }
  }
  List<int>.filled(0x4000000000000000, 1);
}
