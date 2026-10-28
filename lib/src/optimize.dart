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
  final key = source * 2 + which;
  if (state.edges[key] == 0) {
    state.edges[key] = 1;
    state.blocks[edge.target] = 1;
    state.changed = true;
  }
  final parameters = function.blocks[edge.target].parameters;
  var i = 0;
  while (i < parameters.length) {
    final input = edge.arguments[i];
    sccpMeet(state, parameters[i], state.kinds[input], state.constants[input]);
    i++;
  }
}

bool sccpArithmetic(int op) {
  return op >= opAdd && op <= opGe || op == opNot;
}

int sccpCalculate(int op, int left, int right) => switch (op) {
  opAdd => left + right,
  opSub => left - right,
  opMul => left * right,
  opDiv => left ~/ right,
  opMod => left % right,
  opNeg => -left,
  opAnd => left & right,
  opOr => left | right,
  opXor => left ^ right,
  opShl => left << right,
  opShr => left >> right,
  opUshr => left >>> right,
  opBitNot => ~left,
  opEq => left == right ? 1 : 0,
  opNe => left != right ? 1 : 0,
  opLt => left < right ? 1 : 0,
  opLe => left <= right ? 1 : 0,
  opGt => left > right ? 1 : 0,
  opGe => left >= right ? 1 : 0,
  _ => left == 0 ? 1 : 0,
};

void sccpInstruction(
  SccpState state,
  SsaFunction function,
  SsaInstruction instruction,
) {
  final value = instruction.value;
  if (value < 0 || state.kinds[value] == 2) return;
  final type = function.valueTypes[value];
  if (type != tInt && type != tBool) {
    sccpMeet(state, value, 2, 0);
    return;
  }
  final op = instruction.op;
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
    final inputKind = state.kinds[instruction.inputs[i]];
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
  final left = state.constants[instruction.inputs[0]];
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
  final state = SccpState(
    List<int>.filled(function.valueTypes.length, 0),
    List<int>.filled(function.valueTypes.length, 0),
    List<int>.filled(function.blocks.length, 0),
    List<int>.filled(function.blocks.length * 2, 0),
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
        final block = function.blocks[b];
        i = 0;
        while (i < block.instructions.length) {
          sccpInstruction(state, function, block.instructions[i]);
          i++;
        }
        final end = block.end;
        if (end.kind == 1) {
          sccpEdge(state, function, b, 0, end.first);
        } else if (end.kind == 2) {
          final kind = state.kinds[end.value];
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
  final mapping = List<int>.filled(function.blocks.length, -1);
  final List<SsaBlock> blocks = <SsaBlock>[];
  var b = 0;
  while (b < function.blocks.length) {
    if (state.blocks[b] == 1) {
      mapping[b] = blocks.length;
      final block = function.blocks[b];
      var i = 0;
      while (i < block.instructions.length) {
        final instruction = block.instructions[i];
        if (instruction.value >= 0 && state.kinds[instruction.value] == 1) {
          instruction.op = opInt;
          instruction.target = state.constants[instruction.value];
          instruction.inputs = <int>[];
          instruction.effects = 0;
        }
        i++;
      }
      final end = block.end;
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
    final end = blocks[b].end;
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
  final parameters = function.blocks[edge.target].parameters;
  var i = 0;
  while (i < edge.arguments.length) {
    final value = parameters[i];
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
    final next = aliases[value];
    aliases[value] = result;
    value = next;
  }
  return result;
}

List<int> simplifyBlockParameters(
  SsaFunction function,
  List<List<int>> dependencies,
) {
  final List<int> aliases = <int>[];
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
      final parameters = function.blocks[b].parameters;
      i = 0;
      while (i < parameters.length) {
        final parameter = parameters[i];
        if (aliases[parameter] == parameter) {
          final inputs = dependencies[parameter];
          var candidate = -1;
          var n = 0;
          while (n < inputs.length) {
            final input = resolveValue(aliases, inputs[n]);
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
  final parameters = function.blocks[edge.target].parameters;
  final List<int> kept = <int>[];
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
  final List<int> roots = <int>[];
  final List<List<int>> dependencies = <List<int>>[];
  final List<int> empty = <int>[];
  var i = 0;
  while (i < function.valueTypes.length) {
    dependencies.add(empty);
    i++;
  }
  var b = 0;
  while (b < function.blocks.length) {
    final block = function.blocks[b];
    i = 0;
    while (i < block.instructions.length) {
      final instruction = block.instructions[i];
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
    final end = block.end;
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
  final aliases = simplifyBlockParameters(function, dependencies);
  final live = List<int>.filled(function.valueTypes.length, 0);
  final List<int> work = <int>[];
  i = 0;
  while (i < roots.length) {
    markLiveValue(live, work, resolveValue(aliases, roots[i]));
    i++;
  }
  i = 0;
  while (i < work.length) {
    final inputs = dependencies[work[i]];
    var n = 0;
    while (n < inputs.length) {
      markLiveValue(live, work, resolveValue(aliases, inputs[n]));
      n++;
    }
    i++;
  }
  b = 0;
  while (b < function.blocks.length) {
    final end = function.blocks[b].end;
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
    final block = function.blocks[b];
    final List<SsaInstruction> kept = <SsaInstruction>[];
    i = 0;
    while (i < block.instructions.length) {
      final instruction = block.instructions[i];
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
    final List<int> parameters = <int>[];
    final List<int> localSlots = <int>[];
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
    final instructions = function.blocks[b].instructions;
    var i = 0;
    while (i < instructions.length) {
      final instruction = instructions[i];
      if (instruction.op == opBuiltin &&
          instruction.target == bBoxBool &&
          instruction.effects == 0 &&
          instruction.value >= 0 &&
          function.valueTypes[instruction.inputs[0]] == tBool) {
        if (boxes.isEmpty)
          boxes = List<int>.filled(function.valueTypes.length, -1);
        boxes[instruction.value] = instruction.inputs[0];
      }
      i++;
    }
    b++;
  }
  if (boxes.isEmpty) return;
  final aliases = <int>[];
  b = 0;
  while (b < function.blocks.length) {
    final instructions = function.blocks[b].instructions;
    var kept = 0;
    var i = 0;
    while (i < instructions.length) {
      final instruction = instructions[i];
      final check =
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
    final block = function.blocks[b];
    var i = 0;
    while (i < block.instructions.length) {
      resolveValues(aliases, block.instructions[i].inputs);
      i++;
    }
    final end = block.end;
    if (end.value >= 0) end.value = resolveValue(aliases, end.value);
    if (end.kind == 1 || end.kind == 2)
      resolveValues(aliases, end.first.arguments);
    if (end.kind == 2) resolveValues(aliases, end.second.arguments);
    b++;
  }
}

void removeInitialZeroStores(SsaFunction function) {
  final knownZero = List<bool>.filled(globalNames.length, true);
  final zeroValues = List<bool>.filled(function.valueTypes.length, false);
  var entry = function.blocks[0];
  // ssaBuildFunction starts with an empty argument-transfer block.
  if (entry.instructions.isEmpty &&
      entry.end.kind == 1 &&
      entry.end.first.arguments.isEmpty)
    entry = function.blocks[entry.end.first.target];
  final instructions = entry.instructions;
  var kept = 0;
  var i = 0;
  while (i < instructions.length) {
    final instruction = instructions[i];
    final op = instruction.op;
    var remove = false;
    if (op == opStoreGlobal) {
      final zero = zeroValues[instruction.inputs[0]];
      remove = zero && knownZero[instruction.target];
      knownZero[instruction.target] = zero;
    } else {
      // Unknown operations cannot preserve the loader's initial BSS facts.
      final pure =
          op == opInt ||
          op == opString ||
          op == opDescriptor ||
          op == opMetadataAddress ||
          op == opConstantData ||
          op >= opAdd && op <= opGe ||
          op == opNot ||
          op == opBuiltin &&
              (instruction.target == bBoxRef || instruction.target == bBoxBool);
      if (instruction.effects != 0 || !pure) break;
      if (op == opInt && instruction.value >= 0 && instruction.target == 0)
        zeroValues[instruction.value] = true;
    }
    if (!remove) {
      instructions[kept] = instruction;
      kept++;
    }
    i++;
  }
  while (i < instructions.length) {
    instructions[kept] = instructions[i];
    kept++;
    i++;
  }
  while (instructions.length > kept) instructions.removeLast();
}

void optimizeSsa(List<SsaFunction> program) {
  var i = 0;
  while (i < program.length) {
    final function = program[i];
    simplifyBooleanChecks(function);
    final state = sccpAnalyze(function);
    sccpRewrite(function, state);
    if (imageKind == 0 && i == 0) removeInitialZeroStores(function);
    removeDeadValues(function);
    i++;
  }
}
