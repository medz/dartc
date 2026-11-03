import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The open control-flow graph and local bindings for one function.
final class FunctionContext(
  /// The source unit used for resolved identities and diagnostic locations.
  final ResolvedUnitResult unit,

  /// The call targets shared by all functions in this batch.
  final TargetBindings bindings,
) {
  /// The blocks created so far, with the function entry first.
  final blocks = <Block>[];

  /// The SSA value of each in-scope variable on the current path.
  final locals = <VariableElement, Value>{};

  /// Writable bindings and their declared types, in edge-argument order.
  final mutableLocals = <(VariableElement, ValueType)>[];

  /// The block receiving instructions, or `null` after a terminating transfer.
  Block? current;
  _Refinement? _facts;

  /// The narrower operand established on the current path, if any.
  Value refined(Value value) {
    for (var fact = _facts; fact != null; fact = fact.previous) {
      if (fact.operand == value) return refined(fact.narrowed);
    }
    return value;
  }

  /// Checks [value] once and retains the non-null result on this path.
  Value checkNotNull(Value value) {
    final known = refined(value);
    if (!known.type.accepts(.nullType)) return known;
    final checked = current!.emit(NullCheck(known));
    _facts = _Refinement(value, checked, _facts);
    return checked;
  }

  /// Checks [value] against [type] if its current binding does not establish the type.
  Value cast(Value value, ValueType type) {
    if (type.accepts(value.type)) return value;
    final known = refined(value);
    if (type.accepts(known.type)) return known;
    final cast = current!.emit(TypeCast(known, type));
    if (known.type.accepts(type)) _facts = _Refinement(known, cast, _facts);
    return cast;
  }

  /// Tests the runtime type of [value] after its effects have been evaluated.
  Value testType(Value value, ValueType type, {bool negated = false}) {
    final known = refined(value);
    if (type.accepts(known.type)) return Constant.boolean(!negated);
    if (type == .never ||
        known.type == .nullType ||
        (type == .nullType && !known.type.accepts(.nullType))) {
      return Constant.boolean(negated);
    }
    return current!.emit(TypeTest(known, type, negated: negated));
  }

  /// Opens an arm of [condition] and binds the value established by a type test.
  Jump enterArm(Value condition, bool taken) {
    final proof = condition is TypeTest ? condition.refinement(taken) : null;
    final block = addBlock([if (proof is TestedValue) proof.type]);
    if (condition is TypeTest && proof != null && proof != condition.operand) {
      final known = proof is TestedValue ? block.parameters.single : proof;
      _facts = _Refinement(condition.operand, known, _facts);
    }
    current = block;
    return .new(block, [if (proof is TestedValue) proof]);
  }

  /// Appends an open block with parameters of [types] and returns it.
  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }

  /// Captures the bindings that may differ when another path reaches this point.
  List<Value> saveLocals([int? count]) {
    final end = count ?? mutableLocals.length;
    return end == 0
        ? const []
        : [for (var i = 0; i < end; i++) locals[mutableLocals[i].$1]!];
  }

  /// Restores [values] at the same lexical scope in which they were captured.
  void restoreLocals(List<Value> values) {
    for (final (i, (variable, _)) in mutableLocals.indexed) {
      locals[variable] = values[i];
    }
  }

  /// Returns edges from the [saved] and active paths to a new current block.
  ///
  /// If both paths produce a [result], the first block parameter carries it.
  /// The remaining parameters carry only locals that differ across the paths.
  (Jump, Jump) join(List<Value> saved, [(ValueType, Value, Value)? result]) {
    final types = <ValueType>[if (result != null) result.$1];
    final first = <Value>[if (result != null) result.$2];
    final second = <Value>[if (result != null) result.$3];
    final changed = <VariableElement>[];
    for (final (i, (variable, type)) in mutableLocals.indexed) {
      final value = locals[variable]!;
      if (saved[i] == value) continue;
      types.add(type);
      first.add(saved[i]);
      second.add(value);
      changed.add(variable);
    }
    final block = addBlock(types);
    var slot = result == null ? 0 : 1;
    for (final variable in changed) {
      locals[variable] = block.parameters[slot++];
    }
    current = block;
    return (.new(block, first), .new(block, second));
  }

  /// Lowers alternatives from the same local state and joins paths that return normally.
  Value? branch(
    Value condition,
    Value? Function() ifTrue,
    Value? Function() ifFalse, [
    ValueType? resultType,
  ]) {
    if (condition case Constant(value: final bool taken)) {
      return taken ? ifTrue() : ifFalse();
    }
    final origin = current!, before = saveLocals(), facts = _facts;
    final yes = enterArm(condition, true);
    final left = ifTrue(), yesEnd = current;
    final yesFacts = _facts;
    final yesValues = yesEnd == null ? null : saveLocals();
    _facts = facts;
    restoreLocals(before);
    final no = enterArm(condition, false);
    final right = ifFalse(), noEnd = current;
    origin.finish(Branch(condition, yes, no));
    if (yesEnd == null) return right;
    if (noEnd == null) {
      current = yesEnd;
      _facts = yesFacts;
      restoreLocals(yesValues!);
      return left;
    }
    _facts = facts;
    final (fromYes, fromNo) = join(
      yesValues!,
      resultType == null ? null : (resultType, left!, right!),
    );
    yesEnd.finish(fromYes);
    noEnd.finish(fromNo);
    return resultType == null ? null : current!.parameters.first;
  }

  /// Evaluates [right] only on the selected edge and forwards [skipped] on the other.
  Value shortCircuit(
    Value condition, {
    required bool evaluateWhen,
    required Value skipped,
    required ValueType resultType,
    required Value? Function() right,
  }) {
    final entry = current!, before = saveLocals(), facts = _facts;
    final enter = enterArm(condition, evaluateWhen);
    final result = right();
    _facts = facts;
    final Jump skip;
    if (result == null) {
      restoreLocals(before);
      current = addBlock([resultType]);
      skip = Jump(current!, [skipped]);
    } else {
      final end = current!;
      final edges = join(before, (resultType, skipped, result));
      skip = edges.$1;
      end.finish(edges.$2);
    }
    entry.finish(
      Branch(
        condition,
        evaluateWhen ? enter : skip,
        evaluateWhen ? skip : enter,
      ),
    );
    return skip.target.parameters.first;
  }
}

final class _Refinement(
  final Value operand,
  final Value narrowed,
  final _Refinement? previous,
);

/// A jump destination carrying only the mutable locals visible at its boundary.
final class JumpTarget(final FunctionContext _context) {
  final _localCount = _context.mutableLocals.length;
  final _facts = _context._facts;
  Block? _block;

  /// Creates the destination on its first incoming edge.
  Jump edge() {
    final values = _context.saveLocals(_localCount);
    return .new(
      _block ??= _context.addBlock(
        _context.mutableLocals.take(_localCount).map((v) => v.$2),
      ),
      values,
    );
  }

  /// Transfers the open path, if any, to this target.
  void jump() {
    _context.current?.finish(edge());
    _context.current = null;
  }

  /// Merges incoming jumps with fallthrough in the target's lexical scope.
  void enter() {
    final block = _block;
    if (block == null) return;
    _context.current?.finish(edge());
    _context.current = block;
    _context._facts = _facts;
    _context.restoreLocals(block.parameters);
  }
}
