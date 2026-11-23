import 'package:dartc/graph.dart';

import 'block.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';

/// A malformed program: always a compiler bug, never a user error.
final class HirError(final String message) implements Exception {
  @override
  String toString() => 'HirError: $message';
}

/// Throws [HirError] unless [module] satisfies every HIR rule.
void verifyHir(HirModule module) {
  final functions = module.functions.toSet();
  if (functions.length != module.functions.length) {
    throw HirError('a function is listed twice');
  }
  if (!functions.contains(module.main)) throw HirError('main is not listed');
  if (module.main.parameters.isNotEmpty) throw HirError('main has parameters');
  for (final function in module.functions) {
    _FunctionVerifier(functions, function).run();
  }
}

final class _FunctionVerifier(
  final Set<HirFunction> functions,
  final HirFunction function,
) {
  final _blockOf = <HirValue, HirBlock>{};
  final _positionOf = <HirValue, int>{};
  late final _dominators = Dominators(
    function.entry,
    (block) => block.terminator!.edges.map((edge) => edge.target),
  );

  Never _fail(String message) => throw HirError('${function.name}: $message');

  void run() {
    _checkShape();
    for (final block in function.blocks) {
      for (final parameter in block.parameters) {
        _define(parameter, block, -1);
      }
      for (final (i, instruction) in block.instructions.indexed) {
        _define(instruction, block, i);
      }
    }
    if (_dominators.order.length != function.blocks.length) {
      _fail('unreachable block');
    }
    for (final block in function.blocks) {
      for (final (i, instruction) in block.instructions.indexed) {
        _checkUses(instruction.inputs, block, i);
        _checkInstruction(instruction);
      }
      _checkTerminator(block);
    }
  }

  void _checkShape() {
    if (function.blocks.isEmpty) _fail('no blocks');
    final owned = function.blocks.toSet();
    if (owned.length != function.blocks.length) {
      _fail('a block is listed twice');
    }
    _checkTypes(
      function.parameters,
      function.entry.parameters,
      'entry parameters',
    );
    for (final block in function.blocks) {
      final end = block.terminator ?? _fail('a block has no terminator');
      for (final edge in end.edges) {
        if (!owned.contains(edge.target)) _fail('edge leaves the function');
        if (edge.target == function.entry) _fail('edge enters the entry block');
      }
    }
  }

  void _define(HirValue value, HirBlock block, int position) {
    if (_blockOf.containsKey(value)) _fail('a value is defined twice');
    _blockOf[value] = block;
    _positionOf[value] = position;
  }

  void _checkUses(Iterable<HirValue> uses, HirBlock block, int position) {
    for (final value in uses) {
      final owner = _blockOf[value] ?? _fail('use of an undefined value');
      if (value.type == null) _fail('use of an operation without a result');
      if (owner == block
          ? _positionOf[value]! >= position
          : !_dominators.dominates(owner, block)) {
        _fail('a definition does not dominate its use');
      }
    }
  }

  void _expect(HirValue value, HirType type, String what) {
    if (value.type != type) {
      _fail('$what: expected ${type.dartName}, found ${value.type?.dartName}');
    }
  }

  void _checkTypes(List<HirType> expected, List<HirValue> actual, String what) {
    if (expected.length != actual.length) {
      _fail('$what: ${actual.length} for ${expected.length}');
    }
    for (final (i, type) in expected.indexed) {
      _expect(actual[i], type, what);
    }
  }

  void _checkInstruction(HirInstruction instruction) {
    switch (instruction) {
      case HirConst() || HirPrint():
        break;
      case HirIntBinary(:final operator, :final left, :final right):
        _expect(left, .integer, operator.symbol);
        _expect(right, .integer, operator.symbol);
        if (!_allows(operator, right)) _fail('${operator.symbol} could throw');
      case HirFloatBinary(:final operator, :final left, :final right):
        _expect(left, .float, operator.symbol);
        _expect(right, .float, operator.symbol);
      case HirBoolBinary(:final operator, :final left, :final right):
        _expect(left, .boolean, operator.symbol);
        _expect(right, .boolean, operator.symbol);
      case HirUnary(:final operator, :final operand):
        _expect(operand, operator.operand, operator.name);
      case HirCompare(:final relation, :final left, :final right):
        _expect(right, left.type!, relation.symbol);
        if (left.type == .boolean && !relation.isEquality) {
          _fail('bool has no ${relation.symbol}');
        }
      case HirCall(:final target, :final arguments):
        if (!functions.contains(target)) {
          _fail('unlisted callee ${target.name}');
        }
        _checkTypes(target.parameters, arguments, 'call to ${target.name}');
    }
  }

  static bool _allows(HirIntOperator operator, HirValue right) {
    if (!operator.isDivision && !operator.isShift) return true;
    if (right is! HirConst) return false;
    final value = right.value as int;
    return operator.isDivision ? value != 0 : value >= 0;
  }

  void _checkTerminator(HirBlock block) {
    final end = block.terminator!, position = block.instructions.length;
    _checkUses(end.inputs, block, position);
    switch (end) {
      case HirBranch(:final condition):
        _expect(condition, .boolean, 'branch condition');
      case HirReturn(:final value):
        if (value?.type != function.result) {
          _fail('returns ${value?.type?.dartName}');
        }
      case HirExit(:final code):
        _expect(code, .integer, 'exit code');
      case HirJump() || HirUnreachable():
        break;
    }
    for (final edge in end.edges) {
      _checkUses(edge.arguments, block, position);
      _checkTypes(
        [for (final parameter in edge.target.parameters) parameter.type],
        edge.arguments,
        'edge arguments',
      );
    }
  }
}
