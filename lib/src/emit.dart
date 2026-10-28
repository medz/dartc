import 'arm64.dart';
import 'abi.dart';
import 'frame.dart';
import 'host.dart';
import 'ir.dart';
import 'layout.dart';
import 'machine.dart';
import 'root_map.dart';
import 'types.dart';

List<int> emitBranchSites = <int>[];
List<int> emitBranchTargets = <int>[];

// x0 holds the status. An unexpected kernel return traps instead of falling
// through a call whose checked result is Never.
void emitExit() {
  if (targetOS == 1) {
    armConstant(8, 94); // Linux exit_group.
    machineCode.add(0xd4000001);
  } else {
    armConstant(16, 1); // Darwin exit.
    machineCode.add(0xd4001001);
  }
  machineCode.add(0xd4200000); // brk #0
}

void emitEdge(MachineEdge edge, MachineFunction function, int fallthrough) {
  List<int> parameters = function.blocks[edge.target].parameters;
  List<int> locations = function.allocation.locations;
  int i = 0;
  while (i < edge.arguments.length) {
    if (locations[edge.arguments[i]] != locations[parameters[i]]) {
      int register = emitOperand(function, edge.arguments[i], 0);
      armPush(register);
    }
    i = i + 1;
  }
  while (i > 0) {
    i = i - 1;
    if (locations[edge.arguments[i]] != locations[parameters[i]]) {
      int register = emitDestination(function, parameters[i]);
      armPop(register);
      emitStore(function, parameters[i], register);
    }
  }
  if (edge.target != fallthrough) {
    emitBranchSites.add(machineCode.length);
    emitBranchTargets.add(edge.target);
    machineCode.add(0x14000000);
  }
}

void emitInstruction(
  MachineInstruction instruction,
  MachineFunction function,
  CallRootMap? roots,
  EmittedHandler? handler,
) {
  final MachineInstruction(:op, :output, :inputs) = instruction;
  int result = 0;
  if (imageKind != ImageKind.executable && op == mAddress) {
    print('Library functions cannot use globals, strings, or managed objects.');
    hostExit(1);
  }
  if (op == mConstant) {
    result = emitDestination(function, output);
    armConstant(result, instruction.target);
  } else if (op == mMove) {
    result = emitOperand(function, inputs[0], 0);
  } else if (op >= mFloat64Add && op <= mFloat64Neg) {
    final left = emitOperand(function, inputs[0], 0);
    result = emitDestination(function, output);
    if (op == mFloat64FromInt) {
      machineCode.add(0x9e620000 | (left << 5)); // scvtf d0, xN
    } else {
      machineCode.add(0x9e670000 | (left << 5)); // fmov d0, xN
    }
    if (op == mFloat64ToInt) {
      machineCode.add(0x9e780000 | result); // fcvtzs xN, d0
    } else if (op == mFloat64Neg) {
      machineCode.add(0x1e614000); // fneg d0, d0
      machineCode.add(0x9e660000 | result);
    } else if (op == mFloat64FromInt) {
      machineCode.add(0x9e660000 | result); // fmov xN, d0
    } else {
      final right = emitOperand(function, inputs[1], 1);
      machineCode.add(0x9e670001 | (right << 5)); // fmov d1, xN
      if (op == mFloat64Compare) {
        machineCode.add(0x1e612000); // fcmp d0, d1
        machineCode.add(0x9a9f57e9); // cset x9, mi
        machineCode.add(0x9a9fd7e0 | result); // cset xN, gt
        machineCode.add(0xcb090000 | (result << 5) | result);
        machineCode.add(0x9a9f77e9); // cset x9, vs
        machineCode.add(0xaa090400 | (result << 5) | result);
      } else {
        var encoding = 0x1e612800;
        if (op == mFloat64Sub) encoding = 0x1e613800;
        if (op == mFloat64Mul) encoding = 0x1e610800;
        if (op == mFloat64Div) encoding = 0x1e611800;
        machineCode.add(encoding);
        machineCode.add(0x9e660000 | result);
      }
    }
  } else if (op == mFramePointer) {
    result = emitDestination(function, output);
    armMove(result, 29);
  } else if (op == mCaptureContext) {
    emitLoad(function, inputs[0], 9);
    machineCode.add(0xf900013d); // str x29, [x9]
    machineCode.add(0x910003ea); // mov x10, sp
    machineCode.add(0xf900052a); // str x10, [x9, #8]
    machineCode.add(0x1000000a); // adr x10, .
    machineCode.add(0xf900092a); // str x10, [x9, #16]
    for (var register = 19; register <= 27; register++)
      machineCode.add(0xf9000120 | ((register - 16) << 10) | register);
    armConstant(0, 0);
  } else if (op == mResumeContext) {
    emitLoad(function, inputs[0], 9);
    machineCode.add(0xf940013d); // ldr x29, [x9]
    machineCode.add(0xf940052a); // ldr x10, [x9, #8]
    machineCode.add(0xf9400930); // ldr x16, [x9, #16]
    for (var register = 19; register <= 27; register++)
      machineCode.add(0xf9400120 | ((register - 16) << 10) | register);
    machineCode.add(0x9100015f); // mov sp, x10
    machineCode.add(0xd61f0200); // br x16
    return;
  } else if (op == mAddress) {
    armAddress(instruction.extra, instruction.target);
  } else if (op == mLoad64 || op == mLoad8 || op == mLoad16) {
    int address = emitOperand(function, inputs[0], 0);
    result = emitDestination(function, output);
    if (op == mLoad64)
      machineCode.add(0xf9400000 | (address << 5) | result);
    else if (op == mLoad16)
      machineCode.add(0x79400000 | (address << 5) | result);
    else
      machineCode.add(0x39400000 | (address << 5) | result);
  } else if (op == mStore64 || op == mStore8 || op == mStore16) {
    int address = emitOperand(function, inputs[0], 0);
    int value = emitOperand(function, inputs[1], 1);
    if (op == mStore64)
      machineCode.add(0xf9000000 | (address << 5) | value);
    else if (op == mStore16)
      machineCode.add(0x79000000 | (address << 5) | value);
    else
      machineCode.add(0x39000000 | (address << 5) | value);
  } else if (op == mCall || op == mCallIndirect) {
    final vector = op == mCallIndirect && instruction.extra == 1;
    var first = 0;
    if (op == mCallIndirect) first = 1;
    if (vector) first = 3;
    var count = inputs.length - first;
    int outgoing = 0;
    if (vector)
      outgoing = alignFrame(count * 8);
    else if (count > 8)
      outgoing = alignFrame((count - 8) * 8);
    int remaining = outgoing;
    while (remaining >= 4096) {
      machineCode.add(0xd14007ff);
      remaining = remaining - 4096;
    }
    if (remaining != 0) machineCode.add(0xd10003ff | (remaining << 10));
    int argument = vector ? 0 : 8;
    while (argument < count) {
      int value = emitOperand(function, inputs[first + argument], 0);
      int offset = (vector ? argument : argument - 8) * 8;
      if (offset <= 32760) {
        machineCode.add(0xf90003e0 | ((offset ~/ 8) << 10) | value);
      } else {
        armConstant(10, offset);
        machineCode.add(0x910003e9);
        machineCode.add(0x8b0a0129);
        machineCode.add(0xf9000120 | value);
      }
      argument = argument + 1;
    }
    if (vector) {
      emitLoad(function, inputs[1], 0);
      emitLoad(function, inputs[2], 1);
      machineCode.add(0x910003e2); // mov x2, sp
      if (roots != null) {
        final frame = alignFrame(
          (function.allocation.spillSlots +
                  function.allocation.savedRegisters.length) *
              8,
        );
        for (var i = 0; i < count; i++) {
          roots.offsets.add(-frame - outgoing + i * 8);
          roots.kinds.add(storageTagged);
        }
      }
    } else {
      argument = 0;
      while (argument < count && argument < 8) {
        emitLoad(function, inputs[first + argument], argument);
        argument = argument + 1;
      }
    }
    if (op == mCallIndirect) {
      emitLoad(function, inputs[0], 16);
      machineCode.add(0xd63f0200);
    } else {
      armCall(instruction.target);
    }
    if (roots != null) {
      roots.returnOffset = machineCode.length * 4;
      emittedRootMaps.add(roots);
    }
    if (handler != null) {
      handler.returnOffset = machineCode.length * 4;
      emittedHandlers.add(handler);
    }
    remaining = outgoing;
    while (remaining >= 4096) {
      machineCode.add(0x914007ff);
      remaining = remaining - 4096;
    }
    if (remaining != 0) machineCode.add(0x910003ff | (remaining << 10));
  } else if (op == mExit) {
    emitLoad(function, inputs[0], 0);
    emitExit();
    return;
  } else if (op == mSyscall) {
    int numberRegister = 16;
    if (targetOS == 1) numberRegister = 8;
    emitLoad(function, inputs[0], numberRegister);
    int argument = 1;
    while (argument < inputs.length) {
      emitLoad(function, inputs[argument], argument - 1);
      argument = argument + 1;
    }
    if (targetOS == 1)
      machineCode.add(0xd4000001);
    else {
      machineCode.add(0xd4001001);
      machineCode.add(0xda803400);
    }
  } else if (op == mShlImmediate ||
      op == mShrImmediate ||
      op == mUshrImmediate) {
    int left = emitOperand(function, inputs[0], 0);
    result = emitDestination(function, output);
    int count = instruction.target;
    int opcode = 0xd340fc00 | (count << 16);
    if (op == mShlImmediate) {
      opcode = 0xd3400000 | (((64 - count) & 63) << 16) | ((63 - count) << 10);
    } else if (op == mShrImmediate) {
      opcode = 0x9340fc00 | (count << 16);
    }
    machineCode.add(opcode | (left << 5) | result);
  } else if (op == mShl || op == mShr || op == mUshr) {
    int left = emitOperand(function, inputs[0], 0);
    int right = emitOperand(function, inputs[1], 1);
    result = emitDestination(function, output);
    machineCode.add(0xf100001f | (right << 5));
    int valid = machineCode.length;
    machineCode.add(0);
    armConstant(0, 70);
    emitExit();
    machineCode[valid] = 0x5400000a | ((machineCode.length - valid) << 5);
    machineCode.add(0xf101001f | (right << 5));
    int limit = 31;
    if (op == mShr) {
      // x9 is reserved scratch; preserve the sign before output aliases left.
      machineCode.add(0x937ffc09 | (left << 5));
      limit = 9;
    }
    int registers = (right << 16) | (left << 5) | result;
    if (op == mShl) machineCode.add(0x9ac02000 | registers);
    if (op == mShr) machineCode.add(0x9ac02800 | registers);
    if (op == mUshr) machineCode.add(0x9ac02400 | registers);
    // CSEL retains the shifted value only when the count is below 64.
    machineCode.add(0x9a80b000 | (limit << 16) | (result << 5) | result);
  } else if (op == mNeg || op == mBitNot || op == mNot) {
    int value = emitOperand(function, inputs[0], 0);
    result = emitDestination(function, output);
    if (op == mNeg) machineCode.add(0xcb0003e0 | (value << 16) | result);
    if (op == mBitNot) machineCode.add(0xaa2003e0 | (value << 16) | result);
    if (op == mNot) {
      machineCode.add(0xf100001f | (value << 5));
      machineCode.add(0x9a9f17e0 | result);
    }
  } else if (op == mMod) {
    emitLoad(function, inputs[0], 0);
    emitLoad(function, inputs[1], 1);
    machineCode.add(0x9ac10c02);
    machineCode.add(0x9b018040);
    machineCode.add(0xf100001f);
    machineCode.add(0x540000aa);
    machineCode.add(0xf100003f);
    machineCode.add(0x5400004a);
    machineCode.add(0xcb0103e1);
    machineCode.add(0x8b010000);
  } else {
    int left = emitOperand(function, inputs[0], 0);
    int right = emitOperand(function, inputs[1], 1);
    result = emitDestination(function, output);
    int registers = (right << 16) | (left << 5) | result;
    if (op == mAdd) machineCode.add(0x8b000000 | registers);
    if (op == mSub) machineCode.add(0xcb000000 | registers);
    if (op == mMul) machineCode.add(0x9b007c00 | registers);
    if (op == mDiv) machineCode.add(0x9ac00c00 | registers);
    if (op == mAnd) machineCode.add(0x8a000000 | registers);
    if (op == mOr) machineCode.add(0xaa000000 | registers);
    if (op == mXor) machineCode.add(0xca000000 | registers);
    if (op == mCompare) {
      machineCode.add(0xeb00001f | (right << 16) | (left << 5));
      machineCode.add(0x9a9f07e0 | ((instruction.extra ^ 1) << 12) | result);
    }
  }
  if (output >= 0) emitStore(function, output, result);
}

List<int> emitUseCounts(MachineFunction function) {
  List<int> uses = <int>[];
  int value = 0;
  while (value < function.reps.length) {
    uses.add(0);
    value = value + 1;
  }
  int block = 0;
  while (block < function.blocks.length) {
    MachineBlock current = function.blocks[block];
    int instruction = 0;
    while (instruction < current.instructions.length) {
      List<int> inputs = current.instructions[instruction].inputs;
      int input = 0;
      while (input < inputs.length) {
        uses[inputs[input]] = uses[inputs[input]] + 1;
        input = input + 1;
      }
      instruction = instruction + 1;
    }
    MachineTerminator end = current.end;
    if (end.value >= 0) uses[end.value] = uses[end.value] + 1;
    int input = 0;
    while (input < end.first.arguments.length) {
      int value = end.first.arguments[input];
      uses[value] = uses[value] + 1;
      input = input + 1;
    }
    input = 0;
    while (input < end.second.arguments.length) {
      int value = end.second.arguments[input];
      uses[value] = uses[value] + 1;
      input = input + 1;
    }
    block = block + 1;
  }
  return uses;
}

void emitFunction(
  MachineFunction function,
  bool rootsEnabled,
  bool framesEnabled,
  int number,
) {
  List<CallRootMap> roots = const <CallRootMap>[];
  if (rootsEnabled) roots = buildCallRootMaps(function);
  var nextRoot = 0;
  final start = machineCode.length * 4;
  machineCode.add(0xa9bf7bfd);
  machineCode.add(0x910003fd);
  int frame = alignFrame(
    (function.allocation.spillSlots +
            function.allocation.savedRegisters.length) *
        8,
  );
  final frameBytes = frame;
  while (frame >= 4096) {
    machineCode.add(0xd14007ff);
    frame = frame - 4096;
  }
  if (frame != 0) machineCode.add(0xd10003ff | (frame << 10));
  int saved = 0;
  while (saved < function.allocation.savedRegisters.length) {
    armStoreLocal(
      function.allocation.spillSlots + saved,
      function.allocation.savedRegisters[saved],
    );
    saved = saved + 1;
  }
  int argument = 0;
  while (argument < function.arguments.length) {
    if (argument < 8) {
      emitStore(function, function.arguments[argument], argument);
    } else {
      int register = emitDestination(function, function.arguments[argument]);
      int offset = 16 + (argument - 8) * 8;
      if (offset <= 32760) {
        machineCode.add(0xf94003a0 | ((offset ~/ 8) << 10) | register);
      } else {
        armConstant(10, offset);
        machineCode.add(0x8b0a03a9);
        machineCode.add(0xf9400120 | register);
      }
      emitStore(function, function.arguments[argument], register);
    }
    argument = argument + 1;
  }
  List<int> uses = emitUseCounts(function);
  List<int> offsets = <int>[];
  emitBranchSites = <int>[];
  emitBranchTargets = <int>[];
  int block = 0;
  while (block < function.blocks.length) {
    offsets.add(machineCode.length);
    MachineBlock current = function.blocks[block];
    MachineTerminator end = current.end;
    int compareCondition = -1;
    EmittedHandler? handler;
    if (end.kind == 5 || end.kind == 6) handler = EmittedHandler();
    int instruction = 0;
    while (instruction < current.instructions.length) {
      MachineInstruction operation = current.instructions[instruction];
      if (instruction + 1 == current.instructions.length &&
          operation.op == mCompare &&
          operation.output >= 0 &&
          end.kind == 2 &&
          end.value == operation.output &&
          uses[operation.output] == 1) {
        int left = emitOperand(function, operation.inputs[0], 0);
        int right = emitOperand(function, operation.inputs[1], 1);
        machineCode.add(0xeb00001f | (right << 16) | (left << 5));
        compareCondition = operation.extra;
      } else {
        CallRootMap? callRoots;
        if (nextRoot < roots.length &&
            roots[nextRoot].block == block &&
            roots[nextRoot].instruction == instruction) {
          callRoots = roots[nextRoot];
          nextRoot++;
        }
        emitInstruction(
          operation,
          function,
          callRoots,
          instruction + 1 == current.instructions.length ? handler : null,
        );
      }
      instruction = instruction + 1;
    }
    if (end.kind == 1) {
      emitEdge(end.first, function, block + 1);
    } else if (end.kind == 2) {
      if (compareCondition < 0) emitLoad(function, end.value, 0);
      int condition = machineCode.length;
      machineCode.add(0);
      emitEdge(end.first, function, -1);
      int distance = (machineCode.length - condition) & 0x7ffff;
      if (compareCondition >= 0) {
        // The flag-consuming branch immediately follows CMP, before edge copies.
        machineCode[condition] =
            0x54000000 | (distance << 5) | (compareCondition ^ 1);
      } else {
        machineCode[condition] = 0xb4000000 | (distance << 5);
      }
      emitEdge(end.second, function, block + 1);
    } else if (end.kind == 5 || end.kind == 6) {
      if (end.kind == 5)
        emitEdge(end.first, function, -1);
      else
        machineCode.add(
          0xd4200000,
        ); // Never calls cannot fall into their handler.
      handler!.landingOffset = machineCode.length * 4;
      emitEdge(end.second, function, block + 1);
    } else if (end.kind == 4) {
      // A proven non-returning path must never fall into the next block.
      machineCode.add(0xd4200000); // brk #0
    } else {
      if (end.value >= 0)
        emitLoad(function, end.value, 0);
      else
        armConstant(0, 0);
      int restore = 0;
      while (restore < function.allocation.savedRegisters.length) {
        armLoadLocal(
          function.allocation.spillSlots + restore,
          function.allocation.savedRegisters[restore],
        );
        restore = restore + 1;
      }
      machineCode.add(0x910003bf);
      machineCode.add(0xa8c17bfd);
      machineCode.add(0xd65f03c0);
    }
    block = block + 1;
  }
  int branch = 0;
  while (branch < emitBranchSites.length) {
    int site = emitBranchSites[branch];
    int target = offsets[emitBranchTargets[branch]];
    machineCode[site] = 0x14000000 | ((target - site) & 0x3ffffff);
    branch = branch + 1;
  }
  if (framesEnabled) {
    var mask = 0;
    for (final register in function.allocation.savedRegisters)
      mask |= 1 << (register - 19);
    emittedFrames.add(
      EmittedFrame(
        start,
        machineCode.length * 4,
        frameBytes,
        -(function.allocation.spillSlots + 1) * 8,
        mask,
        number,
      ),
    );
  }
}

int alignFrame(int size) {
  return ((size + 15) ~/ 16) * 16;
}

int emitMetadataFeatures(List<MachineFunction> program) {
  var features = 0;
  var f = 0;
  while (f < program.length) {
    var function = program[f];
    if (!function.reachable) {
      f++;
      continue;
    }
    var b = 0;
    while (b < function.blocks.length) {
      final end = function.blocks[b].end;
      if (end.kind == 5 || end.kind == 6)
        features |= metadataFrames | metadataHandlers;
      var instructions = function.blocks[b].instructions;
      var i = 0;
      while (i < instructions.length) {
        var instruction = instructions[i];
        if (instruction.op == mAddress && instruction.extra == 3)
          features |= instruction.target;
        i++;
      }
      b++;
    }
    f++;
  }
  return features;
}

void emitRootBoundary(bool enabled) {
  if (!enabled) return;
  var boundary = CallRootMap(-1, -1, const <int>[], const <int>[]);
  boundary.boundary = true;
  boundary.returnOffset = machineCode.length * 4;
  emittedRootMaps.add(boundary);
}

void generateCode(List<MachineFunction> program) {
  final features = emitMetadataFeatures(program);
  final rootsEnabled = (features & metadataRoots) != 0;
  final framesEnabled = (features & (metadataFrames | metadataHandlers)) != 0;
  emittedRootMaps.clear();
  emittedFrames.clear();
  emittedHandlers.clear();
  machineCode = <int>[];
  addressSites = <int>[];
  addressKinds = <int>[];
  addressTargets = <int>[];
  armFunctionOffsets = <int>[];
  armCallSites = <int>[];
  armCallTargets = <int>[];
  int i = 0;
  while (i < program.length) {
    armFunctionOffsets.add(0);
    i = i + 1;
  }
  if (imageKind == ImageKind.executable) {
    int main = entryFunction;
    if (functions[main].parameters == 0) {
      armCall(0);
      emitRootBoundary(rootsEnabled);
    } else {
      if (targetOS == 1) {
        machineCode.add(0xf94003e0);
        machineCode.add(0x910023e1);
      }
      armPush(0);
      armPush(1);
      armCall(0);
      emitRootBoundary(rootsEnabled);
      armPop(1);
      armPop(0);
      armMove(9, 0);
      armAddress(4, listType(tString));
      armMove(2, 0);
      armMove(0, 9);
      armCall(runtimeFunction(bArguments, -1));
      emitRootBoundary(rootsEnabled);
    }
    armCall(main);
    emitRootBoundary(rootsEnabled);
    armConstant(0, 0);
    emitExit();
    if (framesEnabled)
      emittedFrames.add(EmittedFrame(0, machineCode.length * 4, -1, 0, 0, -1));
  }
  int function = 0;
  if (imageKind != ImageKind.executable) function = 1;
  while (function < program.length) {
    if (program[function].reachable) {
      armFunctionOffsets[function] = machineCode.length;
      emitFunction(program[function], rootsEnabled, framesEnabled, function);
    }
    function = function + 1;
  }
  int call = 0;
  while (call < armCallSites.length) {
    int site = armCallSites[call];
    int target = armFunctionOffsets[armCallTargets[call]];
    machineCode[site] = 0x94000000 | ((target - site) & 0x3ffffff);
    call = call + 1;
  }
}

int emitOperand(MachineFunction function, int value, int fallback) {
  int location = function.allocation.locations[value];
  if (location >= 0) return location;
  armLoadLocal(-location - 1, fallback);
  return fallback;
}

int emitDestination(MachineFunction function, int value) {
  if (value >= 0) {
    int location = function.allocation.locations[value];
    if (location >= 0) return location;
  }
  return 0;
}

void emitLoad(MachineFunction function, int value, int register) {
  int location = function.allocation.locations[value];
  if (location >= 0) {
    if (location != register) armMove(register, location);
  } else {
    armLoadLocal(-location - 1, register);
  }
}

void emitStore(MachineFunction function, int value, int register) {
  int location = function.allocation.locations[value];
  if (location >= 0) {
    if (location != register) armMove(location, register);
  } else {
    armStoreLocal(-location - 1, register);
  }
}
