import 'host.dart';
import 'ir.dart';

const int ssaRead = 1;
const int ssaWrite = 2;
const int ssaAllocate = 4;
const int ssaThrow = 8;
const int ssaGc = 16;
const int ssaNative = 32;

class SsaFunction {
  List<int> arguments;
  List<int> valueTypes;
  List<SsaBlock> blocks;
  int result;

  SsaFunction(this.arguments, this.valueTypes, this.blocks, this.result);
}

class SsaBlock {
  List<int> parameters;
  List<int> localSlots;
  List<SsaInstruction> instructions;
  SsaTerminator end;

  SsaBlock(this.parameters, this.localSlots, this.instructions, this.end);
}

class SsaInstruction {
  int op;
  int value;
  int target;
  List<int> inputs;
  int effects;
  int resultType;

  SsaInstruction(
    this.op,
    this.value,
    this.target,
    this.inputs,
    this.effects,
    this.resultType,
  );
}

class SsaEdge {
  int target;
  List<int> arguments;

  SsaEdge(this.target, this.arguments);
}

class SsaTerminator {
  int kind;
  int value;
  SsaEdge first;
  SsaEdge second;

  SsaTerminator(this.kind, this.value, this.first, this.second);
}

class SsaShape {
  bool known;
  List<int> types;

  SsaShape(this.known, this.types);
}

class SsaFlow {
  int start;
  int end;
  List<int> successors;
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

Never ssaError(String message) {
  print('dartc SSA: ' + message);
  hostExit(1);
}

List<int> ssaFill(int count, int value) {
  List<int> values = <int>[];
  var i = 0;
  while (i < count) {
    values.add(value);
    i = i + 1;
  }
  return values;
}

List<int> ssaCopy(List<int> values) {
  List<int> copy = <int>[];
  var i = 0;
  while (i < values.length) {
    copy.add(values[i]);
    i = i + 1;
  }
  return copy;
}

int ssaInputCount(int op, int position) {
  if (op == opCall || op == opBuiltin) return ir[position + 2];
  if (op == opStoreGlobal) return 1;
  if (op == opNeg ||
      op == opBitNot ||
      op == opNot ||
      op == opTypeTest ||
      op == opTypeCast)
    return 1;
  if (op >= opAdd && op <= opGe) return 2;
  return 0;
}

List<SsaFlow> ssaControlFlow(FunctionInfo info, int end) {
  var leaders = ssaFill(end - info.start + 1, 0);
  leaders[0] = 1;
  var position = info.start;
  while (position < end) {
    var op = ir[position];
    var next = position + irWidth(op);
    if (op == opJump || op == opJumpFalse || op == opJumpTrue) {
      leaders[ir[position + 1] - info.start] = 1;
    }
    if ((op == opJump ||
            op == opJumpFalse ||
            op == opJumpTrue ||
            op == opReturn) &&
        next < end) {
      leaders[next - info.start] = 1;
    }
    position = next;
  }
  List<int> starts = <int>[];
  var i = 0;
  while (i < end - info.start) {
    if (leaders[i] == 1) starts.add(info.start + i);
    i = i + 1;
  }
  List<SsaFlow> flows = <SsaFlow>[];
  var blockAt = ssaFill(end - info.start + 1, -1);
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
        ssaFill(info.locals, 0),
        ssaFill(info.locals, 0),
        ssaFill(info.locals, 0),
        SsaShape(false, <int>[]),
      ),
    );
    i = i + 1;
  }
  i = 0;
  while (i < flows.length) {
    var flow = flows[i];
    position = flow.start;
    var last = position;
    while (position < flow.end) {
      last = position;
      var op = ir[position];
      if (op == opLoadLocal) {
        var slot = ir[position + 1];
        if (flow.definitions[slot] == 0) flow.uses[slot] = 1;
      }
      if (op == opStoreLocal) flow.definitions[ir[position + 1]] = 1;
      position = position + irWidth(op);
    }
    var finalOp = ir[last];
    if (finalOp == opJump) {
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
    } else if (finalOp == opJumpFalse) {
      flow.successors.add(i + 1);
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
    } else if (finalOp == opJumpTrue) {
      flow.successors.add(blockAt[ir[last + 1] - info.start]);
      flow.successors.add(i + 1);
    } else if (finalOp != opReturn && i + 1 < flows.length) {
      flow.successors.add(i + 1);
    }
    i = i + 1;
  }
  return flows;
}

void ssaLiveness(List<SsaFlow> flows, int locals) {
  var changed = true;
  while (changed) {
    changed = false;
    var i = flows.length;
    while (i > 0) {
      i = i - 1;
      var flow = flows[i];
      var slot = 0;
      while (slot < locals) {
        var live = flow.uses[slot];
        if (flow.definitions[slot] == 0) {
          var edge = 0;
          while (edge < flow.successors.length) {
            if (flows[flow.successors[edge]].live[slot] != 0) live = 1;
            edge = edge + 1;
          }
        }
        if (flow.live[slot] != live) {
          flow.live[slot] = live;
          changed = true;
        }
        slot = slot + 1;
      }
    }
  }
}

void ssaStackShapes(FunctionInfo info, List<SsaFlow> flows) {
  List<int> work = <int>[0];
  flows[0].shape.known = true;
  var cursor = 0;
  while (cursor < work.length) {
    var flow = flows[work[cursor]];
    var stack = ssaCopy(flow.shape.types);
    var position = flow.start;
    while (position < flow.end) {
      var op = ir[position];
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
      } else if (op != opJump) {
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
      var successor = flow.successors[edge];
      var shape = flows[successor].shape;
      if (!shape.known) {
        shape.known = true;
        shape.types = ssaCopy(stack);
        work.add(successor);
      } else {
        if (shape.types.length != stack.length) {
          ssaError(info.name + ': incompatible stack heights at merge');
        }
        var slot = 0;
        while (slot < stack.length) {
          if (shape.types[slot] != stack[slot]) {
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
  var value = function.valueTypes.length;
  function.valueTypes.add(type);
  return value;
}

SsaEdge ssaTransfer(
  SsaBlock target,
  int targetId,
  List<int> locals,
  List<int> stack,
) {
  List<int> values = <int>[];
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

int ssaEffects(int op, int target) {
  if (op == opTypeCast) return ssaRead | ssaAllocate | ssaThrow | ssaGc;
  if (op == opLoadGlobal) return ssaRead;
  if (op == opStoreGlobal) return ssaWrite;
  if (op == opDiv || op == opMod || op == opShl || op == opShr || op == opUshr)
    return ssaThrow;
  if (op == opCall) {
    return ssaRead | ssaWrite | ssaAllocate | ssaThrow | ssaGc | ssaNative;
  }
  if (op == opBuiltin) {
    if (target == bFunctionEntry || target == bFunctionType)
      return ssaRead | ssaNative;
    if (target == bValueIdentical) return ssaRead;
    if (target == bBoxRef || target == bBoxBool) return 0;
    if (target == bNativeTarget) return 0;
    if (target == bNativeFramePointer) return ssaRead | ssaNative;
    if (target == bNativeLoad64 ||
        target == bNativeLoad8 ||
        target == bNativeLoad16) {
      return ssaRead | ssaNative;
    }
    if (target == bNativeStore64 ||
        target == bNativeStore8 ||
        target == bNativeStore16) {
      return ssaWrite | ssaNative;
    }
    if (target == bNativeSyscall) return ssaRead | ssaWrite | ssaNative;
    return ssaRead | ssaWrite | ssaAllocate | ssaThrow | ssaGc | ssaNative;
  }
  return 0;
}

void ssaTranslateBlock(
  FunctionInfo info,
  SsaFunction function,
  List<SsaFlow> flows,
  List<int> blockIds,
  int flowId,
) {
  var flow = flows[flowId];
  var block = function.blocks[blockIds[flowId]];
  var locals = ssaFill(info.locals, -1);
  List<int> stack = <int>[];
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
    var op = ir[position];
    if (op == opLoadLocal) {
      stack.add(locals[ir[position + 1]]);
    } else if (op == opStoreLocal) {
      locals[ir[position + 1]] = stack.removeLast();
    } else if (op == opDup) {
      stack.add(stack[stack.length - 1]);
    } else if (op == opPop) {
      stack.removeLast();
    } else if (op == opReturn) {
      var value = stack.removeLast();
      // Void values can be observed through void contexts such as List<void>.
      block.end = SsaTerminator(
        3,
        value,
        SsaEdge(-1, <int>[]),
        SsaEdge(-1, <int>[]),
      );
    } else if (op == opJump || op == opJumpFalse || op == opJumpTrue) {
      var next = blockIds[flow.successors[0]];
      if (op == opJump) {
        block.end = SsaTerminator(
          1,
          -1,
          ssaTransfer(function.blocks[next], next, locals, stack),
          SsaEdge(-1, <int>[]),
        );
      } else {
        var condition = stack.removeLast();
        var otherwise = blockIds[flow.successors[1]];
        block.end = SsaTerminator(
          2,
          condition,
          ssaTransfer(function.blocks[next], next, locals, stack),
          ssaTransfer(function.blocks[otherwise], otherwise, locals, stack),
        );
      }
    } else {
      var count = ssaInputCount(op, position);
      List<int> inputs = <int>[];
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
      if (op != opStoreGlobal) {
        value = ssaValue(function, irTypes[position]);
        stack.add(value);
      }
      block.instructions.add(
        SsaInstruction(
          op,
          value,
          target,
          inputs,
          ssaEffects(op, target),
          irTypes[position],
        ),
      );
    }
    position = position + irWidth(op);
  }
  if (block.end.kind == 0) {
    if (flow.successors.length == 0) {
      ssaError(info.name + ': missing block terminator');
    }
    var next = blockIds[flow.successors[0]];
    block.end = SsaTerminator(
      1,
      -1,
      ssaTransfer(function.blocks[next], next, locals, stack),
      SsaEdge(-1, <int>[]),
    );
  }
}

SsaFunction ssaBuildFunction(FunctionInfo info, int end) {
  var flows = ssaControlFlow(info, end);
  ssaLiveness(flows, info.locals);
  ssaStackShapes(info, flows);
  var function = SsaFunction(<int>[], <int>[], <SsaBlock>[], info.result);
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
  List<int> blockIds = <int>[];
  var flowId = 0;
  while (flowId < flows.length) {
    var flow = flows[flowId];
    if (flow.shape.known) {
      List<int> parameters = <int>[];
      List<int> localSlots = <int>[];
      var slot = 0;
      while (slot < info.locals) {
        if (flow.live[slot] != 0) {
          localSlots.add(slot);
          parameters.add(ssaValue(function, info.localTypes[slot]));
        }
        slot = slot + 1;
      }
      slot = 0;
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
  var locals = ssaFill(info.locals, -1);
  i = 0;
  while (i < function.arguments.length) {
    locals[i] = function.arguments[i];
    i = i + 1;
  }
  var first = function.blocks[blockIds[0]];
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
  List<SsaFunction> result = <SsaFunction>[];
  var i = 0;
  while (i < functions.length) {
    var end = ir.length;
    if (i + 1 < functions.length) end = functions[i + 1].start;
    result.add(ssaBuildFunction(functions[i], end));
    i = i + 1;
  }
  return result;
}
