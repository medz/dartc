import 'call_block.dart';
import 'types.dart';

/// Some bytes of a value, from an offset on, which are at a place in the block
/// of a call.
typedef Piece = ({int offset, int size, int place});

/// How a value is passed.
sealed class const Passing();

/// In parts, which are in registers or on the stack.
final class const InPieces(final List<Piece> pieces) extends Passing;

/// By its address, which is at [place].
///
/// A result's address is also what the function gives at [returned], if it
/// gives that.
final class const ByAddress(final int place, {final int? returned})
    extends Passing;

/// Finds out how the values of one call are passed, in order.
abstract base class Convention() {
  int _words = 0, _floats = 0;

  /// How many bytes of the stack are used.
  int stackEnd = 0;

  /// How many registers there are for words and for floating point numbers.
  int get wordRegisters;
  int get floatRegisters;

  int get freeWords => wordRegisters - _words;
  int get freeFloats => floatRegisters - _floats;

  int takeWord() => CallBlock.words + _words++ * 8;
  int takeFloat() => CallBlock.floats + _floats++ * 8;

  /// Leaves no registers for others.
  void takeAllWords() => _words = wordRegisters;
  void takeAllFloats() => _floats = floatRegisters;

  /// Takes [size] bytes of the stack.
  int takeStack(int size, int alignment) {
    final start = alignTo(stackEnd, alignment);
    stackEnd = start + size;
    if (stackEnd > CallBlock.largestStack) {
      throw UnsupportedError('A call with too many arguments.');
    }
    return CallBlock.stack + start;
  }

  Passing parameter(NativeType type);
  Passing variable(NativeType type);
  Passing result(NativeType type);

  static Passing whole(NativeType type, int place) =>
      InPieces([(offset: 0, size: type.size, place: place)]);
}
