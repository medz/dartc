import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'dispatch.dart';
import 'machine.dart';
import 'operators.dart';
import 'output.dart';
import 'statics.dart';
import 'system.dart';

LirType _typeOf(HirType type) => switch (type) {
  .integer || .boolean => .i64,
  .float => .f64,
  .reference => .ref,
};

/// The machine-level signature of [function].
LirSignature signatureOf(HirCallable function) => LirSignature(
  function.parameters.map(_typeOf),
  function.result == null ? null : _typeOf(function.result!),
);

LirSignature _selectorSignature(HirSelector selector) => LirSignature([
  .ref,
  ...selector.parameters.map(_typeOf),
], selector.result == null ? null : _typeOf(selector.result!));

/// Lowers one function, block by block.
final class FunctionLowering(
  final HirFunction function,
  final Map<HirCallable, String> symbols,
  final OutputData output,
  final ObjectLayout layout,
  final StaticData statics,
  final MachineLowering machine,
) {
  final _values = <HirValue, LirValue>{};
  final _blocks = <HirBlock, LirBlock>{};
  final _added = <LirBlock>[];

  LirFunction lower() {
    for (final block in function.blocks) {
      final lowered = LirBlock(block.parameters.map((p) => _typeOf(p.type)));
      _blocks[block] = lowered;
      for (final (i, parameter) in block.parameters.indexed) {
        _values[parameter] = lowered.parameters[i];
      }
    }
    // In this order, definitions come before the uses they dominate.
    final order = reversePostorder(
      function.entry,
      (block) => block.terminator!.edges.map((edge) => edge.target),
    );
    for (final block in order) {
      final lowered = _blocks[block]!;
      for (final instruction in block.instructions) {
        final value = _instruction(lowered, instruction);
        if (value != null) _values[instruction] = value;
      }
      lowered.end(_terminator(lowered, block.terminator!));
    }
    final overflow = layout.module.stackOverflow;
    return LirFunction(
      symbols[function]!,
      signatureOf(function),
      [..._blocks.values, ..._added],
      checksStack:
          function.checksStack && overflow != null && function != overflow,
    );
  }

  LirValue _value(HirValue value) => _values[value]!;

  LirValue? _instruction(LirBlock block, HirInstruction instruction) {
    final operators = OperatorLowering(block);
    switch (instruction) {
      case HirConst(:final Object value):
        return block.add(switch (value) {
          int() => ConstInt(value),
          double() => ConstFloat(value),
          _ => ConstInt(value == true ? 1 : 0),
        });
      case HirIntBinary(:final operator, :final left, :final right):
        return operators.integer(operator, _value(left), _value(right));
      case HirFloatBinary(:final operator, :final left, :final right):
        return operators.float(operator, _value(left), _value(right));
      case HirBoolBinary(:final operator, :final left, :final right):
        return operators.boolean(operator, _value(left), _value(right));
      case HirUnary(:final operator, :final operand):
        return operators.unary(operator, _value(operand));
      case HirCompare(:final relation, :final left, :final right):
        return operators.compare(relation, _value(left), _value(right));
      case HirNull():
        return block.add(ConstNull());
      case HirNew(:final target):
        return layout.setClass(
          block,
          block.add(layout.allocation(block, target)),
          target,
        );
      case HirStatic(:final object):
        return block.add(StaticObject(statics.constant(object)));
      case HirLoadGlobal(:final global):
        return block.add(
          Load(
            ObjectLayout.widthOf(global.type),
            block.add(StaticObject(globalsSymbol)),
            offset: statics.offsetOf(global),
          ),
        );
      case HirStoreGlobal(:final global, :final value):
        block.add(
          Store(
            ObjectLayout.widthOf(global.type),
            block.add(StaticObject(globalsSymbol)),
            _value(value),
            offset: statics.offsetOf(global),
          ),
        );
        return null;
      case HirMachine(:final op, :final arguments):
        return machine.lower(block, op, arguments.map(_value).toList());
      case HirLoad(:final field, :final object):
        return layout.load(block, field, _value(object));
      case HirStore(:final field, :final object, :final value):
        layout.store(block, field, _value(object), _value(value));
        return null;
      case HirVirtualCall() || HirCall():
        return block.add(_call(block, instruction as HirCalling));
      case HirPrint(:final text):
        output.write(block, standardOutput, '$text\n');
        return null;
      case HirWriteError(:final text):
        output.write(block, standardError, text);
        return null;
      case HirIsInstance(:final test, :final object):
        return layout.isInstance(block, statics.test(test), _value(object));
    }
  }

  /// The call that [calling] makes, not yet part of [block].
  LirCall _call(LirBlock block, HirCalling calling) {
    switch (calling) {
      case HirNew(:final target):
        return layout.allocation(block, target);
      case HirVirtualCall(:final selector, :final receiver, :final arguments):
        final object = _value(receiver);
        return CallIndirect(
          layout.lookUp(block, selector, object),
          _selectorSignature(selector),
          [object, ...arguments.map(_value)],
        );
      case HirCall(:final target, :final arguments):
        return Call(
          symbols[target]!,
          signatureOf(target),
          arguments.map(_value),
        );
    }
  }

  Invoke _invoke(LirBlock block, HirInvoke invoke) {
    final HirInvoke(:call, :onReturn, :onThrow) = invoke;
    var normal = _edge(onReturn);
    if (call is HirNew) {
      // Objects get their class before they are used.
      final made = LirBlock([.ref]);
      _added.add(made);
      layout.setClass(made, made.parameters.single, call.target);
      made.end(
        Jump(
          LirEdge(normal.target, [made.parameters.single, ...normal.arguments]),
        ),
      );
      normal = LirEdge(made);
    }
    return Invoke(_call(block, call), normal, _edge(onThrow));
  }

  LirEdge _edge(HirEdge edge) =>
      LirEdge(_blocks[edge.target]!, edge.arguments.map(_value));

  LirTerminator _terminator(LirBlock block, HirTerminator end) {
    switch (end) {
      case HirJump(:final edge):
        return Jump(_edge(edge));
      case HirBranch(:final condition, :final ifTrue, :final ifFalse):
        return Branch(_value(condition), _edge(ifTrue), _edge(ifFalse));
      case HirReturn(:final value):
        return Return(value == null ? null : _value(value));
      case HirThrow(:final exception, :final trace):
        return Throw(_value(exception), _value(trace));
      case final HirInvoke invoke:
        return _invoke(block, invoke);
      case HirExit(:final code):
        block.add(callSystem('exit', [_value(code)]));
        return Unreachable();
      case HirUnreachable():
        return Unreachable();
    }
  }
}
