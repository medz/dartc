import 'block.dart';
import 'class.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';
import 'verify.dart';

/// Executes a program by the rules of Dart.
///
/// A program exceeding [maxSteps] is stopped with a [StateError].
final class HirInterpreter(
  final HirModule module, {
  final int maxSteps = 10000000,
}) {
  int _steps = 0;
  final _output = StringBuffer();

  /// Everything printed so far.
  String get output => '$_output';

  this {
    verifyHir(module);
  }

  /// The argument of the `exit` ending the program, or null if it returned.
  int? run() {
    try {
      _call(module.main, const []);
      return null;
    } on _Exit catch (exit) {
      return exit.code;
    }
  }

  void _step() {
    if (++_steps > maxSteps) throw StateError('Step limit reached.');
  }

  Object? _call(HirFunction function, List<Object> arguments) {
    final values = <HirValue, Object>{};
    void bind(HirBlock block, List<Object> arguments) {
      for (final (i, parameter) in block.parameters.indexed) {
        values[parameter] = arguments[i];
      }
    }

    var block = function.entry;
    bind(block, arguments);
    while (true) {
      for (final instruction in block.instructions) {
        _step();
        final result = _evaluate(instruction, [
          for (final input in instruction.inputs) values[input]!,
        ]);
        if (result != null) values[instruction] = result;
      }
      _step();
      final HirEdge edge;
      switch (block.terminator!) {
        case HirReturn(:final value):
          return value == null ? null : values[value];
        case HirExit(:final code):
          throw _Exit(values[code] as int);
        case HirUnreachable():
          throw StateError('Unreachable code in ${function.name}.');
        case HirJump(edge: final next):
          edge = next;
        case HirBranch(:final condition, :final ifTrue, :final ifFalse):
          edge = values[condition] as bool ? ifTrue : ifFalse;
      }
      final arguments = [for (final value in edge.arguments) values[value]!];
      block = edge.target;
      bind(block, arguments);
    }
  }

  Object? _evaluate(HirInstruction instruction, List<Object> inputs) {
    switch (instruction) {
      case HirConst(:final value):
        return value;
      case HirIntBinary(:final operator):
        return _int(operator, inputs[0] as int, inputs[1] as int);
      case HirFloatBinary(:final operator):
        return _float(operator, inputs[0] as double, inputs[1] as double);
      case HirBoolBinary(:final operator):
        final left = inputs[0] as bool, right = inputs[1] as bool;
        return switch (operator) {
          .and => left & right,
          .or => left | right,
          .xor => left ^ right,
        };
      case HirUnary(:final operator):
        final operand = inputs.single;
        return switch (operator) {
          .negateInt => -(operand as int),
          .complement => ~(operand as int),
          .negateFloat => -(operand as double),
          .not => !(operand as bool),
          .intToFloat => (operand as int).toDouble(),
        };
      case HirCompare(:final relation):
        return _compare(relation, inputs[0], inputs[1]);
      case HirNull():
        return _null;
      case HirNew(:final target):
        return _Object(target);
      case HirLoad(:final field):
        return _object(inputs[0], field).fields[field] ??
            (throw StateError('${field.name} is not set.'));
      case HirStore(:final field):
        _object(inputs[0], field).fields[field] = inputs[1];
        return null;
      case HirVirtualCall(:final selector):
        return _call(_implementation(selector, inputs[0]), inputs);
      case HirPrint(:final text):
        _output.writeln(text);
        return null;
      case HirCall(:final target):
        return _call(target as HirFunction, inputs);
    }
  }

  /// The object [value], which must have [field].
  _Object _object(Object value, HirField field) {
    if (value is _Object && value.target.fields.contains(field)) return value;
    throw StateError('No field ${field.name} in $value.');
  }

  HirFunction _implementation(HirSelector selector, Object receiver) {
    final function = receiver is _Object
        ? module.dispatch[selector]![receiver.target]
        : null;
    return function ?? (throw StateError('No ${selector.name} in $receiver.'));
  }

  int _int(HirIntOperator operator, int left, int right) => switch (operator) {
    .add => left + right,
    .subtract => left - right,
    .multiply => left * right,
    .divide => left ~/ right,
    .modulo => left % right,
    .and => left & right,
    .or => left | right,
    .xor => left ^ right,
    .shiftLeft => left << right,
    .shiftRight => left >> right,
    .shiftRightUnsigned => left >>> right,
  };

  double _float(HirFloatOperator operator, double left, double right) =>
      switch (operator) {
        .add => left + right,
        .subtract => left - right,
        .multiply => left * right,
        .divide => left / right,
        .modulo => left % right,
      };

  bool _compare(HirRelation relation, Object left, Object right) {
    if (relation == .equal) return left == right;
    if (relation == .notEqual) return left != right;
    final a = left as num, b = right as num;
    return switch (relation) {
      .less => a < b,
      .lessOrEqual => a <= b,
      .greater => a > b,
      _ => a >= b,
    };
  }
}

const _null = _Null();

final class const _Null() {
  @override
  String toString() => 'null';
}

final class _Object(final HirClass target) {
  final fields = <HirField, Object>{};

  this {
    for (final field in target.fields) {
      if (field.type == .reference) fields[field] = _null;
    }
  }

  @override
  String toString() => target.name;
}

final class _Exit(final int code) implements Exception;
