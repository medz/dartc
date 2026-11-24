import 'call_block.dart';
import 'convention.dart';
import 'types.dart';

/// How functions are called on ARM64, by Apple's convention or by the standard
/// one.
final class Arm64Passing({required final bool isApple}) extends Convention {
  @override
  int get wordRegisters => 8;
  @override
  int get floatRegisters => 8;

  /// The place of a value that is no struct, on the stack. Apple's takes no more
  /// than it needs.
  int _stackScalar(NativeType type) =>
      isApple ? takeStack(type.size, type.alignment) : takeStack(8, 8);

  @override
  Passing parameter(NativeType type) {
    switch (type) {
      case NativeFloating():
        final place = freeFloats > 0 ? takeFloat() : _stackScalar(type);
        return Convention.whole(type, place);
      case NativeCompound():
        return _compound(type);
      default:
        final place = freeWords > 0 ? takeWord() : _stackScalar(type);
        return Convention.whole(type, place);
    }
  }

  Passing _compound(NativeCompound type) {
    if (_homogeneous(type) case (:final size, :final count)) {
      if (freeFloats >= count) {
        return InPieces([
          for (var i = 0; i < count; i++)
            (offset: i * size, size: size, place: takeFloat()),
        ]);
      }
      takeAllFloats();
      final place = isApple
          ? takeStack(type.size, size)
          : takeStack(alignTo(type.size, 8), 8);
      return Convention.whole(type, place);
    }
    if (type.size > 16) {
      return ByAddress(freeWords > 0 ? takeWord() : takeStack(8, 8));
    }
    final words = (type.size + 7) ~/ 8;
    if (freeWords >= words) return _pieces(type, takeWord);
    takeAllWords();
    return Convention.whole(type, takeStack(words * 8, 8));
  }

  /// [type] in words that [next] gives.
  static Passing _pieces(NativeType type, int Function() next) => InPieces([
    for (var at = 0; at < type.size; at += 8)
      (
        offset: at,
        size: type.size - at < 8 ? type.size - at : 8,
        place: next(),
      ),
  ]);

  /// Apple's variable arguments are on the stack.
  @override
  Passing variable(NativeType type) {
    if (!isApple) return parameter(type);
    if (type is NativeCompound && type.size > 16) {
      return ByAddress(takeStack(8, 8));
    }
    return Convention.whole(type, takeStack(alignTo(type.size, 8), 8));
  }

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
    if (_homogeneous(type) case (:final size, :final count)) {
      return InPieces([
        for (var i = 0; i < count; i++)
          (offset: i * size, size: size, place: CallBlock.resultFloats + i * 8),
      ]);
    }
    if (type.size > 16) return const ByAddress(CallBlock.resultAddress);
    var place = CallBlock.resultWords;
    return _pieces(type, () => (place += 8) - 8);
  }
}

/// The type that all the up to four parts of [type] have, and how many there
/// are, if they are passed like as many doubles.
({int size, int count})? _homogeneous(NativeType type) {
  final parts = _floatsOf(type);
  if (parts == null || parts.isEmpty || parts.length > 4) return null;
  final size = parts.first;
  return parts.every((part) => part == size) && size * parts.length == type.size
      ? (size: size, count: parts.length)
      : null;
}

/// The sizes of the floating point numbers that [type] is made of, or null if
/// there is anything else.
List<int>? _floatsOf(NativeType type) {
  switch (type) {
    case NativeFloating(:final size):
      return [size];
    case NativeArray(:final element, :final count):
      final inner = _floatsOf(element);
      if (inner == null || inner.length * count > 4) return null;
      return [for (var i = 0; i < count; i++) ...inner];
    case NativeCompound(:final fields, :final isUnion):
      final all = fields.map(_floatsOf).toList();
      if (all.contains(null)) return null;
      if (!isUnion) return [for (final part in all) ...part!];
      var longest = const <int>[];
      for (final part in all) {
        if (part!.length > longest.length) longest = part;
      }
      // The parts of a union have to be of one type.
      final size = longest.firstOrNull;
      return all.every((part) => part!.every((own) => own == size))
          ? longest
          : null;
    default:
      return null;
  }
}
