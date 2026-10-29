import 'ir.dart';
import 'machine.dart';
import 'source.dart';
import 'ssa.dart';

const int _unknownCall = 64;
const int _forbidden = ssaAllocate | ssaThrow | ssaGc | _unknownCall;

int _callRole(int function) {
  var flags = functions[function].contract?.flags ?? 0;
  var result = 0;
  if ((flags & contractAllocate) != 0) result |= ssaAllocate;
  if ((flags & contractMayGc) != 0) result |= ssaGc;
  return result;
}

void _checkBody(SourceProgram sources, int function, int effects) {
  var contract = functions[function].contract;
  if (contract == null || (contract.flags & contractNoGc) == 0) return;
  if ((effects & _forbidden) == 0) return;
  var reason = 'may create a Dart exception';
  if ((effects & ssaGc) != 0) reason = 'may enter GC';
  if ((effects & ssaAllocate) != 0) reason = 'may allocate managed memory';
  if ((effects & _unknownCall) != 0) reason = 'has an unknown indirect call';
  sourceError(
    sources,
    sources.tokens[contract.token],
    'NoGC function ' + functions[function].name + ' ' + reason,
  );
}

bool _ssaConstant(List<SsaInstruction?> definitions, int value, bool nonzero) {
  return switch (definitions[value]) {
    SsaInstruction(op: opInt, :var target) =>
      nonzero ? target != 0 : target >= 0,
    _ => false,
  };
}

bool _ssaNonnegative(List<SsaInstruction?> definitions, int value) {
  if (_ssaConstant(definitions, value, false)) return true;
  if (definitions[value] case SsaInstruction(
    op: opAnd,
    inputs: [var left, var right],
  ))
    return _ssaConstant(definitions, left, false) ||
        _ssaConstant(definitions, right, false);
  return false;
}

bool _builtinThrows(int target) {
  // A raw abort implementation does not discharge a Dart failure obligation.
  return target == bLateError ||
      target == bValueCast ||
      target == bValueCheck ||
      target == bListFilledTyped ||
      target == bValueBool ||
      target == bStringCodeUnit ||
      target == bStringSubstring ||
      target == bStringFromCodes ||
      target == bStringIndexOf ||
      target == bStringStartsWith ||
      target == bStringLastIndexOf ||
      target == bIntParse ||
      target >= bListGet && target <= bListFilled ||
      target == bListRemoveAt ||
      target == bListInsert ||
      target == bListSublist ||
      target >= bValueAdd && target <= bValueUshr ||
      target >= bValueLt && target <= bValueGe ||
      target == bValueToString;
}

List<int> checkNoGcSsa(
  List<SsaFunction> program,
  SourceProgram sources,
  List<int> checked,
) {
  var obligations = List<int>.filled(program.length, 0);
  var f = 0;
  while (f < program.length) {
    if (checked[f] == 0) {
      f++;
      continue;
    }
    var function = program[f];
    var definitions = List<SsaInstruction?>.filled(
      function.valueTypes.length,
      null,
    );
    for (var block in function.blocks) {
      for (var instruction in block.instructions) {
        if (instruction.value >= 0)
          definitions[instruction.value] = instruction;
      }
    }
    var effects = 0;
    for (var block in function.blocks) {
      for (var instruction in block.instructions) {
        var op = instruction.op;
        if (op == opCall) {
          effects |= _callRole(instruction.target);
        } else if (op == opGenericCall) {
          effects |= _callRole(genericCalls[instruction.target].function);
        } else if (op == opTypeCast) {
          effects |= ssaThrow;
        } else if (op == opBuiltin) {
          var target = instruction.target;
          if (_builtinThrows(target)) effects |= ssaThrow;
          if (target == bObjectNew ||
              target == bListNew ||
              target == bTypeInstantiate ||
              target == bListNewTyped ||
              target == bListFilledTyped ||
              target == bListFilled ||
              target == bListSublist ||
              target == bBoxInt ||
              target == bListFromData ||
              target == bObjectFromData) {
            effects |= ssaAllocate;
          }
          if (target >= bNativeLoad64) {
            effects |= instruction.effects & _forbidden;
            if ((instruction.effects & _forbidden) != 0)
              effects |= _unknownCall;
          }
        } else {
          var local = instruction.effects & _forbidden;
          if (((op == opDiv || op == opMod) &&
                  _ssaConstant(definitions, instruction.inputs[1], true)) ||
              ((op == opShl || op == opShr || op == opUshr) &&
                  _ssaNonnegative(definitions, instruction.inputs[1]))) {
            local &= ~ssaThrow;
          }
          effects |= local;
        }
      }
    }
    obligations[f] = effects;
    _checkBody(sources, f, effects);
    f++;
  }
  return obligations;
}

bool _machineConstant(
  List<MachineInstruction?> definitions,
  int value,
  bool nonzero,
) {
  return switch (definitions[value]) {
    MachineInstruction(op: mConstant, :var target) =>
      nonzero ? target != 0 : target >= 0,
    _ => false,
  };
}

bool _machineNonnegative(List<MachineInstruction?> definitions, int value) {
  if (_machineConstant(definitions, value, false)) return true;
  if (definitions[value] case MachineInstruction(
    op: mAnd,
    inputs: [var left, var right],
  ))
    return _machineConstant(definitions, left, false) ||
        _machineConstant(definitions, right, false);
  return false;
}

List<int> checkNoGcMachine(
  List<MachineFunction> program,
  List<int> obligations,
  SourceProgram sources,
  List<int> checked,
) {
  if (obligations.isEmpty) return const <int>[];
  var summaries = List<int>.filled(program.length, 0);
  var f = 0;
  while (f < program.length) {
    if (checked[f] == 0) {
      f++;
      continue;
    }
    var function = program[f];
    var definitions = List<MachineInstruction?>.filled(
      function.reps.length,
      null,
    );
    for (var block in function.blocks) {
      for (var instruction in block.instructions) {
        if (instruction.output >= 0)
          definitions[instruction.output] = instruction;
      }
    }
    var effects = obligations[f];
    for (var block in function.blocks) {
      for (var instruction in block.instructions) {
        var op = instruction.op;
        if (op == mCallIndirect) {
          effects |= _forbidden;
        } else if (op != mCall) {
          var local = instruction.effects;
          if (((op == mDiv || op == mMod) &&
                  _machineConstant(definitions, instruction.inputs[1], true)) ||
              ((op == mShl || op == mShr || op == mUshr) &&
                  _machineNonnegative(definitions, instruction.inputs[1]))) {
            local &= ~ssaThrow;
          }
          effects |= local;
        }
      }
    }
    summaries[f] = effects;
    f++;
  }
  var changed = true;
  while (changed) {
    changed = false;
    f = 0;
    while (f < program.length) {
      if (checked[f] == 0) {
        f++;
        continue;
      }
      var effects = summaries[f];
      for (var block in program[f].blocks) {
        for (var instruction in block.instructions) {
          if (instruction.op == mCall) {
            var callee = instruction.target;
            effects |= summaries[callee] | _callRole(callee);
          }
        }
      }
      if (effects != summaries[f]) {
        summaries[f] = effects;
        changed = true;
      }
      f++;
    }
  }
  f = 0;
  while (f < program.length) {
    if (checked[f] != 0) _checkBody(sources, f, summaries[f]);
    f++;
  }
  return summaries;
}
