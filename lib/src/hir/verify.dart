import 'package:dartc/graph.dart';

import 'block.dart';
import 'class.dart';
import 'global.dart';
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
  final classes = module.classes.toSet();
  if (classes.length != module.classes.length) {
    throw HirError('a class is listed twice');
  }
  final globals = module.globals.toSet();
  if (globals.length != module.globals.length) {
    throw HirError('a global is listed twice');
  }
  for (final HirGlobal(:name, :type, :initial) in module.globals) {
    if (!isConstant(type, initial)) {
      throw HirError('global $name starts with $initial');
    }
    _checkConstant(classes, initial);
  }
  if (module.allocate case final allocate?) {
    if (!functions.contains(allocate)) throw HirError('allocate is not listed');
    if (allocate.parameters.length != 1 ||
        allocate.parameters.single != .integer ||
        allocate.result != .integer) {
      throw HirError('allocate has another signature');
    }
  }
  module.dispatch.forEach((selector, entries) {
    entries.forEach((class_, function) {
      Never fail(String message) =>
          throw HirError('${selector.name}: $message');
      if (!classes.contains(class_)) fail('unlisted class ${class_.name}');
      if (!functions.contains(function)) {
        fail('unlisted function ${function.name}');
      }
      final [receiver, ...parameters] = function.parameters;
      if (receiver != .reference ||
          parameters.length != selector.parameters.length ||
          parameters.indexed.any((e) => e.$2 != selector.parameters[e.$1]) ||
          function.result != selector.result) {
        fail('${function.name} has another signature');
      }
    });
  });
  for (final function in module.functions) {
    _FunctionVerifier(module, functions, classes, globals, function).run();
  }
}

/// Checks a constant and those it refers to, which form no cycle.
void _checkConstant(Set<HirClass> classes, Object? value) {
  if (value is! HirConstObject) return;
  final HirConstObject(:target, :fields) = value;
  if (!classes.contains(target)) {
    throw HirError('unlisted class ${target.name}');
  }
  final expected = target.fields;
  if (fields.length != expected.length ||
      !expected.every(
        (field) =>
            fields.containsKey(field) && isConstant(field.type, fields[field]),
      )) {
    throw HirError('constant ${target.name} has wrong fields');
  }
  for (final field in fields.values) {
    _checkConstant(classes, field);
  }
}

final class _FunctionVerifier(
  final HirModule module,
  final Set<HirFunction> functions,
  final Set<HirClass> classes,
  final Set<HirGlobal> globals,
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
      case HirConst() || HirNull() || HirPrint():
        break;
      case HirStatic(:final object):
        _checkConstant(classes, object);
      case HirLoadGlobal(:final global):
        _checkGlobal(global);
      case HirStoreGlobal(:final global, :final value):
        _checkGlobal(global);
        _expect(value, global.type, 'global ${global.name}');
      case HirMachine(:final op, :final arguments):
        _checkTypes(List.filled(op.parameters, .integer), arguments, op.name);
      case HirNew(:final target):
        if (!classes.contains(target)) _fail('unlisted class ${target.name}');
      case HirLoad(:final object):
        _expect(object, .reference, 'object');
      case HirStore(:final field, :final object, :final value):
        _expect(object, .reference, 'object');
        _expect(value, field.type, 'field ${field.name}');
      case HirVirtualCall(:final selector, :final receiver, :final arguments):
        if (!module.dispatch.containsKey(selector)) {
          _fail('unlisted selector ${selector.name}');
        }
        _expect(receiver, .reference, 'receiver');
        _checkTypes(selector.parameters, arguments, 'call to ${selector.name}');
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
        final ordered = left.type == .integer || left.type == .float;
        if (!ordered && !relation.isEquality) {
          _fail('${left.type!.dartName} has no ${relation.symbol}');
        }
      case HirCall(:final target, :final arguments):
        if (!functions.contains(target)) {
          _fail('unlisted callee ${target.name}');
        }
        _checkTypes(target.parameters, arguments, 'call to ${target.name}');
    }
  }

  void _checkGlobal(HirGlobal global) {
    if (!globals.contains(global)) _fail('unlisted global ${global.name}');
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
