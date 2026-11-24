/// The functions of C that programs can make.
///
/// As many as there can be at once exist from the start, one after the other.
abstract final class Callbacks() {
  static const count = 2048, entryBytes = 8;

  /// What each does is told by a word: in the low 32 bits how many bytes are
  /// passed on the stack, then whether it is done later, and then a number that
  /// tells which of those that were made one after the other it is.
  static const infoBytes = 8, listenerBit = 32, numberShift = 33;

  /// A call that is done later: the next one, what its function was, the word
  /// for that, then its block, without what is on the stack, and that.
  static const postedNext = 0, postedSlot = 8, postedInfo = 16;
  static const postedBlock = 24;
}
