import 'abi.dart';
import 'host.dart';
import 'ir.dart';
import 'types.dart';
import 'ssa.dart';

const int rI64 = 0;
const int rRef = 1;
const int rAddr = 2;
const int rI1 = 3;
const int rTagged = 4;

const int mConstant = 1;
// Address kinds: 0 string, 1 global, 2 class descriptor, 3 metadata, 4 TypeRef,
// 5 constant data, 6 callable object.
const int mAddress = 2;
const int mLoad64 = 3;
const int mStore64 = 4;
const int mLoad8 = 5;
const int mStore8 = 6;
// Calls pass the first eight inputs in x0..x7, the rest on the stack.
// Results return in x0.
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
const int mLoad16 = 24;
const int mStore16 = 25;
const int mMove = 26;
const int mCallIndirect = 27;
const int mShlImmediate = 28;
const int mShrImmediate = 29;
const int mUshrImmediate = 30;
const int mFramePointer = 31;

class RegisterAllocation {
  final List<int> locations;
  final int spillSlots;
  final List<int> savedRegisters;

  const RegisterAllocation(
    this.locations,
    this.spillSlots,
    this.savedRegisters,
  );
}

class MachineFunction {
  List<int> arguments;
  List<int> reps;
  List<MachineBlock> blocks;
  int resultRep;
  RegisterAllocation allocation;
  bool reachable;

  MachineFunction(
    this.arguments,
    this.reps,
    this.blocks,
    this.resultRep,
    this.allocation,
    this.reachable,
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
  if (typeIsTagged(type)) return rTagged;
  if (typeIsReference(type)) return rRef;
  return rI64;
}

MachineEdge machineEdge(SsaEdge edge) {
  return MachineEdge(edge.target, edge.arguments.sublist(0));
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
  List<int> types,
  List<int> reps,
  List<int> counts,
  List<MachineInstruction> instructions,
) {
  var SsaInstruction(:op, value: output, :target, :effects) = source;
  final List<int> inputs = source.inputs.sublist(0);
  if (op == opInt) {
    instructions.add(
      MachineInstruction(mConstant, output, inputs, target, 0, effects),
    );
    return;
  }
  if (op == opString ||
      op == opDescriptor ||
      op == opMetadataAddress ||
      op == opConstantData ||
      op == opFunctionReference ||
      op == opClosureDescriptor ||
      op == opCaptureCellDescriptor ||
      op == opTypeReference) {
    int kind = 0;
    if (op == opDescriptor) kind = 2;
    if (op == opMetadataAddress) kind = 3;
    if (op == opConstantData) kind = 5;
    if (op == opFunctionReference) kind = 6;
    if (op == opClosureDescriptor) kind = 7;
    if (op == opCaptureCellDescriptor) kind = 8;
    if (op == opTypeReference) kind = 9;
    instructions.add(
      MachineInstruction(mAddress, output, inputs, target, kind, effects),
    );
    return;
  }
  if (op == opLoadGlobal || op == opStoreGlobal) {
    final int address = reps.length;
    reps.add(rAddr);
    instructions.add(
      MachineInstruction(mAddress, address, <int>[], target, 1, 0),
    );
    final List<int> memory = <int>[address];
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
  if (op == opCall || op == opGenericCall) {
    if (op == opGenericCall) target = genericCalls[target].function;
    instructions.add(
      MachineInstruction(mCall, output, inputs, target, 0, effects),
    );
    return;
  }
  if (op == opTypeTest || op == opTypeCast) {
    if (op == opTypeTest || target != tInt && target != tBool) {
      final type = reps.length;
      reps.add(rAddr);
      instructions.add(
        MachineInstruction(mAddress, type, <int>[], target, 4, 0),
      );
      inputs.add(type);
    }
    var builtin = bValueIs;
    if (op == opTypeCast) builtin = bValueCast;
    instructions.add(
      MachineInstruction(
        mCall,
        output,
        inputs,
        runtimeFunction(builtin, target),
        0,
        effects,
      ),
    );
    return;
  }
  if (op == opBuiltin) {
    if (target == bBoxRef) {
      instructions.add(
        MachineInstruction(mMove, output, inputs, 0, 0, effects),
      );
      return;
    }
    if (target == bNativeCall1 ||
        target == bNativeCall0 ||
        target == bFunctionInvoke) {
      instructions.add(
        MachineInstruction(mCallIndirect, output, inputs, 0, 0, effects),
      );
      return;
    }
    if (target == bNativeTarget) {
      instructions.add(
        MachineInstruction(mConstant, output, <int>[], targetOS, 0, effects),
      );
      return;
    }
    if (target == bNativeFramePointer) {
      instructions.add(
        MachineInstruction(mFramePointer, output, inputs, 0, 0, effects),
      );
      return;
    }
    if (target == bNativeSyscall) {
      instructions.add(
        MachineInstruction(mSyscall, output, inputs, 0, 0, effects),
      );
      return;
    }
    if (target == bNativeLoad64 ||
        target == bNativeLoad8 ||
        target == bNativeLoad16) {
      int load = mLoad64;
      if (target == bNativeLoad8) load = mLoad8;
      if (target == bNativeLoad16) load = mLoad16;
      instructions.add(MachineInstruction(load, output, inputs, 0, 0, effects));
      return;
    }
    if (target == bNativeStore64 ||
        target == bNativeStore8 ||
        target == bNativeStore16) {
      int store = mStore64;
      if (target == bNativeStore8) store = mStore8;
      if (target == bNativeStore16) store = mStore16;
      instructions.add(MachineInstruction(store, -1, inputs, 0, 0, effects));
      if (output >= 0) {
        instructions.add(
          MachineInstruction(mConstant, output, <int>[], 0, 0, 0),
        );
      }
      return;
    }
    var typeId = -1;
    var castType = -1;
    if (target == bValueCast) {
      castType = source.resultType;
      if (castType != tInt && castType != tBool) typeId = castType;
    } else if (target == bListNew ||
        target == bListFilled ||
        target == bListGet ||
        target == bListRemoveLast ||
        target == bListRemoveAt) {
      typeId = source.resultType;
    } else if (target == bListAdd) {
      typeId = types[source.inputs[1]];
    } else if (target == bListSet || target == bListInsert) {
      typeId = types[source.inputs[2]];
    }
    if (typeId >= 0) {
      if (typeContainsParameters(typeId)) typeId = tDynamic;
      final type = reps.length;
      reps.add(rAddr);
      instructions.add(
        MachineInstruction(mAddress, type, <int>[], typeId, 4, 0),
      );
      inputs.add(type);
    }
    instructions.add(
      MachineInstruction(
        mCall,
        output,
        inputs,
        runtimeFunction(target, castType),
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
    var count = 0;
    if ((op == opShl || op == opShr || op == opUshr) &&
        counts[inputs[1]] >= 0) {
      count = counts[inputs[1]];
      if (op == opShl) arithmetic = mShlImmediate;
      if (op == opShr) arithmetic = mShrImmediate;
      if (op == opUshr) arithmetic = mUshrImmediate;
      inputs.removeLast();
      effects = 0;
    }
    instructions.add(
      MachineInstruction(arithmetic, output, inputs, count, 0, effects),
    );
    return;
  }
  print('Unsupported SSA operation: ' + op.toString());
  hostExit(1);
}

void machineRemoveUnusedConstants(List<MachineBlock> blocks, int count) {
  final used = List<bool>.filled(count, false);
  var b = 0;
  while (b < blocks.length) {
    final block = blocks[b];
    var i = 0;
    while (i < block.instructions.length) {
      final inputs = block.instructions[i].inputs;
      var n = 0;
      while (n < inputs.length) {
        used[inputs[n]] = true;
        n++;
      }
      i++;
    }
    final end = block.end;
    if (end.value >= 0) used[end.value] = true;
    i = 0;
    while (i < end.first.arguments.length) {
      used[end.first.arguments[i]] = true;
      i++;
    }
    i = 0;
    while (i < end.second.arguments.length) {
      used[end.second.arguments[i]] = true;
      i++;
    }
    b++;
  }
  b = 0;
  while (b < blocks.length) {
    final instructions = blocks[b].instructions;
    var i = 0;
    var kept = 0;
    while (i < instructions.length) {
      final instruction = instructions[i];
      if (instruction.op != mConstant ||
          instruction.effects != 0 ||
          instruction.output < 0 ||
          used[instruction.output]) {
        instructions[kept] = instruction;
        kept++;
      }
      i++;
    }
    while (instructions.length > kept) instructions.removeLast();
    b++;
  }
}

List<MachineFunction> selectMachine(
  List<SsaFunction> source,
  List<int> reachable,
) {
  final List<MachineFunction> result = <MachineFunction>[];
  int f = 0;
  while (f < source.length) {
    final SsaFunction function = source[f];
    if (reachable[f] == 0) {
      result.add(
        MachineFunction(
          <int>[],
          <int>[],
          <MachineBlock>[],
          machineRep(function.result),
          const RegisterAllocation(<int>[], 0, <int>[]),
          false,
        ),
      );
      f = f + 1;
      continue;
    }
    final List<int> reps = <int>[];
    int i = 0;
    while (i < function.valueTypes.length) {
      reps.add(machineRep(function.valueTypes[i]));
      i = i + 1;
    }
    final List<MachineBlock> blocks = <MachineBlock>[];
    final counts = List<int>.filled(function.valueTypes.length, -1);
    int b = 0;
    while (b < function.blocks.length) {
      final instructions = function.blocks[b].instructions;
      i = 0;
      while (i < instructions.length) {
        final instruction = instructions[i];
        if (instruction.op == opInt &&
            instruction.value >= 0 &&
            instruction.effects == 0 &&
            instruction.target >= 0 &&
            instruction.target <= 63) {
          counts[instruction.value] = instruction.target;
        }
        i++;
      }
      b++;
    }
    b = 0;
    while (b < function.blocks.length) {
      final SsaBlock block = function.blocks[b];
      final List<MachineInstruction> instructions = <MachineInstruction>[];
      i = 0;
      while (i < block.instructions.length) {
        machineSelectInstruction(
          block.instructions[i],
          function.valueTypes,
          reps,
          counts,
          instructions,
        );
        i = i + 1;
      }
      final SsaTerminator end = block.end;
      blocks.add(
        MachineBlock(
          block.parameters.sublist(0),
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
    machineRemoveUnusedConstants(blocks, reps.length);
    result.add(
      MachineFunction(
        function.arguments.sublist(0),
        reps,
        blocks,
        machineRep(function.result),
        const RegisterAllocation(<int>[], 0, <int>[]),
        true,
      ),
    );
    f = f + 1;
  }
  return result;
}
