/// Where a call of a C function leaves what is in registers and on the stack.
///
/// Calls are made from such a block, and what C calls finds one.
abstract final class CallBlock() {
  /// The registers for words, for doubles, and for where results go.
  static const words = 0, floats = 64, resultAddress = 128;

  /// The address of the function, and how many bytes of the stack there are,
  /// which are a multiple of 16.
  static const target = 136, stackBytes = 144;

  /// The results in registers for words and for doubles.
  static const resultWords = 160, resultFloats = 176;

  /// What is passed on the stack.
  static const stack = 208;

  /// What can be passed there.
  static const largestStack = 2048;
  static const size = stack + largestStack;
}
