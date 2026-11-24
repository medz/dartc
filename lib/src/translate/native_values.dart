import 'package:analyzer/dart/element/type.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/native.dart';

import 'builder.dart';
import 'conversions.dart';
import 'scope.dart';
import 'types.dart';

/// Converts between values and what C has for them.
final class NativeValues(
  final ProgramScope _scope,
  final FunctionBuilder _builder,
) {
  late final _conversions = Conversions(_scope, _builder);

  HirValue _number(int value) => _builder.add(HirConst(value));

  HirValue _at(HirValue address, int offset) =>
      _builder.add(HirIntBinary(.add, address, _number(offset)));

  HirValue _machine(HirMachineOp op, List<HirValue> arguments) =>
      _builder.add(HirMachine(op, arguments));

  HirValue _call(String name, List<HirValue> arguments) =>
      _builder.call(HirCall(_scope.runtime(name), arguments))!;

  /// Memory for a value of [type], as typed data.
  HirValue newMemory(NativeType type) =>
      _call('newMemory', [_number(type.size)]);

  /// The address of [value], which is a struct or memory.
  HirValue addressOf(HirValue value) => _call('startOf', [value]);

  /// What passing [value], of [type], needs: a number, or memory with it.
  HirValue prepare(
    HirValue value,
    NativeType type, {
    required bool isByAddress,
  }) => switch (type) {
    NativePointer() => _call('pointerAddress', [
      _conversions.coerce(value, .reference),
    ]),
    NativeBoolean() => _builder.choose(
      _conversions.coerce(value, .boolean),
      .integer,
      () => _number(1),
      () => _number(0),
    ),
    NativeInteger() => _conversions.coerce(value, .integer),
    NativeFloating() => _conversions.coerce(value, .float),
    NativeCompound() =>
      isByAddress ? _call('copyOf', [value, _number(type.size)]) : value,
    _ => throw StateError('No value of $type.'),
  };

  /// Stores [value], which [prepare] gave, as [passing] tells.
  void store(HirValue block, Passing passing, NativeType type, HirValue value) {
    switch (passing) {
      case ByAddress(:final place):
        _machine(.store64, [_at(block, place), addressOf(value)]);
      case InPieces(:final pieces) when type is NativeCompound:
        final from = addressOf(value);
        for (final (:offset, :size, :place) in pieces) {
          _call('copyBytes', [
            _at(block, place),
            _at(from, offset),
            _number(size),
          ]);
        }
      case InPieces(:final pieces):
        final (:offset, :size, :place) = pieces.single;
        // In a register, there is room for more.
        final isRegister = place < CallBlock.stack && type is! NativeFloating;
        storeScalar(
          _at(block, place),
          type,
          value,
          width: isRegister ? 8 : type.size,
        );
    }
  }

  /// Stores a number at [address], as one of [width] bytes.
  void storeScalar(
    HirValue address,
    NativeType type,
    HirValue value, {
    int? width,
  }) {
    final size = width ?? type.size;
    if (type is NativeFloating) {
      _machine(size == 4 ? .storeSingle : .storeDouble, [address, value]);
      return;
    }
    final op = switch (size) {
      1 => HirMachineOp.store8,
      2 => HirMachineOp.store16,
      4 => HirMachineOp.store32,
      _ => HirMachineOp.store64,
    };
    final extended = size > type.size ? narrow(value, type) : value;
    _machine(op, [address, extended]);
  }

  /// [value] as one of [type] has it, extended to 64 bits.
  HirValue narrow(HirValue value, NativeType type) {
    if (type is! NativeInteger || type.size == 8) return value;
    final bits = _number(64 - type.size * 8);
    final high = _builder.add(HirIntBinary(.shiftLeft, value, bits));
    return _builder.add(
      HirIntBinary(
        type.isSigned ? .shiftRight : .shiftRightUnsigned,
        high,
        bits,
      ),
    );
  }

  /// What is stored in [block] as [passing] tells, as a value of [type] that
  /// has [dartType].
  HirValue load(
    HirValue block,
    Passing passing,
    NativeType type,
    DartType dartType,
  ) {
    switch (passing) {
      case ByAddress(:final place):
        final from = _machine(.load64, [_at(block, place)]);
        final memory = newMemory(type);
        _call('copyBytes', [addressOf(memory), from, _number(type.size)]);
        return wrap(memory, dartType);
      case InPieces(:final pieces) when type is NativeCompound:
        final memory = newMemory(type);
        final to = addressOf(memory);
        for (final (:offset, :size, :place) in pieces) {
          _call('copyBytes', [
            _at(to, offset),
            _at(block, place),
            _number(size),
          ]);
        }
        return wrap(memory, dartType);
      case InPieces(:final pieces):
        return loadScalar(_at(block, pieces.single.place), type, dartType);
    }
  }

  /// The number at [address], as a value that has [dartType].
  HirValue loadScalar(HirValue address, NativeType type, DartType dartType) {
    switch (type) {
      case NativeFloating(:final size):
        return _machine(size == 4 ? .loadSingle : .loadDouble, [address]);
      case NativeBoolean():
        final value = _machine(.load8, [address]);
        return _builder.add(HirCompare(.notEqual, value, _number(0)));
      case NativePointer():
        return pointer(_machine(.load64, [address]), dartType);
      case NativeInteger(:final size):
        final value = _machine(
          switch (size) {
            1 => .load8,
            2 => .load16,
            4 => .load32,
            _ => .load64,
          },
          [address],
        );
        return narrow(value, type);
      default:
        throw StateError('No number of $type.');
    }
  }

  /// The pointer to [address], which has [type].
  HirValue pointer(HirValue address, DartType type) {
    final arguments = type is InterfaceType
        ? type.typeArguments
        : [_conversions.types.neverType];
    final types = _scope.typeList(_builder, arguments);
    if (types == null) throw StateError('No $type.');
    return _call('fromAddress', [types, address]);
  }

  /// The struct or union of [type] that is in [base], from [offset] on.
  HirValue wrap(HirValue base, DartType type, [HirValue? offset]) {
    final element = (boundOf(type) as InterfaceType).element;
    final class_ = _scope.createdClass(element);
    final object = _builder.create(class_);
    for (final field in class_.fields) {
      _builder.add(
        HirStore(field, object, switch (field.name) {
          '_typedDataBase' => base,
          '_offsetInBytes' => offset ?? _number(0),
          _ => throw StateError('A field ${field.name} in a struct.'),
        }),
      );
    }
    return object;
  }
}
