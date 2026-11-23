import 'block.dart';
import 'class.dart';
import 'global.dart';
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

  /// How many calls may be running before the stack overflows.
  final int maxDepth = 500,
}) {
  int _steps = 0, _depth = 0;
  final _output = StringBuffer(), _errors = StringBuffer();
  final _constants = <HirConstObject, _Object>{};
  late final _globals = {
    for (final global in module.globals) global: _constant(global.initial),
  };

  /// Everything printed so far.
  String get output => '$_output';

  /// Everything written to standard error so far.
  String get errors => '$_errors';

  this {
    verifyHir(module);
  }

  /// The code of an exit that ended the program, or null if it returned.
  int? run() {
    try {
      _call(module.main, const []);
      return null;
    } on _Exit catch (exit) {
      return exit.code;
    } on _Thrown catch (thrown) {
      final uncaught = module.uncaught ?? (throw StateError('Uncaught.'));
      _call(uncaught, [thrown.exception]);
      return 255;
    }
  }

  void _step() {
    if (++_steps > maxSteps) throw StateError('Step limit reached.');
  }

  Object? _call(HirFunction function, List<Object> arguments) {
    if (module.stackOverflow case final overflow?
        when function.checksStack && function != overflow) {
      if (_depth >= maxDepth) return _call(overflow, const []);
    }
    _depth++;
    try {
      return _run(function, arguments);
    } finally {
      _depth--;
    }
  }

  Object? _run(HirFunction function, List<Object> arguments) {
    final values = <HirValue, Object>{};
    void bind(HirBlock block, List<Object> arguments) {
      for (final (i, parameter) in block.parameters.indexed) {
        values[parameter] = arguments[i];
      }
    }

    List<Object> inputsOf(HirInstruction instruction) => [
      for (final input in instruction.inputs) values[input]!,
    ];

    var block = function.entry;
    bind(block, arguments);
    while (true) {
      for (final instruction in block.instructions) {
        _step();
        final result = _evaluate(instruction, inputsOf(instruction));
        if (result != null) values[instruction] = result;
      }
      _step();
      final HirEdge edge;
      var implicit = const <Object>[];
      switch (block.terminator!) {
        case HirReturn(:final value):
          return value == null ? null : values[value];
        case HirExit(:final code):
          throw _Exit(values[code] as int);
        case HirThrow(:final exception, :final trace):
          throw _Thrown(values[exception]!, values[trace]!);
        case HirInvoke(:final call, :final onReturn, :final onThrow):
          (edge, implicit) = _invoke(call, inputsOf(call), onReturn, onThrow);
        case HirUnreachable():
          throw StateError('Unreachable code in ${function.name}.');
        case HirJump(edge: final next):
          edge = next;
        case HirBranch(:final condition, :final ifTrue, :final ifFalse):
          edge = values[condition] as bool ? ifTrue : ifFalse;
      }
      final arguments = [
        ...implicit,
        for (final value in edge.arguments) values[value]!,
      ];
      block = edge.target;
      bind(block, arguments);
    }
  }

  (HirEdge, List<Object>) _invoke(
    HirCalling call,
    List<Object> inputs,
    HirEdge onReturn,
    HirEdge onThrow,
  ) {
    try {
      final result = _evaluate(call, inputs);
      return (onReturn, [if (call.type != null) result!]);
    } on _Thrown catch (thrown) {
      return (onThrow, [thrown.exception, thrown.trace]);
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
          .floatToInt =>
            (operand as double).isFinite
                ? operand.toInt()
                : throw StateError('$operand is not finite.'),
        };
      case HirCompare(:final relation):
        return _compare(relation, inputs[0], inputs[1]);
      case HirNull():
        return _null;
      case HirStatic(:final object):
        return _constant(object);
      case HirLoadGlobal(:final global):
        return _globals[global];
      case HirStoreGlobal(:final global):
        _globals[global] = inputs.single;
        return null;
      case HirMachine(op: .isSame):
        return identical(inputs[0], inputs[1]);
      case HirMachine(op: .writeError):
        _errors.writeCharCode(inputs.single as int);
        return null;
      case HirWriteError(:final text):
        _errors.write(text);
        return null;
      case HirIsInstance(:final test):
        final object = inputs.single;
        if (object is! _Object) throw StateError('$object has no class.');
        return module.tests[test]!.contains(object.target);
      case HirMachine(:final op):
        throw StateError('${op.name} is not simulated.');
      case HirNew(:final target):
        return _Object(target);
      case HirLoad(:final field):
        return _object(inputs[0], field).fields[field] ??
            (throw StateError('${field.name} is not set.'));
      case HirStore(:final field):
        final object = _object(inputs[0], field);
        if (object.isConstant) throw StateError('$object is constant.');
        object.fields[field] = inputs[1];
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

  Object _constant(Object? value) {
    if (value == null) return _null;
    if (value is! HirConstObject) return value;
    return _constants.putIfAbsent(value, () {
      final object = _Object(value.target, isConstant: true);
      value.fields.forEach((field, content) {
        object.fields[field] = _constant(content);
      });
      return object;
    });
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

  int _int(HirIntOperator operator, int left, int right) {
    if (operator.isDivision && right == 0 || operator.isShift && right < 0) {
      throw StateError('$left ${operator.symbol} $right is impossible.');
    }
    return switch (operator) {
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
  }

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

final class _Object(final HirClass target, {final bool isConstant = false}) {
  final fields = <HirField, Object>{};

  this {
    for (final field in target.fields) {
      if (field.type == .reference) fields[field] = _null;
    }
  }

  @override
  String toString() => target.name;
}

final class _Thrown(final Object exception, final Object trace)
    implements Exception;

final class _Exit(final int code) implements Exception;
