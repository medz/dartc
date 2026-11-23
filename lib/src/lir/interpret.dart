import 'dart:math' as math;
import 'dart:typed_data';

import 'block.dart';
import 'instruction.dart';
import 'memory.dart';
import 'module.dart';
import 'value.dart';
import 'verify.dart';

/// A host implementation of an external function.
typedef LirExternalBody = Object? Function(
  LirMemory memory,
  List<Object?> arguments,
);

/// A throw in the interpreted program that reached the caller.
final class LirException(final LirObject? exception, final LirObject? trace)
    implements Exception;

/// Executes a verified module, checking every LIR precondition.
///
/// Integers and addresses are Dart ints, doubles are doubles and references
/// are a nullable [LirObject]. A program exceeding [maxSteps] faults.
final class LirInterpreter(
  final LirModule module, {
  final Map<String, LirExternalBody> externals = const {},
  final int maxSteps = 10000000,
}) {
  final LirMemory memory = LirMemory();
  final _functions = <String, LirFunction>{};
  final _addresses = <String, int>{};
  final _statics = <String, LirObject>{};
  final _callables = <int, String>{};
  int _steps = 0;

  this {
    verifyModule(module);
    for (final function in module.functions) {
      _functions[function.name] = function;
    }
    for (final data in module.data) {
      final bytes = Uint8List.fromList(data.bytes);
      _addresses[data.name] = memory.map(bytes, writable: data.writable);
    }
    for (final name in module.signatures.keys) {
      // Code has an address but no readable bytes.
      final address = memory.map(Uint8List(0));
      _addresses[name] = address;
      _callables[address] = name;
    }
    for (final static in module.statics) {
      final object = LirObject(static.bytes.length, writable: static.writable);
      object.bytes.setAll(0, static.bytes);
      _statics[static.name] = object;
    }
    for (final static in module.statics) {
      static.references.forEach((offset, target) {
        _statics[static.name]!.references[offset] = _statics[target]!;
      });
    }
    for (final table in module.tables) {
      final words = ByteData(table.functions.length * 4);
      final address = memory.map(words.buffer.asUint8List(), writable: false);
      _addresses[table.name] = address;
      for (final (i, function) in table.functions.indexed) {
        words.setInt32(i * 4, _addresses[function]! - address, .little);
      }
    }
  }

  /// Calls [symbol]; a program throw surfaces as [LirException].
  Object? call(String symbol, [List<Object?> arguments = const []]) {
    final signature =
        module.signatures[symbol] ?? (throw LirFault('No function $symbol.'));
    if (signature.parameters.length != arguments.length) {
      throw LirFault('$symbol takes ${signature.parameters.length} arguments.');
    }
    final function = _functions[symbol];
    if (function != null) return _run(function, arguments);
    final body = externals[symbol] ?? (throw LirFault('No external $symbol.'));
    return body(memory, arguments);
  }

  Object? _run(LirFunction function, List<Object?> arguments) {
    final values = <LirValue, Object?>{};
    var block = function.entry;
    _bind(values, block, arguments);
    while (true) {
      for (final instruction in block.instructions) {
        _step();
        values[instruction] = _evaluate(instruction, values);
      }
      _step();
      final (LirEdge edge, List<Object?> implicit) next;
      switch (block.terminator!) {
        case Return(:final value):
          return value == null ? null : values[value];
        case Throw(:final exception, :final trace):
          throw LirException(
            values[exception] as LirObject?,
            values[trace] as LirObject?,
          );
        case Unreachable():
          throw LirFault('Unreachable code in ${function.name}.');
        case Jump(:final edge):
          next = (edge, const []);
        case Branch(:final condition, :final ifTrue, :final ifFalse):
          next = (values[condition] != 0 ? ifTrue : ifFalse, const []);
        case final Invoke invoke:
          next = _invoke(invoke, values);
      }
      final (edge, implicit) = next;
      block = edge.target;
      _bind(values, block, [
        ...implicit,
        for (final value in edge.arguments) values[value],
      ]);
    }
  }

  (LirEdge, List<Object?>) _invoke(
    Invoke invoke,
    Map<LirValue, Object?> values,
  ) {
    try {
      final result = _evaluate(invoke.call, values);
      return (invoke.onReturn, [if (invoke.call.type != null) result]);
    } on LirException catch (error) {
      return (invoke.onThrow, [error.exception, error.trace]);
    }
  }

  void _bind(
    Map<LirValue, Object?> values,
    LirBlock block,
    List<Object?> arguments,
  ) {
    for (final (i, parameter) in block.parameters.indexed) {
      values[parameter] = arguments[i];
    }
  }

  void _step() {
    if (++_steps > maxSteps) throw LirFault('Step limit reached.');
  }

  Object? _evaluate(LirInstruction instruction, Map<LirValue, Object?> values) {
    int integer(LirValue value) => values[value] as int;
    double float(LirValue value) => values[value] as double;
    int place(int offset, LirValue? index) =>
        offset + (index == null ? 0 : integer(index));
    switch (instruction) {
      case ConstInt(:final value):
        return value;
      case ConstFloat(:final value):
        return value;
      case ConstNull():
        return null;
      case SymbolAddress(:final symbol):
        return _addresses[symbol] ??
            (throw LirFault('$symbol has no address here.'));
      case StaticObject(:final symbol):
        return _statics[symbol];
      case FrameAddress():
        throw LirFault('Frames are not simulated.');
      case IntBinary(:final op, :final left, :final right):
        return _integer(op, integer(left), integer(right));
      case FloatBinary(:final op, :final left, :final right):
        return _float(op, float(left), float(right));
      case FloatUnary(:final op, :final operand):
        return switch (op) {
          .neg => -float(operand),
          .sqrt => math.sqrt(float(operand)),
        };
      case Compare(:final relation, :final left, :final right):
        return _compare(relation, values[left], values[right]) ? 1 : 0;
      case Convert(:final op, :final operand):
        return _convert(op, values[operand]);
      case PtrAdd(:final base, :final offset):
        return integer(base) + integer(offset);
      case Load(:final width, :final base, :final offset, :final index):
        return memory.load(width, values[base], place(offset, index));
      case Store(
        :final width,
        :final base,
        :final offset,
        :final index,
        :final value,
      ):
        final at = place(offset, index);
        memory.store(width, values[base], at, values[value]);
        return null;
      case Call(:final symbol, :final arguments):
        return call(symbol, [for (final value in arguments) values[value]]);
      case CallIndirect(:final address, :final signature, :final arguments):
        final symbol = _callables[integer(address)];
        if (symbol == null) throw LirFault('Call to a non-function address.');
        if (module.signatures[symbol] != signature) {
          throw LirFault('Indirect call to $symbol as $signature.');
        }
        return call(symbol, [for (final value in arguments) values[value]]);
      case Alloc(:final size):
        final bytes = integer(size);
        if (bytes < 0) throw LirFault('Allocation of $bytes bytes.');
        return LirObject(bytes);
    }
  }

  int _integer(IntOp op, int left, int right) {
    if ((op == .div || op == .rem) && right == 0) {
      throw LirFault('Division by zero.');
    }
    if ((op == .shl || op == .sar || op == .shr) && (right < 0 || right > 63)) {
      throw LirFault('Shift by $right.');
    }
    return switch (op) {
      .add => left + right,
      .sub => left - right,
      .mul => left * right,
      .div => left ~/ right,
      .rem => left.remainder(right),
      .and => left & right,
      .or => left | right,
      .xor => left ^ right,
      .shl => left << right,
      .sar => left >> right,
      .shr => left >>> right,
    };
  }

  double _float(FloatOp op, double left, double right) => switch (op) {
    .add => left + right,
    .sub => left - right,
    .mul => left * right,
    .div => left / right,
  };

  bool _compare(Relation relation, Object? left, Object? right) {
    if (left is! num || right is! num) {
      final same = identical(left, right);
      return relation == .eq ? same : !same;
    }
    const sign = 1 << 63;
    if (relation.isUnsigned) {
      left = (left as int) ^ sign;
      right = (right as int) ^ sign;
    }
    return switch (relation) {
      .eq => left == right,
      .ne => left != right,
      .lt || .ult => left < right,
      .le || .ule => left <= right,
      .gt || .ugt => left > right,
      .ge || .uge => left >= right,
    };
  }

  Object _convert(Conversion op, Object? value) {
    final bits = ByteData(8);
    switch (op) {
      case .intToFloat:
        return (value as int).toDouble();
      case .floatToInt:
        final source = value as double;
        if (!(source >= -9223372036854775808.0 &&
            source < 9223372036854775808.0)) {
          throw LirFault('$source does not fit an integer.');
        }
        return source.toInt();
      case .intBitsToFloat:
        bits.setInt64(0, value as int);
        return bits.getFloat64(0);
      case .floatBitsToInt:
        bits.setFloat64(0, value as double);
        return bits.getInt64(0);
      case .intToRef:
        throw LirFault('Objects are not integers here.');
      case .intToPtr || .ptrToInt:
        return value as int;
    }
  }
}
