const int rI64 = 0;
const int rRef = 1;
const int rAddr = 2;
const int rI1 = 3;
const int rTagged = 4;
const int rF64Bits = 5;

const int mConstant = 1;
// Address kinds: 0 string, 1 global, 2 class descriptor, 3 metadata, 4 TypeRef,
// 5 constant data, 6 callable object.
const int mAddress = 2;
const int mLoad64 = 3;
const int mStore64 = 4;
const int mLoad8 = 5;
const int mStore8 = 6;
// Calls carry ordered arguments. The target owns registers, stack arguments
// and the result register.
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
// extra stores a signed comparison: equal, not-equal, less, less-or-equal,
// greater, greater-or-equal (0..5).
const int mCompare = 23;
const int mLoad16 = 24;
const int mStore16 = 25;
const int mMove = 26;
const int mCallIndirect = 27;
const int mShlImmediate = 28;
const int mShrImmediate = 29;
const int mUshrImmediate = 30;
const int mFramePointer = 31;
// The internal ABI transports binary64 bits in general registers. Allocation
// may keep double values in floating registers between calls.
const int mFloat64Add = 32;
const int mFloat64Sub = 33;
const int mFloat64Mul = 34;
const int mFloat64Div = 35;
const int mFloat64Compare = 36;
const int mFloat64FromInt = 37;
const int mFloat64ToInt = 38;
const int mFloat64Neg = 39;
const int mExit = 40;
const int mCaptureContext = 41;
const int mResumeContext = 42;

bool machineClobbersCallerSaved(int op) =>
    op == mCall ||
    op == mCallIndirect ||
    op == mSyscall ||
    op == mCaptureContext ||
    op == mResumeContext;

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
  RegisterAllocation allocation;
  bool reachable;

  MachineFunction(
    this.arguments,
    this.reps,
    this.blocks,
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
