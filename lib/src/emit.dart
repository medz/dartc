import 'arm64.dart';
import 'host.dart';
import 'ir.dart';
import 'machine.dart';

List<int> emitBranchSites = <int>[];
List<int> emitBranchTargets = <int>[];

void emitEdge(MachineEdge edge, MachineFunction function) {
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
  emitBranchSites.add(machineCode.length);
  emitBranchTargets.add(edge.target);
  machineCode.add(0x14000000);
}

void emitInstruction(MachineInstruction instruction, MachineFunction function) {
  int op = instruction.op;
  int output = instruction.output;
  List<int> inputs = instruction.inputs;
  int result = 0;
  if (imageKind != 0 && op == mAddress) {
    print('Library functions cannot use globals, strings, or managed objects.');
    hostExit(1);
  }
  if (op == mConstant) {
    result = emitDestination(function, output);
    armConstant(result, instruction.target);
  } else if (op == mAddress) {
    armAddress(instruction.extra, instruction.target);
  } else if (op == mLoad64 || op == mLoad8) {
    int address = emitOperand(function, inputs[0], 0);
    result = emitDestination(function, output);
    if (op == mLoad64)
      machineCode.add(0xf9400000 | (address << 5) | result);
    else
      machineCode.add(0x39400000 | (address << 5) | result);
  } else if (op == mStore64 || op == mStore8) {
    int address = emitOperand(function, inputs[0], 0);
    int value = emitOperand(function, inputs[1], 1);
    if (op == mStore64)
      machineCode.add(0xf9000000 | (address << 5) | value);
    else
      machineCode.add(0x39000000 | (address << 5) | value);
  } else if (op == mCall) {
    int outgoing = 0;
    if (inputs.length > 8) outgoing = alignFrame((inputs.length - 8) * 8);
    int remaining = outgoing;
    while (remaining >= 4096) {
      machineCode.add(0xd14007ff);
      remaining = remaining - 4096;
    }
    if (remaining != 0) machineCode.add(0xd10003ff | (remaining << 10));
    int argument = 8;
    while (argument < inputs.length) {
      int value = emitOperand(function, inputs[argument], 0);
      int offset = (argument - 8) * 8;
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
    argument = 0;
    while (argument < inputs.length && argument < 8) {
      emitLoad(function, inputs[argument], argument);
      argument = argument + 1;
    }
    armCall(instruction.target);
    remaining = outgoing;
    while (remaining >= 4096) {
      machineCode.add(0x914007ff);
      remaining = remaining - 4096;
    }
    if (remaining != 0) machineCode.add(0x910003ff | (remaining << 10));
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
    if (op == mShl) machineCode.add(0x9ac02000 | registers);
    if (op == mShr) machineCode.add(0x9ac02800 | registers);
    if (op == mUshr) machineCode.add(0x9ac02400 | registers);
    if (op == mCompare) {
      machineCode.add(0xeb00001f | (right << 16) | (left << 5));
      machineCode.add(0x9a9f07e0 | ((instruction.extra ^ 1) << 12) | result);
    }
  }
  if (output >= 0) emitStore(function, output, result);
}

void emitFunction(MachineFunction function) {
  machineCode.add(0xa9bf7bfd);
  machineCode.add(0x910003fd);
  int frame = alignFrame(
    (function.allocation.spillSlots +
            function.allocation.savedRegisters.length) *
        8,
  );
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
  List<int> offsets = <int>[];
  emitBranchSites = <int>[];
  emitBranchTargets = <int>[];
  int block = 0;
  while (block < function.blocks.length) {
    offsets.add(machineCode.length);
    MachineBlock current = function.blocks[block];
    int instruction = 0;
    while (instruction < current.instructions.length) {
      emitInstruction(current.instructions[instruction], function);
      instruction = instruction + 1;
    }
    MachineTerminator end = current.end;
    if (end.kind == 1) {
      emitEdge(end.first, function);
    } else if (end.kind == 2) {
      emitLoad(function, end.value, 0);
      int condition = machineCode.length;
      machineCode.add(0);
      emitEdge(end.first, function);
      machineCode[condition] =
          0xb4000000 | (((machineCode.length - condition) & 0x7ffff) << 5);
      emitEdge(end.second, function);
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
}

int alignFrame(int size) {
  return ((size + 15) ~/ 16) * 16;
}

void generateCode(List<MachineFunction> program) {
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
  if (imageKind == 0) {
    int main = armFunctionId('main');
    if (functions[main].parameters == 0) {
      armCall(0);
    } else {
      if (targetOS == 1) {
        machineCode.add(0xf94003e0);
        machineCode.add(0x910023e1);
      }
      armPush(0);
      armPush(1);
      armCall(0);
      armPop(1);
      armPop(0);
      armCall(armFunctionId('rtArguments'));
    }
    armCall(main);
    armConstant(0, 0);
    if (targetOS == 1) {
      armConstant(8, 93);
      machineCode.add(0xd4000001);
    } else {
      armConstant(16, 1);
      machineCode.add(0xd4001001);
    }
  }
  int function = 0;
  if (imageKind != 0) function = 1;
  while (function < program.length) {
    if (program[function].reachable) {
      armFunctionOffsets[function] = machineCode.length;
      emitFunction(program[function]);
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
