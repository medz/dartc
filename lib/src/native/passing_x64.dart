import 'call_block.dart';
import 'convention.dart';
import 'types.dart';

/// How functions are called on x64 systems other than Windows.
final class X64Passing() extends Convention {
  @override
  int get wordRegisters => 6;
  @override
  int get floatRegisters => 8;

  @override
  Passing parameter(NativeType type) {
    switch (type) {
      case NativeFloating():
        final place = freeFloats > 0 ? takeFloat() : takeStack(8, 8);
        return Convention.whole(type, place);
      case NativeCompound():
        final kinds = _kindsOf(type);
        final floats = kinds?.where((isFloat) => isFloat).length ?? 0;
        final words = (kinds?.length ?? 0) - floats;
        if (kinds == null || words > freeWords || floats > freeFloats) {
          final size = alignTo(type.size, 8);
          return Convention.whole(type, takeStack(size, 8));
        }
        return _pieces(type, kinds, takeWord, takeFloat);
      default:
        final place = freeWords > 0 ? takeWord() : takeStack(8, 8);
        return Convention.whole(type, place);
    }
  }

  @override
  Passing variable(NativeType type) => parameter(type);

  @override
  Passing result(NativeType type) {
    if (type is NativeFloating) {
      return Convention.whole(type, CallBlock.resultFloats);
    }
    if (type is! NativeCompound) {
      return type.size == 0
          ? const InPieces([])
          : Convention.whole(type, CallBlock.resultWords);
    }
    final kinds = _kindsOf(type);
    if (kinds == null) {
      return ByAddress(takeWord(), returned: CallBlock.resultWords);
    }
    var word = CallBlock.resultWords, float = CallBlock.resultFloats;
    return _pieces(type, kinds, () => (word += 8) - 8, () => (float += 8) - 8);
  }

  /// The words of [type], which [kinds] tells about.
  static Passing _pieces(
    NativeType type,
    List<bool> kinds,
    int Function() nextWord,
    int Function() nextFloat,
  ) => InPieces([
    for (final (i, isFloat) in kinds.indexed)
      (
        offset: i * 8,
        size: type.size - i * 8 < 8 ? type.size - i * 8 : 8,
        place: isFloat ? nextFloat() : nextWord(),
      ),
  ]);

  /// Whether each word of [type] has only floating point numbers, or null if it
  /// is in memory.
  static List<bool>? _kindsOf(NativeCompound type) {
    if (type.size > 16) return null;
    final kinds = List.filled((type.size + 7) ~/ 8, true);
    return _classify(type, 0, kinds) ? kinds : null;
  }

  /// Finds out about the words that [type] has, at [offset]. Returns whether it
  /// is where it would be without packing.
  static bool _classify(NativeType type, int offset, List<bool> kinds) {
    if (type.size == 0) return true;
    switch (type) {
      case NativeCompound(:final fields, :final offsets):
        for (final (i, field) in fields.indexed) {
          if (!_classify(field, offset + offsets[i], kinds)) return false;
        }
        return true;
      case NativeArray(:final element, :final count):
        for (var i = 0; i < count; i++) {
          if (!_classify(element, offset + i * element.size, kinds)) {
            return false;
          }
        }
        return true;
      default:
        if (offset % type.size != 0) return false;
        if (type is! NativeFloating) kinds[offset ~/ 8] = false;
        return true;
    }
  }
}
