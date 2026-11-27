import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'boxes.dart';
import 'dispatch.dart';
import 'instance_tests.dart';
import 'machine.dart';
import 'operators.dart';
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
  final ObjectLayout layout,
  final StaticData statics,
  final MachineLowering machine,
) {
  final _values = <HirValue, LirValue>{};
  final _blocks = <HirBlock, LirBlock>{};
  final _added = <LirBlock>[];
  late final _boxes = BoxLowering(layout, _added.add);
  late final _instanceTests = InstanceTests(
    layout,
    statics,
    _boxes,
    _added.add,
  );

  /// The block that code is added to.
  late LirBlock _block;

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
      _block = _blocks[block]!;
      for (final instruction in block.instructions) {
        final value = _instruction(instruction);
        if (value != null) _values[instruction] = value;
      }
      _terminate(block.terminator!);
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

  /// Goes on with the block of [made], and gives its value.
  LirValue _continue((LirBlock, LirValue) made) {
    _block = made.$1;
    return made.$2;
  }

  LirValue? _instruction(HirInstruction instruction) {
    final block = _block;
    final operators = OperatorLowering(block);
    switch (instruction) {
      case HirConst() || HirNull() || HirStatic():
        return _constant(block, instruction);
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
      case HirNew(:final target):
        final made = block.add(layout.allocation(block, target));
        return layout.setClass(block, made, target);
      case HirNewArray(:final target, :final length):
        return layout.setClass(
          block,
          block.add(layout.allocation(block, target, _value(length))),
          target,
          _value(length),
        );
      case HirLength() || HirLoadElement() || HirStoreElement():
        return _element(block, instruction);
      case HirNativeFunction(:final name):
        return machine.nativeFunction(block, name);
      case HirClassNumber(:final target):
        return block.add(ConstInt(layout.numberOf(target) ?? -1));
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
      case HirMachine(op: .classNumber, :final arguments):
        return _classNumber(_value(arguments.single));
      case HirMachine(:final op, :final arguments):
        return machine.lower(block, op, arguments.map(_value).toList());
      case HirLoad(:final field, :final object):
        return layout.load(block, field, _value(object));
      case HirStore(:final field, :final object, :final value):
        layout.store(block, field, _value(object), _value(value));
        return null;
      case HirBox(:final target, :final value):
        return _continue(
          _boxes.box(block, target, _value(value), (block) {
            return (block, block.add(layout.allocation(block, target)));
          }),
        );
      case HirRefine(:final value):
        return _value(value);
      case HirUnbox(:final field, :final object):
        return _continue(_boxes.unbox(block, field, _value(object)));
      case HirVirtualCall() || HirCall():
        if (_testsInstance(instruction) case final tested?) return tested;
        // Finding what is called can end the block.
        final call = _call(instruction as HirCalling);
        return _block.add(call);
      case HirHasClass(:final target, :final object, :final mayBeInteger):
        final number = _classNumber(_value(object), mayBeInteger: mayBeInteger);
        final wanted = _block.add(ConstInt(layout.numberOf(target)!));
        return _block.add(Compare(.eq, number, wanted));
      case HirIsInstance(:final test, :final object):
        final number = _classNumber(_value(object));
        return layout.isInstance(_block, statics.test(test), number);
    }
  }

  /// Whether an object is of a type, if [instruction] asks that and the class
  /// of the object may tell.
  LirValue? _testsInstance(HirInstruction instruction) {
    if (instruction
        case HirCall(:final target, arguments: [final object, final type])
        when _instanceTests.lowers(target, type)) {
      final call = _call(instruction);
      return _continue(
        _instanceTests.lower(_block, _value(object), type, _value(type), call),
      );
    }
    return null;
  }

  LirValue? _constant(LirBlock block, HirInstruction instruction) {
    switch (instruction) {
      case HirConst(:final Object value):
        return block.add(switch (value) {
          int() => ConstInt(value),
          double() => ConstFloat(value),
          _ => ConstInt(value == true ? 1 : 0),
        });
      case HirStatic(:final object):
        final bits = statics.bitsOf(object);
        return bits == null
            ? block.add(StaticObject(statics.constant(object)))
            : block.add(Convert(.intToRef, block.add(ConstInt(bits))));
      default:
        return block.add(ConstNull());
    }
  }

  /// A use of the elements of an array.
  LirValue? _element(LirBlock block, HirInstruction instruction) {
    final [array, ...rest] = instruction.inputs.map(_value).toList();
    switch (instruction) {
      case HirLoadElement(:final element):
        return layout.loadElement(block, element, array, rest.single);
      case HirStoreElement(:final element):
        final [index, value] = rest;
        layout.storeElement(block, element, array, index, value);
        return null;
      default:
        return layout.length(block, array);
    }
  }

  LirValue _classNumber(LirValue object, {bool mayBeInteger = true}) =>
      _continue(_boxes.classNumber(_block, object, mayBeInteger: mayBeInteger));

  /// The call that [calling] makes, not yet part of a block.
  LirCall _call(HirCalling calling) =>
      _callOnly(calling)..place = _placeOf(calling.place);

  LirCall _callOnly(HirCalling calling) {
    final block = _block;
    switch (calling) {
      case HirBox(:final target):
        return layout.allocation(block, target);
      case HirNew(:final target):
        return layout.allocation(block, target);
      case HirNewArray(:final target, :final length):
        return layout.allocation(block, target, _value(length));
      case HirVirtualCall(:final selector, :final receiver, :final arguments):
        final object = _value(receiver);
        final number = _classNumber(
          object,
          mayBeInteger: layout.canReceive(selector),
        );
        return CallIndirect(
          layout.lookUp(_block, selector, number),
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

  void _invoke(HirInvoke invoke) {
    final HirInvoke(:call, :onReturn, :onThrow) = invoke;
    (LirBlock, LirValue) allocate(LirBlock block, LirCall allocation) {
      final made = LirBlock([.ref]);
      _added.add(made);
      block.end(Invoke(allocation, LirEdge(made), _edge(onThrow)));
      return (made, made.parameters.single);
    }

    LirValue? result;
    switch (call) {
      case HirNew(:final target) || HirNewArray(:final target):
        // Objects get their class before they are used.
        final object = _continue(allocate(_block, _call(call)));
        result = layout.setClass(
          _block,
          object,
          target,
          call is HirNewArray ? _value(call.length) : null,
        );
      case HirBox(:final target, :final value):
        result = _continue(
          _boxes.box(
            _block,
            target,
            _value(value),
            (block) => allocate(block, layout.allocation(block, target)),
          ),
        );
      default:
        final made = _call(call);
        _block.end(Invoke(made, _edge(onReturn), _edge(onThrow)));
        return;
    }
    final LirEdge(:target, :arguments) = _edge(onReturn);
    _block.end(Jump(LirEdge(target, [result, ...arguments])));
  }

  LirEdge _edge(HirEdge edge) =>
      LirEdge(_blocks[edge.target]!, edge.arguments.map(_value));

  void _terminate(HirTerminator end) {
    if (end is HirInvoke) return _invoke(end);
    _block.end(_terminator(end));
  }

  LirTerminator _terminator(HirTerminator end) {
    switch (end) {
      case HirJump(:final edge):
        return Jump(_edge(edge));
      case HirBranch(:final condition, :final ifTrue, :final ifFalse):
        return Branch(_value(condition), _edge(ifTrue), _edge(ifFalse));
      case HirReturn(:final value):
        return Return(value == null ? null : _value(value));
      case HirThrow(:final exception, :final trace):
        return Throw(_value(exception), _value(trace));
      case HirExit(:final code):
        _block.add(callSystem('exit', [_value(code)]));
        return Unreachable();
      case HirInvoke() || HirUnreachable():
        return Unreachable();
    }
  }
}

final _places = Expando<LirPlace>();

/// [place] as LIR tells it.
LirPlace? _placeOf(HirPlace? place) => place == null
    ? null
    : _places[place] ??= LirPlace(
        place.function,
        place.uri,
        place.line,
        _placeOf(place.outer),
      );
