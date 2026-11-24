import 'block.dart';
import 'instruction.dart';
import 'value.dart';

/// Another instruction like [given], with operands that [of] gives for its own.
HirInstruction copyInstruction(
  HirInstruction given,
  HirValue Function(HirValue value) of,
) => switch (given) {
  HirCalling() => _copyCalling(given, of),
  HirConst(:final value) => HirConst(value),
  HirNull() => HirNull(),
  HirClassNumber(:final target) => HirClassNumber(target),
  HirNativeFunction(:final name) => HirNativeFunction(name),
  HirStatic(:final object) => HirStatic(object),
  HirLoadGlobal(:final global) => HirLoadGlobal(global),
  HirStoreGlobal(:final global, :final value) => HirStoreGlobal(
    global,
    of(value),
  ),
  HirLength(:final array) => HirLength(of(array)),
  HirLoadElement(:final element, :final array, :final index) => HirLoadElement(
    element,
    of(array),
    of(index),
  ),
  HirStoreElement(:final element, :final array, :final index, :final value) =>
    HirStoreElement(element, of(array), of(index), of(value)),
  HirMachine(:final op, :final arguments) => HirMachine(op, arguments.map(of)),
  HirLoad(:final field, :final object) => HirLoad(field, of(object)),
  HirUnbox(:final field, :final object) => HirUnbox(field, of(object)),
  HirStore(:final field, :final object, :final value) => HirStore(
    field,
    of(object),
    of(value),
  ),
  HirIntBinary(:final operator, :final left, :final right) => HirIntBinary(
    operator,
    of(left),
    of(right),
  ),
  HirFloatBinary(:final operator, :final left, :final right) => HirFloatBinary(
    operator,
    of(left),
    of(right),
  ),
  HirBoolBinary(:final operator, :final left, :final right) => HirBoolBinary(
    operator,
    of(left),
    of(right),
  ),
  HirUnary(:final operator, :final operand) => HirUnary(operator, of(operand)),
  HirCompare(:final relation, :final left, :final right) => HirCompare(
    relation,
    of(left),
    of(right),
  ),
  HirIsInstance(:final test, :final object) => HirIsInstance(test, of(object)),
  HirHasClass(:final target, :final object, :final mayBeInteger) => HirHasClass(
    target,
    of(object),
    mayBeInteger: mayBeInteger,
  ),
};

HirCalling _copyCalling(
  HirCalling given,
  HirValue Function(HirValue value) of,
) => switch (given) {
  HirNew(:final target) => HirNew(target),
  HirBox(:final target, :final value) => HirBox(target, of(value)),
  HirNewArray(:final target, :final length) => HirNewArray(target, of(length)),
  HirVirtualCall(
    :final selector,
    :final receiver,
    :final arguments,
    :final bound,
  ) =>
    HirVirtualCall(selector, of(receiver), arguments.map(of), bound: bound),
  HirCall(:final target, :final arguments) => HirCall(
    target,
    arguments.map(of),
  ),
};

/// Another terminator like [given], with operands that [of] gives for its own,
/// and edges to the blocks that [to] gives.
HirTerminator copyTerminator(
  HirTerminator given,
  HirValue Function(HirValue value) of,
  HirBlock Function(HirBlock block) to,
) {
  HirEdge edge(HirEdge edge) =>
      HirEdge(to(edge.target), edge.arguments.map(of));
  return switch (given) {
    HirJump(edge: final target) => HirJump(edge(target)),
    HirBranch(:final condition, :final ifTrue, :final ifFalse) => HirBranch(
      of(condition),
      edge(ifTrue),
      edge(ifFalse),
    ),
    HirReturn(:final value) => HirReturn(value == null ? null : of(value)),
    HirThrow(:final exception, :final trace) => HirThrow(
      of(exception),
      of(trace),
    ),
    HirInvoke(:final call, :final onReturn, :final onThrow) => HirInvoke(
      _copyCalling(call, of),
      edge(onReturn),
      edge(onThrow),
    ),
    HirExit(:final code) => HirExit(of(code)),
    HirUnreachable() => HirUnreachable(),
  };
}
