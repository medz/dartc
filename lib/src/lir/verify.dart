import 'package:dartc/graph.dart';

import 'block.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';

/// A malformed module: always a compiler bug, never a user error.
final class LirError(final String message) implements Exception {
  @override
  String toString() => 'LirError: $message';
}

/// Throws [LirError] unless [module] satisfies every LIR rule.
void verifyModule(LirModule module) {
  final names = <String>{};
  for (final name in [
    ...module.functions.map((function) => function.name),
    ...module.externals.map((external) => external.name),
    ...module.data.map((data) => data.name),
  ]) {
    if (!names.add(name)) throw LirError('Duplicate symbol: $name');
  }
  for (final function in module.functions) {
    _FunctionVerifier(module, names, function).run();
  }
}

final class _FunctionVerifier(
  final LirModule module,
  final Set<String> symbols,
  final LirFunction function,
) {
  final _blockOf = <LirValue, LirBlock>{};
  final _positionOf = <LirValue, int>{};
  late final _dominators = Dominators(
    function.entry,
    (block) => block.terminator!.edges.map((edge) => edge.target),
  );

  Never _fail(String message) => throw LirError('${function.name}: $message');

  void run() {
    _checkShape();
    _define();
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
    if (function.blocks.toSet().length != function.blocks.length) {
      _fail('a block is listed twice');
    }
    final actual = function.entry.parameters.map((p) => p.type);
    if (LirSignature(actual, function.signature.result) != function.signature) {
      _fail('entry parameters differ from the signature');
    }
    final owned = function.blocks.toSet();
    for (final block in function.blocks) {
      final end = block.terminator ?? _fail('a block has no terminator');
      for (final edge in end.edges) {
        if (!owned.contains(edge.target)) _fail('edge leaves the function');
        if (edge.target == function.entry) _fail('edge enters the entry block');
      }
      if (end is Invoke && identical(end.onReturn, end.onThrow)) {
        _fail('invoke shares one edge for both outcomes');
      }
    }
  }

  void _define() {
    void define(LirValue value, LirBlock block, int position) {
      if (_blockOf.containsKey(value)) _fail('a value is defined twice');
      _blockOf[value] = block;
      _positionOf[value] = position;
    }

    for (final block in function.blocks) {
      for (final parameter in block.parameters) {
        define(parameter, block, -1);
      }
      for (final (i, instruction) in block.instructions.indexed) {
        define(instruction, block, i);
      }
    }
    final invoked = <LirValue>{};
    for (final block in function.blocks) {
      if (block.terminator case Invoke(:final call)) {
        if (_blockOf.containsKey(call) || !invoked.add(call)) {
          _fail('a call is executed at two places');
        }
      }
    }
  }

  void _checkUses(Iterable<LirValue> uses, LirBlock block, int position) {
    for (final value in uses) {
      final owner = _blockOf[value] ?? _fail('use of an undefined value');
      if (value.type == null) _fail('use of an instruction without a result');
      if (owner == block
          ? _positionOf[value]! >= position
          : !_dominators.dominates(owner, block)) {
        _fail('a definition does not dominate its use');
      }
    }
  }

  void _expect(LirValue value, LirType type, String what) {
    if (value.type != type) {
      _fail('$what: expected ${type.name}, found ${value.type?.name}');
    }
  }

  void _checkInstruction(LirInstruction instruction) {
    switch (instruction) {
      case ConstInt() || ConstFloat() || ConstNull():
        break;
      case SymbolAddress(:final symbol):
        if (!symbols.contains(symbol)) _fail('unknown symbol $symbol');
      case IntBinary(:final left, :final right):
        _expect(left, .i64, 'integer operand');
        _expect(right, .i64, 'integer operand');
      case FloatBinary(:final left, :final right):
        _expect(left, .f64, 'float operand');
        _expect(right, .f64, 'float operand');
      case FloatUnary(:final operand):
        _expect(operand, .f64, 'float operand');
      case Compare():
        _checkCompare(instruction);
      case Convert(:final op, :final operand):
        _expect(operand, op.from, op.name);
      case PtrAdd(:final base, :final offset):
        _expect(base, .ptr, 'address');
        _expect(offset, .i64, 'address offset');
      case Load(:final width, :final base, :final index):
        _checkAddress(width, base, index);
      case Store(:final width, :final base, :final index, :final value):
        _checkAddress(width, base, index);
        _expect(value, width.type, 'stored value');
      case LirCall():
        _checkCall(instruction);
    }
  }

  void _checkCompare(Compare compare) {
    final type = compare.left.type!;
    _expect(compare.right, type, 'compared value');
    final relation = compare.relation;
    final allowed = switch (type) {
      .i64 => true,
      .f64 => !relation.isUnsigned,
      .ref || .ptr => relation.isEquality,
    };
    if (!allowed) _fail('${type.name} has no ${relation.name} comparison');
  }

  void _checkAddress(Width width, LirValue base, LirValue? index) {
    if (base.type != .ref && base.type != .ptr) {
      _fail('memory base is ${base.type?.name}');
    }
    if (width == .ref && base.type != .ref) {
      _fail('a reference is stored outside a managed object');
    }
    if (index != null) _expect(index, .i64, 'memory index');
  }

  void _checkCall(LirCall call) {
    switch (call) {
      case Call(:final symbol, :final signature, :final arguments):
        final declared = module.signatures[symbol];
        if (declared == null) _fail('unknown callee $symbol');
        if (declared != signature) _fail('$symbol has signature $declared');
        _checkArguments(signature.parameters, arguments, 'call to $symbol');
      case CallIndirect(:final address, :final signature, :final arguments):
        _expect(address, .ptr, 'callee address');
        _checkArguments(signature.parameters, arguments, 'indirect call');
      case Alloc(:final size):
        _expect(size, .i64, 'allocation size');
    }
  }

  void _checkArguments(
    List<LirType> expected,
    List<LirValue> actual,
    String what,
  ) {
    if (expected.length != actual.length) {
      _fail('$what: ${actual.length} arguments for ${expected.length}');
    }
    for (final (i, type) in expected.indexed) {
      _expect(actual[i], type, what);
    }
  }

  void _checkTerminator(LirBlock block) {
    final end = block.terminator!;
    final position = block.instructions.length;
    _checkUses(end.inputs, block, position);
    switch (end) {
      case Branch(:final condition):
        _expect(condition, .i64, 'branch condition');
      case Return(:final value):
        if (value?.type != function.signature.result) {
          _fail('returns ${value?.type?.name}');
        }
      case Throw(:final exception, :final trace):
        _expect(exception, .ref, 'exception');
        _expect(trace, .ref, 'stack trace');
      case Invoke(:final call):
        _checkUses(call.inputs, block, position);
        _checkCall(call);
      case Jump() || Unreachable():
        break;
    }
    for (final edge in end.edges) {
      _checkUses(edge.arguments, block, position);
      final implicit = end.implicit(edge);
      final target = edge.target.parameters.map((p) => p.type).toList();
      if (target.length < implicit.length ||
          implicit.indexed.any((e) => target[e.$1] != e.$2)) {
        _fail('edge target does not accept the call outcome');
      }
      _checkArguments(
        target.sublist(implicit.length),
        edge.arguments,
        'edge arguments',
      );
    }
  }
}
