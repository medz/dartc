import 'ir.dart';
import 'types.dart';
import 'ssa.dart';

// Lattice states are unknown, one constant, and overdefined.
class SccpState {
  List<int> kinds;
  List<int> constants;
  List<int> blocks;
  List<int> edges;
  bool changed;

  SccpState(this.kinds, this.constants, this.blocks, this.edges, this.changed);
}

void sccpMeet(SccpState state, int value, int kind, int constant) {
  if (kind == 0 || state.kinds[value] == 2) return;
  if (state.kinds[value] == 0) {
    state.kinds[value] = kind;
    state.constants[value] = constant;
    state.changed = true;
  } else if (kind == 2 || state.constants[value] != constant) {
    state.kinds[value] = 2;
    state.changed = true;
  }
}

void sccpEdge(
  SccpState state,
  SsaFunction function,
  int source,
  int which,
  SsaEdge edge,
) {
  var key = source * 2 + which;
  if (state.edges[key] == 0) {
    state.edges[key] = 1;
    state.blocks[edge.target] = 1;
    state.changed = true;
  }
  var parameters = function.blocks[edge.target].parameters;
  var i = 0;
  while (i < parameters.length) {
    var input = edge.arguments[i];
    sccpMeet(state, parameters[i], state.kinds[input], state.constants[input]);
    i++;
  }
}

bool sccpArithmetic(int op) {
  return op >= opAdd && op <= opGe || op == opNot;
}

int sccpCalculate(int op, int left, int right) {
  if (op == opAdd) return left + right;
  if (op == opSub) return left - right;
  if (op == opMul) return left * right;
  if (op == opDiv) return left ~/ right;
  if (op == opMod) return left % right;
  if (op == opNeg) return -left;
  if (op == opAnd) return left & right;
  if (op == opOr) return left | right;
  if (op == opXor) return left ^ right;
  if (op == opShl) return left << right;
  if (op == opShr) return left >> right;
  if (op == opUshr) return left >>> right;
  if (op == opBitNot) return ~left;
  if (op == opEq) {
    if (left == right) return 1;
    return 0;
  }
  if (op == opNe) {
    if (left != right) return 1;
    return 0;
  }
  if (op == opLt) {
    if (left < right) return 1;
    return 0;
  }
  if (op == opLe) {
    if (left <= right) return 1;
    return 0;
  }
  if (op == opGt) {
    if (left > right) return 1;
    return 0;
  }
  if (op == opGe) {
    if (left >= right) return 1;
    return 0;
  }
  if (left == 0) return 1;
  return 0;
}

void sccpInstruction(
  SccpState state,
  SsaFunction function,
  SsaInstruction instruction,
) {
  var value = instruction.value;
  if (value < 0 || state.kinds[value] == 2) return;
  var type = function.valueTypes[value];
  if (type != tInt && type != tBool) {
    sccpMeet(state, value, 2, 0);
    return;
  }
  var op = instruction.op;
  if (op == opInt && instruction.effects == 0) {
    sccpMeet(state, value, 1, instruction.target);
    return;
  }
  if (op == opBuiltin &&
      instruction.target == bNativeTarget &&
      instruction.effects == 0) {
    sccpMeet(state, value, 1, targetOS);
    return;
  }
  var allowedEffects = 0;
  if (op == opDiv ||
      op == opMod ||
      op == opShl ||
      op == opShr ||
      op == opUshr) {
    allowedEffects = ssaThrow;
  }
  if (!sccpArithmetic(op) || (instruction.effects & ~allowedEffects) != 0) {
    sccpMeet(state, value, 2, 0);
    return;
  }
  var kind = 1;
  var i = 0;
  while (i < instruction.inputs.length) {
    var inputKind = state.kinds[instruction.inputs[i]];
    if (inputKind == 2) {
      kind = 2;
      break;
    }
    if (inputKind == 0) kind = 0;
    i++;
  }
  if (kind != 1) {
    sccpMeet(state, value, kind, 0);
    return;
  }
  var left = state.constants[instruction.inputs[0]];
  var right = 0;
  if (instruction.inputs.length == 2)
    right = state.constants[instruction.inputs[1]];
  if ((op == opDiv || op == opMod) && right == 0) {
    sccpMeet(state, value, 2, 0);
    return;
  }
  if ((op == opShl || op == opShr || op == opUshr) &&
      (right < 0 || right > 63)) {
    sccpMeet(state, value, 2, 0);
    return;
  }
  sccpMeet(state, value, 1, sccpCalculate(op, left, right));
}

SccpState sccpAnalyze(SsaFunction function) {
  var state = SccpState(
    ssaFill(function.valueTypes.length, 0),
    ssaFill(function.valueTypes.length, 0),
    ssaFill(function.blocks.length, 0),
    ssaFill(function.blocks.length * 2, 0),
    true,
  );
  state.blocks[0] = 1;
  var i = 0;
  while (i < function.arguments.length) {
    sccpMeet(state, function.arguments[i], 2, 0);
    i++;
  }
  while (state.changed) {
    state.changed = false;
    var b = 0;
    while (b < function.blocks.length) {
      if (state.blocks[b] == 1) {
        var block = function.blocks[b];
        i = 0;
        while (i < block.instructions.length) {
          sccpInstruction(state, function, block.instructions[i]);
          i++;
        }
        var end = block.end;
        if (end.kind == 1) {
          sccpEdge(state, function, b, 0, end.first);
        } else if (end.kind == 2) {
          var kind = state.kinds[end.value];
          if (kind == 2 || kind == 1 && state.constants[end.value] != 0) {
            sccpEdge(state, function, b, 0, end.first);
          }
          if (kind == 2 || kind == 1 && state.constants[end.value] == 0) {
            sccpEdge(state, function, b, 1, end.second);
          }
        }
      }
      b++;
    }
  }
  return state;
}

void sccpRewrite(SsaFunction function, SccpState state) {
  var mapping = ssaFill(function.blocks.length, -1);
  List<SsaBlock> blocks = <SsaBlock>[];
  var b = 0;
  while (b < function.blocks.length) {
    if (state.blocks[b] == 1) {
      mapping[b] = blocks.length;
      var block = function.blocks[b];
      var i = 0;
      while (i < block.instructions.length) {
        var instruction = block.instructions[i];
        if (instruction.value >= 0 && state.kinds[instruction.value] == 1) {
          instruction.op = opInt;
          instruction.target = state.constants[instruction.value];
          instruction.inputs = <int>[];
          instruction.effects = 0;
        }
        i++;
      }
      var end = block.end;
      if (end.kind == 2 && state.kinds[end.value] == 1) {
        var chosen = end.first;
        if (state.constants[end.value] == 0) chosen = end.second;
        block.end = SsaTerminator(1, -1, chosen, SsaEdge(-1, <int>[]));
      }
      blocks.add(block);
    }
    b++;
  }
  b = 0;
  while (b < blocks.length) {
    var end = blocks[b].end;
    if (end.kind == 1 || end.kind == 2)
      end.first.target = mapping[end.first.target];
    if (end.kind == 2) end.second.target = mapping[end.second.target];
    b++;
  }
  function.blocks = blocks;
}

void markLiveValue(List<int> live, List<int> work, int value) {
  if (live[value] == 0) {
    live[value] = 1;
    work.add(value);
  }
}

void addEdgeDependencies(
  SsaFunction function,
  List<List<int>> dependencies,
  SsaEdge edge,
) {
  var parameters = function.blocks[edge.target].parameters;
  var i = 0;
  while (i < edge.arguments.length) {
    var value = parameters[i];
    if (dependencies[value].length == 0) {
      dependencies[value] = <int>[edge.arguments[i]];
    } else {
      dependencies[value].add(edge.arguments[i]);
    }
    i++;
  }
}

int resolveValue(List<int> aliases, int value) {
  var result = value;
  while (aliases[result] != result) result = aliases[result];
  while (aliases[value] != value) {
    var next = aliases[value];
    aliases[value] = result;
    value = next;
  }
  return result;
}

List<int> simplifyBlockParameters(
  SsaFunction function,
  List<List<int>> dependencies,
) {
  List<int> aliases = <int>[];
  var i = 0;
  while (i < function.valueTypes.length) {
    aliases.add(i);
    i++;
  }
  var changed = true;
  while (changed) {
    changed = false;
    var b = 0;
    while (b < function.blocks.length) {
      var parameters = function.blocks[b].parameters;
      i = 0;
      while (i < parameters.length) {
        var parameter = parameters[i];
        if (aliases[parameter] == parameter) {
          var inputs = dependencies[parameter];
          var candidate = -1;
          var n = 0;
          while (n < inputs.length) {
            var input = resolveValue(aliases, inputs[n]);
            if (input != parameter) {
              if (candidate == -1) {
                candidate = input;
              } else if (candidate != input) {
                candidate = -2;
                break;
              }
            }
            n++;
          }
          if (candidate >= 0) {
            aliases[parameter] = candidate;
            changed = true;
          }
        }
        i++;
      }
      b++;
    }
  }
  return aliases;
}

void removeDeadEdgeArguments(
  SsaFunction function,
  List<int> live,
  List<int> aliases,
  SsaEdge edge,
) {
  var parameters = function.blocks[edge.target].parameters;
  List<int> kept = <int>[];
  var i = 0;
  while (i < parameters.length) {
    if (live[parameters[i]] != 0) {
      kept.add(resolveValue(aliases, edge.arguments[i]));
    }
    i++;
  }
  edge.arguments = kept;
}

void removeDeadValues(SsaFunction function) {
  List<int> roots = <int>[];
  List<List<int>> dependencies = <List<int>>[];
  List<int> empty = <int>[];
  var i = 0;
  while (i < function.valueTypes.length) {
    dependencies.add(empty);
    i++;
  }
  var b = 0;
  while (b < function.blocks.length) {
    var block = function.blocks[b];
    i = 0;
    while (i < block.instructions.length) {
      var instruction = block.instructions[i];
      if (instruction.value >= 0) {
        dependencies[instruction.value] = instruction.inputs;
      }
      if (instruction.effects != 0) {
        var n = 0;
        while (n < instruction.inputs.length) {
          roots.add(instruction.inputs[n]);
          n++;
        }
      }
      i++;
    }
    var end = block.end;
    if (end.kind == 2 || end.kind == 3 && end.value >= 0) {
      roots.add(end.value);
    }
    if (end.kind == 1 || end.kind == 2) {
      addEdgeDependencies(function, dependencies, end.first);
    }
    if (end.kind == 2) {
      addEdgeDependencies(function, dependencies, end.second);
    }
    b++;
  }
  var aliases = simplifyBlockParameters(function, dependencies);
  var live = ssaFill(function.valueTypes.length, 0);
  List<int> work = <int>[];
  i = 0;
  while (i < roots.length) {
    markLiveValue(live, work, resolveValue(aliases, roots[i]));
    i++;
  }
  i = 0;
  while (i < work.length) {
    var inputs = dependencies[work[i]];
    var n = 0;
    while (n < inputs.length) {
      markLiveValue(live, work, resolveValue(aliases, inputs[n]));
      n++;
    }
    i++;
  }
  b = 0;
  while (b < function.blocks.length) {
    var end = function.blocks[b].end;
    if (end.value >= 0) end.value = resolveValue(aliases, end.value);
    if (end.kind == 1 || end.kind == 2) {
      removeDeadEdgeArguments(function, live, aliases, end.first);
    }
    if (end.kind == 2) {
      removeDeadEdgeArguments(function, live, aliases, end.second);
    }
    b++;
  }
  b = 0;
  while (b < function.blocks.length) {
    var block = function.blocks[b];
    List<SsaInstruction> kept = <SsaInstruction>[];
    i = 0;
    while (i < block.instructions.length) {
      var instruction = block.instructions[i];
      if (instruction.effects != 0 ||
          instruction.value < 0 ||
          live[instruction.value] != 0) {
        var n = 0;
        while (n < instruction.inputs.length) {
          instruction.inputs[n] = resolveValue(aliases, instruction.inputs[n]);
          n++;
        }
        if (instruction.effects != 0 &&
            instruction.value >= 0 &&
            live[instruction.value] == 0) {
          instruction.value = -1;
        }
        kept.add(instruction);
      }
      i++;
    }
    block.instructions = kept;
    List<int> parameters = <int>[];
    List<int> localSlots = <int>[];
    i = 0;
    while (i < block.parameters.length) {
      if (live[block.parameters[i]] != 0) {
        parameters.add(block.parameters[i]);
        if (i < block.localSlots.length) localSlots.add(block.localSlots[i]);
      }
      i++;
    }
    block.parameters = parameters;
    block.localSlots = localSlots;
    b++;
  }
}

void resolveValues(List<int> aliases, List<int> values) {
  var i = 0;
  while (i < values.length) {
    values[i] = resolveValue(aliases, values[i]);
    i++;
  }
}

void simplifyBooleanChecks(SsaFunction function) {
  var boxes = <int>[];
  var b = 0;
  while (b < function.blocks.length) {
    var instructions = function.blocks[b].instructions;
    var i = 0;
    while (i < instructions.length) {
      var instruction = instructions[i];
      if (instruction.op == opBuiltin &&
          instruction.target == bBoxBool &&
          instruction.effects == 0 &&
          instruction.value >= 0 &&
          function.valueTypes[instruction.inputs[0]] == tBool) {
        if (boxes.isEmpty) boxes = ssaFill(function.valueTypes.length, -1);
        boxes[instruction.value] = instruction.inputs[0];
      }
      i++;
    }
    b++;
  }
  if (boxes.isEmpty) return;
  var aliases = <int>[];
  b = 0;
  while (b < function.blocks.length) {
    var instructions = function.blocks[b].instructions;
    var kept = 0;
    var i = 0;
    while (i < instructions.length) {
      var instruction = instructions[i];
      var check =
          instruction.op == opTypeCast && instruction.target == tBool ||
          instruction.op == opBuiltin &&
              (instruction.target == bValueBool ||
                  instruction.target == bValueCast &&
                      instruction.resultType == tBool);
      var source = -1;
      if (check) source = boxes[instruction.inputs[0]];
      if (source >= 0) {
        if (aliases.isEmpty) {
          var value = 0;
          while (value < function.valueTypes.length) {
            aliases.add(value);
            value++;
          }
        }
        if (instruction.value >= 0) aliases[instruction.value] = source;
      } else {
        instructions[kept] = instruction;
        kept++;
      }
      i++;
    }
    while (instructions.length > kept) instructions.removeLast();
    b++;
  }
  if (aliases.isEmpty) return;
  b = 0;
  while (b < function.blocks.length) {
    var block = function.blocks[b];
    var i = 0;
    while (i < block.instructions.length) {
      resolveValues(aliases, block.instructions[i].inputs);
      i++;
    }
    var end = block.end;
    if (end.value >= 0) end.value = resolveValue(aliases, end.value);
    if (end.kind == 1 || end.kind == 2)
      resolveValues(aliases, end.first.arguments);
    if (end.kind == 2) resolveValues(aliases, end.second.arguments);
    b++;
  }
}

void optimizeSsa(List<SsaFunction> program) {
  var i = 0;
  while (i < program.length) {
    var function = program[i];
    simplifyBooleanChecks(function);
    var state = sccpAnalyze(function);
    sccpRewrite(function, state);
    removeDeadValues(function);
    i++;
  }
}
