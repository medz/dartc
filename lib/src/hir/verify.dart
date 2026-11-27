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
  for (final class_ in module.classes) {
    final superclass = class_.superclass;
    if (superclass?.elements != null) {
      throw HirError('class ${class_.name} extends an array');
    }
    if (class_.elements != null && class_.fields.length > 1) {
      throw HirError('array ${class_.name} has several fields');
    }
  }
  final constants = _ConstantVerifier(classes);
  final globals = module.globals.toSet();
  if (globals.length != module.globals.length) {
    throw HirError('a global is listed twice');
  }
  for (final HirGlobal(:name, :type, :initial) in module.globals) {
    if (!isConstant(type, initial)) {
      throw HirError('global $name starts with $initial');
    }
    constants.check(initial);
  }
  _checkRuntime(module, functions);
  module.tests.forEach((test, passing) {
    for (final class_ in passing) {
      if (classes.contains(class_)) continue;
      throw HirError('test ${test.name}: unlisted class ${class_.name}');
    }
  });
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
    _FunctionVerifier(
      module,
      functions,
      classes,
      constants,
      globals,
      function,
    ).run();
  }
}

void _checkRuntime(HirModule module, Set<HirFunction> functions) {
  void check(
    String name,
    HirFunction? function,
    List<HirType> parameters, [
    HirType? result,
  ]) {
    if (function == null) return;
    if (!functions.contains(function)) throw HirError('$name is not listed');
    if (function.parameters.length != parameters.length ||
        function.parameters.indexed.any((e) => e.$2 != parameters[e.$1]) ||
        function.result != result) {
      throw HirError('$name has another signature');
    }
  }

  check('allocate', module.allocate, [.integer], .integer);
  check('raise', module.raise, [.reference, .reference]);
  check('stackOverflow', module.stackOverflow, []);
  check('outOfMemory', module.outOfMemory, []);
  final callback = module.callback;
  check('callback', callback, [.integer, .integer, .integer], callback?.result);
  final spawned = module.spawned;
  check('spawned', spawned, [.integer], spawned?.result);
  module.exports.forEach((name, function) {
    check('export $name', function, [.integer, .integer], function.result);
  });
  final loop = module.eventLoop;
  check('eventLoop', loop, const [], loop?.result);
  // What it gives, if anything, is not used.
  final uncaught = module.uncaught;
  check('uncaught', uncaught, [.reference, .reference], uncaught?.result);
}

/// Checks constants and those they refer to, which form no cycle.
final class _ConstantVerifier(final Set<HirClass> _classes) {
  final _checked = Set<HirConstObject>.identity();

  void check(Object? value) {
    if (value is! HirConstObject || !_checked.add(value)) return;
    final HirConstObject(:target, :fields) = value;
    if (!_classes.contains(target)) {
      throw HirError('unlisted class ${target.name}');
    }
    final expected = target.fields;
    if (fields.length != expected.length ||
        !expected.every(
          (field) =>
              fields.containsKey(field) &&
              isConstant(field.type, fields[field]),
        )) {
      throw HirError('constant ${target.name} has wrong fields');
    }
    final isRight = switch (target.elements) {
      null => value.elements == null,
      .references => value.elements?.every((e) => isConstant(.reference, e)),
      .bytes => value.elements?.every((e) => e is int && e >= 0 && e < 256),
    };
    if (isRight != true) {
      throw HirError('constant ${target.name} has wrong elements');
    }
    for (final part in [...fields.values, ...?value.elements]) {
      check(part);
    }
  }
}

final class _FunctionVerifier(
  final HirModule module,
  final Set<HirFunction> functions,
  final Set<HirClass> classes,
  final _ConstantVerifier constants,
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
    for (final block in function.blocks) {
      if (block.terminator case HirInvoke(:final call)) {
        if (_blockOf.containsKey(call)) _fail('a value is defined twice');
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
      if (end is HirInvoke && identical(end.onReturn, end.onThrow)) {
        _fail('invoke shares one edge for both outcomes');
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
      case HirConst() || HirNull() || HirClassNumber() || HirNativeFunction():
        break;
      case HirNewArray(:final target, :final length):
        _checkClass(target);
        if (target.elements == null) _fail('${target.name} has no elements');
        _expect(length, .integer, 'length');
      case HirLength(:final array):
        _expect(array, .reference, 'array');
      case HirLoadElement(:final array, :final index):
        _expect(array, .reference, 'array');
        _expect(index, .integer, 'index');
      case HirStoreElement(
        :final element,
        :final array,
        :final index,
        :final value,
      ):
        _expect(array, .reference, 'array');
        _expect(index, .integer, 'index');
        _expect(value, element.type, 'element');
      case HirStatic(:final object):
        constants.check(object);
      case HirLoadGlobal(:final global):
        _checkGlobal(global);
      case HirStoreGlobal(:final global, :final value):
        _checkGlobal(global);
        _expect(value, global.type, 'global ${global.name}');
      case HirMachine(:final op, :final arguments):
        _checkTypes(op.parameters, arguments, op.name);
      case HirIsInstance(:final test, :final object):
        _checkTest(test);
        _expect(object, .reference, 'is ${test.name}');
      case HirHasClass(:final target, :final object):
        _checkClass(target);
        _expect(object, .reference, 'is exactly ${target.name}');
      case HirNew(:final target):
        _checkClass(target);
        if (target.elements != null) _fail('${target.name} has elements');
      case HirBox(:final target, :final value):
        _checkClass(target);
        if (target.fields.length != 1 || target.elements != null) {
          _fail('${target.name} is no box');
        }
        _expect(value, target.fields.single.type, target.name);
      case HirLoad(:final object) || HirUnbox(:final object):
        _expect(object, .reference, 'object');
      case HirStore(:final field, :final object, :final value):
        _expect(object, .reference, 'object');
        _expect(value, field.type, 'field ${field.name}');
      case HirVirtualCall(
        :final selector,
        :final receiver,
        :final arguments,
        :final bound,
      ):
        if (bound != null) _checkTest(bound);
        if (!module.dispatch.containsKey(selector)) {
          _fail('unlisted selector ${selector.name}');
        }
        _expect(receiver, .reference, 'receiver');
        _checkTypes(selector.parameters, arguments, 'call to ${selector.name}');
      case HirIntBinary() ||
          HirFloatBinary() ||
          HirBoolBinary() ||
          HirUnary() ||
          HirCompare():
        _checkOperator(instruction);
      case HirCall(:final target, :final arguments):
        if (!functions.contains(target)) {
          _fail('unlisted callee ${target.name}');
        }
        _checkTypes(target.parameters, arguments, 'call to ${target.name}');
    }
  }

  void _checkOperator(HirInstruction instruction) {
    switch (instruction) {
      case HirIntBinary(:final operator, :final left, :final right):
        _expect(left, .integer, operator.symbol);
        _expect(right, .integer, operator.symbol);
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
      default:
        break;
    }
  }

  void _checkClass(HirClass target) {
    if (!classes.contains(target)) _fail('unlisted class ${target.name}');
  }

  void _checkTest(HirTypeTest test) {
    if (!module.tests.containsKey(test)) _fail('unlisted test ${test.name}');
  }

  void _checkGlobal(HirGlobal global) {
    if (!globals.contains(global)) _fail('unlisted global ${global.name}');
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
      case HirThrow(:final exception, :final trace):
        _expect(exception, .reference, 'exception');
        _expect(trace, .reference, 'stack trace');
      case HirInvoke(:final call):
        _checkInstruction(call);
      case HirJump() || HirUnreachable():
        break;
    }
    for (final edge in end.edges) {
      _checkUses(edge.arguments, block, position);
      final implicit = end.implicit(edge);
      final target = [for (final p in edge.target.parameters) p.type];
      if (target.length < implicit.length ||
          implicit.indexed.any((e) => target[e.$1] != e.$2)) {
        _fail('edge target does not accept the call outcome');
      }
      _checkTypes(
        target.sublist(implicit.length),
        edge.arguments,
        'edge arguments',
      );
    }
  }
}
