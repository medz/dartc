import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'class.dart';
import 'machine.dart';
import 'module.dart';

/// What null is while a program is interpreted.
const Object hirNull = _Null();

final class const _Null() {
  @override
  String toString() => 'null';
}

/// An object of an interpreted program.
final class HirObject(final HirClass target, {int? length}) {
  final fields = <HirField, Object>{};
  late final List<Object> _references;
  late final ByteData _bytes;

  /// Whether nothing may change it.
  bool isConstant = false;

  this {
    for (final field in target.fields) {
      if (field.type == .reference) fields[field] = hirNull;
    }
    switch (target.elements) {
      case null:
        break;
      case .references:
        _references = List.filled(length!, hirNull);
      case .bytes:
        _bytes = ByteData(length!);
    }
  }

  int get length => switch (target.elements) {
    .references => _references.length,
    _ => _bytes.lengthInBytes,
  };

  void checkWritable() {
    if (isConstant) throw StateError('$this is constant.');
  }

  Object load(HirElement element, int index) => switch (element) {
    .reference => _references[index],
    .int8 => _bytes.getInt8(index),
    .uint8 => _bytes.getUint8(index),
    .int16 => _bytes.getInt16(index, .little),
    .uint16 => _bytes.getUint16(index, .little),
    .int32 => _bytes.getInt32(index, .little),
    .uint32 => _bytes.getUint32(index, .little),
    .int64 => _bytes.getInt64(index, .little),
    .float32 => _bytes.getFloat32(index, .little),
    .float64 => _bytes.getFloat64(index, .little),
  };

  void store(HirElement element, int index, Object value) {
    checkWritable();
    switch (element) {
      case .reference:
        _references[index] = value;
      case .int8 || .uint8:
        _bytes.setInt8(index, value as int);
      case .int16 || .uint16:
        _bytes.setInt16(index, value as int, .little);
      case .int32 || .uint32:
        _bytes.setInt32(index, value as int, .little);
      case .int64:
        _bytes.setInt64(index, value as int, .little);
      case .float32:
        _bytes.setFloat32(index, value as double, .little);
      case .float64:
        _bytes.setFloat64(index, value as double, .little);
    }
  }

  @override
  String toString() => target.name;
}

/// The machine that an interpreted program runs on.
final class HirMachineState(final HirModule _module) {
  final _output = BytesBuilder(), _errors = BytesBuilder();
  final _memory = <int, int>{};
  final _addresses = Expando<int>();
  int _mapped = 1 << 16, _numbered = 0;

  String get output => utf8.decode(_output.toBytes());
  String get errors => utf8.decode(_errors.toBytes());

  /// Performs [op], returning its result if it has one.
  Object? run(HirMachineOp op, List<Object> inputs) {
    int number(int index) => inputs[index] as int;
    switch (op) {
      case .isSame:
        return identical(inputs[0], inputs[1]);
      case .classNumber:
        return _module.classes.indexOf((inputs.single as HirObject).target);
      case .addressOf:
        return _addresses[inputs.single] ??= ++_numbered * 16;
      case .objectAt:
        throw UnsupportedError('Objects at addresses.');
      case .mapMemory:
        return (_mapped += number(0) + 4096) - number(0);
      case .outputBuffer:
        return 4096;
      case .arguments:
        // Nothing is stored there, so there are none.
        return 16;
      case .nativeFrame:
        return 24;
      case .sourcePlaces:
        // There are no frames to tell.
        return 0;
      case .callBlock ||
          .callNative ||
          .callbacks ||
          .callbackInfo ||
          .takePosted ||
          .waitPosted ||
          .newIsolate ||
          .isolateEntry:
        throw UnsupportedError('Calls of C functions.');
      case .write:
        (number(0) == 1 ? _output : _errors).add(_read(number(1), number(2)));
        return null;
      case .formatDouble:
        final text = formatExactly(inputs[0] as double, number(1));
        for (final (i, byte) in [...ascii.encode(text), 0].indexed) {
          _memory[number(2) + i] = byte;
        }
        return null;
      case .parseDouble:
        var count = 0;
        while ((_memory[number(0) + count] ?? 0) != 0) {
          count++;
        }
        return double.parse(ascii.decode(_read(number(0), count)));
      case .realTime:
        return DateTime.now().microsecondsSinceEpoch * 1000;
      case .steadyTime:
        return ++_passed * 1000;
      case .randomBits:
        return Random().nextInt(1 << 32);
      case .pause:
        _passed += number(0);
        return null;
      case .localTime:
        _localTime(number(0));
        return null;
      case .load8 || .load16 || .load64 || .loadSingle || .loadDouble:
        return _load(op, number(0));
      case .store8 || .store16 || .store64 || .storeSingle || .storeDouble:
        _store(op, number(0), inputs[1]);
        return null;
      default:
        return _function(op, [
          for (final input in inputs)
            if (input is double) input,
        ]);
    }
  }

  /// The microseconds that passed for the program, which take no time here.
  ///
  /// Each time that it asks, it finds that one passed.
  int _passed = 0;

  double _function(HirMachineOp op, List<double> inputs) => switch (op) {
    .sine => sin(inputs[0]),
    .cosine => cos(inputs[0]),
    .tangent => tan(inputs[0]),
    .arcSine => asin(inputs[0]),
    .arcCosine => acos(inputs[0]),
    .arcTangent => atan(inputs[0]),
    .exponential => exp(inputs[0]),
    .logarithm => log(inputs[0]),
    .arcTangent2 => atan2(inputs[0], inputs[1]),
    .power => pow(inputs[0], inputs[1]).toDouble(),
    _ => throw StateError('${op.name} is not simulated.'),
  };

  /// Of what the system tells about a time, only its zone.
  void _localTime(int address) {
    final seconds = ByteData.sublistView(_read(address, 8))
        .getInt64(0, .little);
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final name = address + 200;
    final zone = ByteData(16)
      ..setInt64(0, time.timeZoneOffset.inSeconds, .little)
      ..setInt64(8, name, .little);
    for (var i = 0; i < 16; i++) {
      _memory[address + 48 + i] = zone.getUint8(i);
    }
    for (final (i, byte) in [...ascii.encode(time.timeZoneName), 0].indexed) {
      _memory[name + i] = byte;
    }
  }

  Object _load(HirMachineOp op, int address) {
    final bytes = ByteData.sublistView(_read(address, 8));
    return switch (op) {
      .load8 => bytes.getUint8(0),
      .load16 => bytes.getUint16(0, .little),
      .loadSingle => bytes.getFloat32(0, .little),
      .loadDouble => bytes.getFloat64(0, .little),
      _ => bytes.getInt64(0, .little),
    };
  }

  void _store(HirMachineOp op, int address, Object value) {
    final size = switch (op) {
      .store8 => 1,
      .store16 => 2,
      .storeSingle => 4,
      _ => 8,
    };
    final bytes = ByteData(8);
    switch (op) {
      case .storeSingle:
        bytes.setFloat32(0, value as double, .little);
      case .storeDouble:
        bytes.setFloat64(0, value as double, .little);
      default:
        bytes.setInt64(0, value as int, .little);
    }
    _write(address, ByteData.sublistView(bytes, 0, size));
  }

  void _write(int address, ByteData bytes) {
    for (var i = 0; i < bytes.lengthInBytes; i++) {
      _memory[address + i] = bytes.getUint8(i);
    }
  }

  Uint8List _read(int address, int count) => Uint8List.fromList([
    for (var i = 0; i < count; i++) _memory[address + i] ?? 0,
  ]);
}

/// [value], which is positive and finite, with [digits] significant digits, in
/// one of the forms that programs read.
String formatExactly(double value, int digits) {
  if (digits <= 21) return value.toStringAsExponential(digits - 1);
  // Any double is an integer divided by a power of 2.
  var numerator = value, power = 0;
  while (numerator != numerator.truncateToDouble()) {
    numerator *= 2;
    power++;
  }
  // As many tens as twos leave a whole number.
  final whole = BigInt.from(numerator) * BigInt.from(5).pow(power);
  final text = '$whole';
  final exponent = text.length - 1 - power;
  final kept = text.padRight(digits, '0').substring(0, digits);
  return '${kept[0]}.${kept.substring(1)}e${exponent < 0 ? '-' : '+'}'
      '${exponent.abs()}';
}
