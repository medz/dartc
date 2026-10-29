import 'ir.dart';
import 'ssa.dart';
import 'types.dart';

class SsaShape {
  bool known;
  List<int> types;

  SsaShape(this.known, this.types);
}

class SsaFlow {
  int exceptional = -1;
  int start;
  int end;
  List<int> successors;
  // Local slot sets, packed into 64-bit words.
  List<int> uses;
  List<int> definitions;
  List<int> live;
  SsaShape shape;

  SsaFlow(
    this.start,
    this.end,
    this.successors,
    this.uses,
    this.definitions,
    this.live,
    this.shape,
  );
}

int ssaInputCount(int op, int position) {
  if (op == opCall || op == opGenericCall || op == opBuiltin)
    return ir[position + 2];
  if (op == opStoreGlobal) return 1;
  if (op == opDoubleNeg ||
      op == opIntToDouble ||
      op == opNeg ||
      op == opBitNot ||
      op == opNot ||
      op == opTypeTest ||
      op == opTypeCast)
    return 1;
  if (op >= opAdd && op <= opGe || op >= opDoubleAdd && op <= opDoubleCompare)
    return 2;
  return 0;
}

bool ssaEndsFlow(int position) =>
    ir[position] == opReturn ||
    ir[position] == opUnreachable ||
    irTypes[position] == tNever;

List<SsaFlow> ssaControlFlow(FunctionInfo info, int end) {
  if (info.start < 0 || end <= info.start || end > ir.length)
    ssaError('invalid function IR range: ' + info.name);
  final leaders = List<int>.filled(end - info.start + 1, 0);
  final handlerAt = List<int>.filled(end - info.start + 1, -1);
  final handlers = <int>[];
  leaders[0] = 1;
  var position = info.start;
  while (position < end) {
    final op = ir[position];
    final next = position + irWidth(op);
    if (next > end)
      ssaError('instruction exceeds function IR range: ' + info.name);
    if (op == opBeginTry ||
        op == opJump ||
        op == opJumpFalse ||
        op == opJumpTrue) {
      final target = ir[position + 1];
      if (target < info.start || target >= end)
        ssaError('branch leaves function IR range: ' + info.name);
    }
    if (op == opBeginTry) {
      final target = ir[position + 1];
      handlers.add(target);
      leaders[target - info.start] = 1;
    } else if (op == opEndTry) {
      if (handlers.isEmpty) ssaError(info.name + ': unmatched try end');
      handlers.removeLast();
    } else if (handlers.isNotEmpty &&
        (ssaEffects(op, irWidth(op) > 1 ? ir[position + 1] : 0) & ssaThrow) !=
            0) {
      handlerAt[position - info.start] = handlers.last;
    }
    if (op == opJump || op == opJumpFalse || op == opJumpTrue) {
      leaders[ir[position + 1] - info.start] = 1;
    }
    if ((op == opJump ||
            op == opJumpFalse ||
            op == opJumpTrue ||
            op == opBeginTry ||
            op == opEndTry ||
            handlerAt[position - info.start] >= 0 ||
            ssaEndsFlow(position)) &&
        next < end) {
      leaders[next - info.start] = 1;
    }
    position = next;
  }
  if (handlers.isNotEmpty) ssaError(info.name + ': unterminated try region');
  final List<int> starts = <int>[];
  var i = 0;
  while (i < end - info.start) {
    if (leaders[i] == 1) starts.add(info.start + i);
    i = i + 1;
  }
  final List<SsaFlow> flows = <SsaFlow>[];
  final blockAt = List<int>.filled(end - info.start + 1, -1);
  final localWords = (info.locals + 63) ~/ 64;
  i = 0;
  while (i < starts.length) {
    var stop = end;
    if (i + 1 < starts.length) stop = starts[i + 1];
    blockAt[starts[i] - info.start] = i;
    flows.add(
      SsaFlow(
        starts[i],
        stop,
        <int>[],
        List<int>.filled(localWords, 0),
        List<int>.filled(localWords, 0),
        List<int>.filled(localWords, 0),
        SsaShape(false, <int>[]),
      ),
    );
    i = i + 1;
  }
  i = 0;
  while (i < flows.length) {
    final flow = flows[i];
    position = flow.start;
    var last = position;
    while (position < flow.end) {
      last = position;
      final op = ir[position];
      if (op == opLoadLocal) {
        final slot = ir[position + 1];
        final word = slot ~/ 64;
        final bit = 1 << (slot & 63);
        if ((flow.definitions[word] & bit) == 0) flow.uses[word] |= bit;
      }
      if (op == opStoreLocal) {
        final slot = ir[position + 1];
        flow.definitions[slot ~/ 64] |= 1 << (slot & 63);
      }
      position = position + irWidth(op);
    }
    final finalOp = ir[last];
    if (finalOp == opJump) {
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
    } else if (finalOp == opJumpFalse) {
      flow.successors.add(i + 1);
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
    } else if (finalOp == opJumpTrue) {
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
      flow.successors.add(i + 1);
    } else if (!ssaEndsFlow(last) && i + 1 < flows.length) {
      flow.successors.add(i + 1);
    }
    final handler = handlerAt[last - info.start];
    if (handler >= 0) {
      flow.exceptional = blockAt[handler - info.start];
      flow.successors.add(flow.exceptional);
    }
    i = i + 1;
  }
  return flows;
}

void ssaLiveness(List<SsaFlow> flows) {
  var changed = true;
  while (changed) {
    changed = false;
    var i = flows.length;
    while (i > 0) {
      i = i - 1;
      final flow = flows[i];
      var word = 0;
      while (word < flow.live.length) {
        var outgoing = 0;
        var edge = 0;
        while (edge < flow.successors.length) {
          outgoing |= flows[flow.successors[edge]].live[word];
          edge = edge + 1;
        }
        final live = flow.uses[word] | (outgoing & ~flow.definitions[word]);
        if (flow.live[word] != live) {
          flow.live[word] = live;
          changed = true;
        }
        word = word + 1;
      }
    }
  }
}

void ssaStackShapes(FunctionInfo info, List<SsaFlow> flows) {
  final List<int> work = <int>[0];
  flows[0].shape.known = true;
  var cursor = 0;
  while (cursor < work.length) {
    final flow = flows[work[cursor]];
    final stack = <int>[...flow.shape.types];
    var position = flow.start;
    while (position < flow.end) {
      final op = ir[position];
      if (op == opUnreachable || irTypes[position] == tNever) break;
      if (op == opLoadLocal) {
        stack.add(info.localTypes[ir[position + 1]]);
      } else if (op == opDup) {
        stack.add(stack[stack.length - 1]);
      } else if (op == opStoreLocal ||
          op == opStoreGlobal ||
          op == opPop ||
          op == opJumpFalse ||
          op == opJumpTrue ||
          op == opReturn) {
        stack.removeLast();
      } else if (op != opJump && op != opBeginTry && op != opEndTry) {
        var count = ssaInputCount(op, position);
        while (count > 0) {
          stack.removeLast();
          count = count - 1;
        }
        stack.add(irTypes[position]);
      }
      position = position + irWidth(op);
    }
    var edge = 0;
    while (edge < flow.successors.length) {
      final successor = flow.successors[edge];
      final transferred =
          flow.exceptional >= 0 && edge == flow.successors.length - 1
          ? const <int>[]
          : stack;
      final shape = flows[successor].shape;
      if (!shape.known) {
        shape.known = true;
        shape.types = <int>[...transferred];
        work.add(successor);
      } else {
        if (shape.types.length != transferred.length) {
          ssaError(info.name + ': incompatible stack heights at merge');
        }
        var slot = 0;
        while (slot < transferred.length) {
          if (shape.types[slot] != transferred[slot]) {
            ssaError(info.name + ': incompatible stack types at merge');
          }
          slot = slot + 1;
        }
      }
      edge = edge + 1;
    }
    cursor = cursor + 1;
  }
}

int ssaValue(SsaFunction function, int type) {
  final value = function.valueTypes.length;
  function.valueTypes.add(type);
  return value;
}

SsaEdge ssaTransfer(
  SsaBlock target,
  int targetId,
  List<int> locals,
  List<int> stack,
) {
  final List<int> values = <int>[];
  var i = 0;
  while (i < target.localSlots.length) {
    values.add(locals[target.localSlots[i]]);
    i = i + 1;
  }
  i = 0;
  while (i < stack.length) {
    values.add(stack[i]);
    i = i + 1;
  }
  return SsaEdge(targetId, values);
}

void ssaTranslateBlock(
  FunctionInfo info,
  SsaFunction function,
  List<SsaFlow> flows,
  List<int> blockIds,
  int flowId,
) {
  final flow = flows[flowId];
  final block = function.blocks[blockIds[flowId]];
  final locals = List<int>.filled(info.locals, -1);
  final List<int> stack = <int>[];
  var i = 0;
  while (i < block.localSlots.length) {
    locals[block.localSlots[i]] = block.parameters[i];
    i = i + 1;
  }
  while (i < block.parameters.length) {
    stack.add(block.parameters[i]);
    i = i + 1;
  }
  var position = flow.start;
  while (position < flow.end) {
    final op = ir[position];
    if (op == opBeginTry || op == opEndTry) {
      // Lexical region markers have no runtime value or normal-path cost.
    } else if (op == opUnreachable) {
      block.end = SsaTerminator(
        4,
        -1,
        SsaEdge(-1, <int>[]),
        SsaEdge(-1, <int>[]),
      );
    } else if (op == opLoadLocal) {
      stack.add(locals[ir[position + 1]]);
    } else if (op == opStoreLocal) {
      locals[ir[position + 1]] = stack.removeLast();
    } else if (op == opDup) {
      stack.add(stack[stack.length - 1]);
    } else if (op == opPop) {
      stack.removeLast();
    } else if (op == opReturn) {
      final value = stack.removeLast();
      // Void values can be observed through void contexts such as List<void>.
      block.end = SsaTerminator(
        3,
        value,
        SsaEdge(-1, <int>[]),
        SsaEdge(-1, <int>[]),
      );
    } else if (op == opJump || op == opJumpFalse || op == opJumpTrue) {
      final next = blockIds[flow.successors[0]];
      if (op == opJump) {
        block.end = SsaTerminator(
          1,
          -1,
          ssaTransfer(function.blocks[next], next, locals, stack),
          SsaEdge(-1, <int>[]),
        );
      } else {
        final condition = stack.removeLast();
        final otherwise = blockIds[flow.successors[1]];
        block.end = SsaTerminator(
          2,
          condition,
          ssaTransfer(function.blocks[next], next, locals, stack),
          ssaTransfer(function.blocks[otherwise], otherwise, locals, stack),
        );
      }
    } else {
      var count = ssaInputCount(op, position);
      final List<int> inputs = <int>[];
      i = stack.length - count;
      while (i < stack.length) {
        inputs.add(stack[i]);
        i = i + 1;
      }
      while (count > 0) {
        stack.removeLast();
        count = count - 1;
      }
      var target = 0;
      if (irWidth(op) > 1) target = ir[position + 1];
      var value = -1;
      final type = irTypes[position];
      final effects = ssaEffects(op, target);
      if (op != opStoreGlobal && type != tNever) {
        value = ssaValue(function, irTypes[position]);
        stack.add(value);
      }
      if (type != tNever || effects != 0) {
        block.instructions.add(
          SsaInstruction(op, value, target, inputs, effects, type),
        );
      }
    }
    if (irTypes[position] == tNever) {
      block.end = SsaTerminator(
        4,
        -1,
        SsaEdge(-1, <int>[]),
        SsaEdge(-1, <int>[]),
      );
    }
    position = position + irWidth(op);
  }
  if (flow.exceptional >= 0) {
    final caught = blockIds[flow.exceptional];
    final never = block.end.kind == 4;
    final normal = never ? -1 : blockIds[flow.successors[0]];
    block.end = SsaTerminator(
      never ? 6 : 5,
      -1,
      never
          ? SsaEdge(-1, <int>[])
          : ssaTransfer(function.blocks[normal], normal, locals, stack),
      ssaTransfer(function.blocks[caught], caught, locals, const <int>[]),
    );
  }
  if (block.end.kind == 0) {
    if (flow.successors.length == 0) {
      ssaError(info.name + ': missing block terminator');
    }
    final next = blockIds[flow.successors[0]];
    block.end = SsaTerminator(
      1,
      -1,
      ssaTransfer(function.blocks[next], next, locals, stack),
      SsaEdge(-1, <int>[]),
    );
  }
}

SsaFunction ssaBuildFunction(FunctionInfo info, int end) {
  final flows = ssaControlFlow(info, end);
  ssaLiveness(flows);
  ssaStackShapes(info, flows);
  final function = SsaFunction(<int>[], <int>[], <SsaBlock>[], info.result);
  var i = 0;
  while (i < info.parameters) {
    function.arguments.add(ssaValue(function, info.parameterTypes[i]));
    i = i + 1;
  }
  function.blocks.add(
    SsaBlock(
      <int>[],
      <int>[],
      <SsaInstruction>[],
      SsaTerminator(0, -1, SsaEdge(-1, <int>[]), SsaEdge(-1, <int>[])),
    ),
  );
  final List<int> blockIds = <int>[];
  var flowId = 0;
  while (flowId < flows.length) {
    final flow = flows[flowId];
    if (flow.shape.known) {
      final List<int> parameters = <int>[];
      final List<int> localSlots = <int>[];
      var word = 0;
      while (word < flow.live.length) {
        var bits = flow.live[word];
        var bit = 0;
        while (bits != 0) {
          if ((bits & 1) != 0) {
            final slot = word * 64 + bit;
            localSlots.add(slot);
            parameters.add(ssaValue(function, info.localTypes[slot]));
          }
          bits >>>= 1;
          bit = bit + 1;
        }
        word = word + 1;
      }
      var slot = 0;
      while (slot < flow.shape.types.length) {
        parameters.add(ssaValue(function, flow.shape.types[slot]));
        slot = slot + 1;
      }
      blockIds.add(function.blocks.length);
      function.blocks.add(
        SsaBlock(
          parameters,
          localSlots,
          <SsaInstruction>[],
          SsaTerminator(0, -1, SsaEdge(-1, <int>[]), SsaEdge(-1, <int>[])),
        ),
      );
    } else {
      blockIds.add(-1);
    }
    flowId = flowId + 1;
  }
  final locals = List<int>.filled(info.locals, -1);
  i = 0;
  while (i < function.arguments.length) {
    locals[i] = function.arguments[i];
    i = i + 1;
  }
  final first = function.blocks[blockIds[0]];
  i = 0;
  while (i < first.localSlots.length) {
    if (first.localSlots[i] >= info.parameters) {
      ssaError(info.name + ': local is read before definition at entry');
    }
    i = i + 1;
  }
  function.blocks[0].end = SsaTerminator(
    1,
    -1,
    ssaTransfer(first, blockIds[0], locals, <int>[]),
    SsaEdge(-1, <int>[]),
  );
  flowId = 0;
  while (flowId < flows.length) {
    if (flows[flowId].shape.known) {
      ssaTranslateBlock(info, function, flows, blockIds, flowId);
    }
    flowId = flowId + 1;
  }
  return function;
}

List<SsaFunction> buildSsa() {
  final List<SsaFunction> result = <SsaFunction>[];
  var i = 0;
  while (i < functions.length) {
    result.add(ssaBuildFunction(functions[i], functions[i].end));
    i = i + 1;
  }
  return result;
}
