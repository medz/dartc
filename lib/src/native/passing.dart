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
final class const ByAddress(final int place) extends Passing;

/// How the values of a call are passed.
typedef CallPassing = ({
  List<Passing> parameters,
  Passing result,
  int stackBytes,
});

/// How functions with [signature] are called on macOS with ARM64.
CallPassing passingOf(NativeSignature signature) {
  final passing = _Passing();
  final parameters = [
    for (final (i, type) in signature.parameters.indexed)
      signature.isVariable(i)
          ? passing.variable(type)
          : passing.parameter(type),
  ];
  return (
    parameters: parameters,
    result: passing.result(signature.result),
    stackBytes: alignTo(passing.stackEnd, 16),
  );
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

final class _Passing() {
  static const _registers = 8;
  int _words = 0, _floats = 0;

  /// How many bytes of the stack are used.
  int stackEnd = 0;

  int _word() => CallBlock.words + _words++ * 8;
  int _float() => CallBlock.floats + _floats++ * 8;

  /// Takes [size] bytes of the stack.
  int _stack(int size, int alignment) {
    final start = alignTo(stackEnd, alignment);
    stackEnd = start + size;
    if (stackEnd > CallBlock.largestStack) {
      throw UnsupportedError('A call with too many arguments.');
    }
    return CallBlock.stack + start;
  }

  /// The place of a value that is no struct, on the stack, where it takes no
  /// more than it needs.
  int _stackScalar(NativeType type) => _stack(type.size, type.alignment);

  Passing parameter(NativeType type) {
    switch (type) {
      case NativeFloating():
        return _whole(
          type,
          _floats < _registers ? _float() : _stackScalar(type),
        );
      case NativeCompound():
        return _compound(type);
      default:
        return _whole(type, _words < _registers ? _word() : _stackScalar(type));
    }
  }

  static Passing _whole(NativeType type, int place) =>
      InPieces([(offset: 0, size: type.size, place: place)]);

  Passing _compound(NativeCompound type) {
    if (_homogeneous(type) case (:final size, :final count)) {
      if (_floats + count <= _registers) {
        return InPieces([
          for (var i = 0; i < count; i++)
            (offset: i * size, size: size, place: _float()),
        ]);
      }
      _floats = _registers;
      return _whole(type, _stack(type.size, size));
    }
    if (type.size > 16) {
      return ByAddress(_words < _registers ? _word() : _stack(8, 8));
    }
    final words = (type.size + 7) ~/ 8;
    if (_words + words <= _registers) return _pieces(type, _word);
    _words = _registers;
    return _whole(type, _stack(words * 8, 8));
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

  /// Variable arguments are on the stack.
  Passing variable(NativeType type) {
    if (type is NativeCompound && type.size > 16) {
      return ByAddress(_stack(8, 8));
    }
    return _whole(type, _stack(alignTo(type.size, 8), 8));
  }

  Passing result(NativeType type) {
    if (type is NativeFloating) return _whole(type, CallBlock.resultFloats);
    if (type is! NativeCompound) {
      return type.size == 0
          ? const InPieces([])
          : _whole(type, CallBlock.resultWords);
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
