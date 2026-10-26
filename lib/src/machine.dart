import 'host.dart';
import 'ir.dart';
import 'ssa.dart';

const int rI64 = 0;
const int rRef = 1;
const int rAddr = 2;
const int rI1 = 3;

const int mConstant = 1;
// Address kinds: 0 string, 1 global slot, 2 class descriptor.
const int mAddress = 2;
const int mLoad64 = 3;
const int mStore64 = 4;
const int mLoad8 = 5;
const int mStore8 = 6;
// Calls pass inputs in x0..x7 and return their result in x0.
const int mCall = 7;
const int mSyscall = 8;
const int mAdd = 9;
const int mSub = 10;
const int mMul = 11;
const int mDiv = 12;
const int mMod = 13;
const int mAnd = 14;
const int mOr = 15;
const int mXor = 16;
const int mShl = 17;
const int mShr = 18;
const int mUshr = 19;
const int mNeg = 20;
const int mBitNot = 21;
const int mNot = 22;
// extra stores the ARM64 condition code for a signed comparison.
const int mCompare = 23;

class RegisterAllocation {
  List<int> locations;
  int spillSlots;
  List<int> savedRegisters;

  RegisterAllocation(this.locations, this.spillSlots, this.savedRegisters);
}

class MachineFunction {
  List<int> arguments;
  List<int> reps;
  List<MachineBlock> blocks;
  int resultRep;
  RegisterAllocation allocation;

  MachineFunction(
    this.arguments,
    this.reps,
    this.blocks,
    this.resultRep,
    this.allocation,
  );
}

class MachineBlock {
  List<int> parameters;
  List<MachineInstruction> instructions;
  MachineTerminator end;

  MachineBlock(this.parameters, this.instructions, this.end);
}

class MachineInstruction {
  int op;
  int output;
  List<int> inputs;
  int target;
  int extra;
  int effects;

  MachineInstruction(
    this.op,
    this.output,
    this.inputs,
    this.target,
    this.extra,
    this.effects,
  );
}

class MachineTerminator {
  int kind;
  int value;
  MachineEdge first;
  MachineEdge second;

  MachineTerminator(this.kind, this.value, this.first, this.second);
}

class MachineEdge {
  int target;
  List<int> arguments;

  MachineEdge(this.target, this.arguments);
}

int machineRep(int type) {
  if (type == tPointer) return rAddr;
  if (type == tBool) return rI1;
  if (type == tString || type >= tList) return rRef;
  return rI64;
}

List<int> machineCopyValues(List<int> values) {
  List<int> result = <int>[];
  int i = 0;
  while (i < values.length) {
    result.add(values[i]);
    i = i + 1;
  }
  return result;
}

MachineEdge machineEdge(SsaEdge edge) {
  return MachineEdge(edge.target, machineCopyValues(edge.arguments));
}

int machineFunctionId(String name) {
  int i = 0;
  while (i < functions.length) {
    if (functions[i].name == name) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

int machineBuiltinFunction(int builtin) {
  if (builtin == bPrintString) return machineFunctionId('rtPrintString');
  if (builtin == bPrintInt) return machineFunctionId('rtPrintInt');
  if (builtin == bPrintBool) return machineFunctionId('rtPrintBool');
  if (builtin == bIntToString) return machineFunctionId('rtIntToString');
  if (builtin == bStringConcat) return machineFunctionId('rtStringConcat');
  if (builtin == bStringEqual) return machineFunctionId('rtStringEqual');
  if (builtin == bStringLength) return machineFunctionId('rtStringLength');
  if (builtin == bStringCodeUnit) return machineFunctionId('rtStringCodeUnit');
  if (builtin == bStringSubstring)
    return machineFunctionId('rtStringSubstring');
  if (builtin == bStringFromCodes)
    return machineFunctionId('rtStringFromCodes');
  if (builtin == bStringIndexOf) return machineFunctionId('rtStringIndexOf');
  if (builtin == bStringStartsWith)
    return machineFunctionId('rtStringStartsWith');
  if (builtin == bStringEndsWith) return machineFunctionId('rtStringEndsWith');
  if (builtin == bStringLastIndexOf)
    return machineFunctionId('rtStringLastIndexOf');
  if (builtin == bIntParse) return machineFunctionId('rtIntParse');
  if (builtin == bListNew) return machineFunctionId('rtListNew');
  if (builtin == bListLength) return machineFunctionId('rtListLength');
  if (builtin == bListGet) return machineFunctionId('rtListGet');
  if (builtin == bListSet) return machineFunctionId('rtListSet');
  if (builtin == bListAdd) return machineFunctionId('rtListAdd');
  if (builtin == bListRemoveLast) return machineFunctionId('rtListRemoveLast');
  if (builtin == bListClear) return machineFunctionId('rtListClear');
  if (builtin == bListFilled) return machineFunctionId('rtListFilled');
  if (builtin == bHostRead) return machineFunctionId('rtHostRead');
  if (builtin == bHostWrite) return machineFunctionId('rtHostWrite');
  if (builtin == bHostFinish) return machineFunctionId('rtHostFinish');
  if (builtin == bHostExit) return machineFunctionId('rtHostExit');
  if (builtin == bHostStdPath) return machineFunctionId('rtHostStdPath');
  if (builtin == bArguments) return machineFunctionId('rtArguments');
  if (builtin == bHostTarget) return machineFunctionId('rtHostTarget');
  if (builtin == bObjectNew) return machineFunctionId('rtObjectNew');
  if (builtin == bObjectGet) return machineFunctionId('rtObjectGet');
  if (builtin == bObjectSet) return machineFunctionId('rtObjectSet');
  print('Unknown native builtin: ' + builtin.toString());
  hostExit(1);
}

int machineArithmetic(int op) {
  if (op == opAdd) return mAdd;
  if (op == opSub) return mSub;
  if (op == opMul) return mMul;
  if (op == opDiv) return mDiv;
  if (op == opMod) return mMod;
  if (op == opAnd) return mAnd;
  if (op == opOr) return mOr;
  if (op == opXor) return mXor;
  if (op == opShl) return mShl;
  if (op == opShr) return mShr;
  if (op == opUshr) return mUshr;
  if (op == opNeg) return mNeg;
  if (op == opBitNot) return mBitNot;
  if (op == opNot) return mNot;
  return 0;
}

void machineSelectInstruction(
  SsaInstruction source,
  List<int> reps,
  List<MachineInstruction> instructions,
) {
  int op = source.op;
  int output = source.value;
  int target = source.target;
  int effects = source.effects;
  List<int> inputs = machineCopyValues(source.inputs);
  if (op == opInt) {
    instructions.add(
      MachineInstruction(mConstant, output, inputs, target, 0, effects),
    );
    return;
  }
  if (op == opString || op == opDescriptor) {
    int kind = 0;
    if (op == opDescriptor) kind = 2;
    instructions.add(
      MachineInstruction(mAddress, output, inputs, target, kind, effects),
    );
    return;
  }
  if (op == opLoadGlobal || op == opStoreGlobal) {
    int address = reps.length;
    reps.add(rAddr);
    instructions.add(
      MachineInstruction(mAddress, address, <int>[], target, 1, 0),
    );
    List<int> memory = <int>[address];
    if (op == opLoadGlobal) {
      instructions.add(
        MachineInstruction(mLoad64, output, memory, 0, 0, effects),
      );
    } else {
      memory.add(inputs[0]);
      instructions.add(MachineInstruction(mStore64, -1, memory, 0, 0, effects));
    }
    return;
  }
  if (op == opCall) {
    instructions.add(
      MachineInstruction(mCall, output, inputs, target, 0, effects),
    );
    return;
  }
  if (op == opBuiltin) {
    if (target == bNativeTarget) {
      instructions.add(
        MachineInstruction(mConstant, output, <int>[], targetOS, 0, effects),
      );
      return;
    }
    if (target == bNativeSyscall) {
      instructions.add(
        MachineInstruction(mSyscall, output, inputs, 0, 0, effects),
      );
      return;
    }
    if (target == bNativeLoad64 || target == bNativeLoad8) {
      int load = mLoad64;
      if (target == bNativeLoad8) load = mLoad8;
      instructions.add(MachineInstruction(load, output, inputs, 0, 0, effects));
      return;
    }
    if (target == bNativeStore64 || target == bNativeStore8) {
      int store = mStore64;
      if (target == bNativeStore8) store = mStore8;
      instructions.add(MachineInstruction(store, -1, inputs, 0, 0, effects));
      if (output >= 0) {
        instructions.add(
          MachineInstruction(mConstant, output, <int>[], 0, 0, 0),
        );
      }
      return;
    }
    instructions.add(
      MachineInstruction(
        mCall,
        output,
        inputs,
        machineBuiltinFunction(target),
        0,
        effects,
      ),
    );
    return;
  }
  if (op >= opEq && op <= opGe) {
    int condition = 0;
    if (op == opNe) condition = 1;
    if (op == opLt) condition = 11;
    if (op == opLe) condition = 13;
    if (op == opGt) condition = 12;
    if (op == opGe) condition = 10;
    instructions.add(
      MachineInstruction(mCompare, output, inputs, 0, condition, effects),
    );
    return;
  }
  int arithmetic = machineArithmetic(op);
  if (arithmetic != 0) {
    instructions.add(
      MachineInstruction(arithmetic, output, inputs, 0, 0, effects),
    );
    return;
  }
  print('Unsupported SSA operation: ' + op.toString());
  hostExit(1);
}

List<MachineFunction> selectMachine(List<SsaFunction> source) {
  List<MachineFunction> result = <MachineFunction>[];
  int f = 0;
  while (f < source.length) {
    SsaFunction function = source[f];
    List<int> reps = <int>[];
    int i = 0;
    while (i < function.valueTypes.length) {
      reps.add(machineRep(function.valueTypes[i]));
      i = i + 1;
    }
    List<MachineBlock> blocks = <MachineBlock>[];
    int b = 0;
    while (b < function.blocks.length) {
      SsaBlock block = function.blocks[b];
      List<MachineInstruction> instructions = <MachineInstruction>[];
      i = 0;
      while (i < block.instructions.length) {
        machineSelectInstruction(block.instructions[i], reps, instructions);
        i = i + 1;
      }
      SsaTerminator end = block.end;
      blocks.add(
        MachineBlock(
          machineCopyValues(block.parameters),
          instructions,
          MachineTerminator(
            end.kind,
            end.value,
            machineEdge(end.first),
            machineEdge(end.second),
          ),
        ),
      );
      b = b + 1;
    }
    result.add(
      MachineFunction(
        machineCopyValues(function.arguments),
        reps,
        blocks,
        machineRep(function.result),
        RegisterAllocation(<int>[], 0, <int>[]),
      ),
    );
    f = f + 1;
  }
  return result;
}
