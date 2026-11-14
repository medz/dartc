import 'dart:math' as math;

import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

/// Native storage facts for one explicit target, independent of managed layout.
final class NativeLayout(final Target target) {
  /// Computes size, alignment and field offsets, rejecting incomplete or cyclic types.
  /// Storage exceeding positive signed 64-bit byte counts throws [RangeError].
  NativeStorage of(NativeTypeRef type) => _layout(type, {});

  /// Scalar leaves at their native byte offsets; union alternatives may overlap.
  Iterable<({NativeTypeRef type, int offset})> leaves(
    NativeTypeRef type, [
    int offset = 0,
  ]) sync* {
    RangeError.checkNotNegative(offset, 'offset');
    final layout = of(type);
    _add(offset, layout.size);
    switch (type) {
      case NativeCompoundType(:final fields):
        for (final (i, field) in fields.indexed) {
          yield* leaves(field.type, offset + layout.offsets[i]);
        }
      case NativeArrayType(:final element, :final length):
        final stride = of(element).size;
        if (stride == 0) return;
        for (var i = 0; i < length; i++) {
          yield* leaves(element, offset + i * stride);
        }
      default:
        yield (type: type, offset: offset);
    }
  }

  /// Homogeneous floating members under AAPCS64, or null for other aggregates.
  List<({NativeTypeRef type, int offset})>? homogeneous(NativeTypeRef type) {
    of(type);
    List<({NativeTypeRef type, int offset})>? visit(
      NativeTypeRef type,
      int offset,
    ) {
      if (type.isFloating) return [(type: type, offset: offset)];
      final members = <({NativeTypeRef type, int offset})>[];
      if (type case NativeCompoundType(:final fields, :final isUnion)) {
        final layout = of(type);
        for (final (i, field) in fields.indexed) {
          final child = visit(field.type, offset + layout.offsets[i]);
          if (child == null ||
              members.isNotEmpty && members.first.type != child.first.type) {
            return null;
          }
          if (!isUnion) {
            members.addAll(child);
          } else if (child.length > members.length) {
            members
              ..clear()
              ..addAll(child);
          }
        }
      } else if (type case NativeArrayType(:final element, :final length)) {
        final stride = of(element).size;
        for (var i = 0; i < length; i++) {
          final child = visit(element, offset + i * stride);
          if (child == null) return null;
          members.addAll(child);
          if (members.length > 4) return null;
        }
      } else {
        return null;
      }
      return members.isNotEmpty && members.length <= 4 ? members : null;
    }

    return visit(type, 0);
  }

  NativeStorage _layout(NativeTypeRef type, Set<NativeCompoundType> active) {
    switch (type) {
      case NativeAbiIntegerType():
        return _layout(type.resolveAbi(target.abi), active);
      case NativeScalarType() || NativePointerType():
        return NativeStorage._(type.nativeSize, type.nativeSize);
      case NativeArrayType(:final element, :final length):
        final item = _layout(element, active);
        if (item.size != 0 && length > _maxSize ~/ item.size) {
          throw RangeError(
            'Native array storage exceeds the signed 64-bit size range.',
          );
        }
        return NativeStorage._(item.size * length, item.alignment);
      case NativeCompoundType(:final fields, :final isUnion, :final packing):
        if (!active.add(type)) {
          throw ArgumentError('Recursive native value: ${type.name}');
        }
        var size = 0, alignment = 1;
        final offsets = <int>[];
        for (final field in fields) {
          final item = _layout(field.type, active);
          final boundary = math.min(item.alignment, packing ?? item.alignment);
          alignment = math.max(alignment, boundary);
          final offset = isUnion ? 0 : _align(size, boundary);
          offsets.add(offset);
          size = math.max(size, _add(offset, item.size));
        }
        active.remove(type);
        return NativeStorage._(_align(size, alignment), alignment, offsets);
      case NativeFunctionType() || NativeOpaqueType():
        throw UnsupportedError('Native type has no storage: $type');
    }
  }

  static const _maxSize = 0x7fffffffffffffff;

  int _add(int offset, int size) {
    if (offset > _maxSize - size) {
      throw RangeError('Native storage exceeds the signed 64-bit size range.');
    }
    return offset + size;
  }

  int _align(int size, int alignment) => _add(size, (-size) & (alignment - 1));
}

/// Size, required alignment and declaration-order field offsets in bytes.
final class NativeStorage._(
  final int size,
  final int alignment, [
  Iterable<int> offsets = const [],
]) {
  /// Empty for non-compound types.
  final List<int> offsets = .unmodifiable(offsets);
}
