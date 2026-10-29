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
  // 1 jump, 2 branch, 3 return, 4 unreachable, 5 invoke, 6 Never invoke.
  // Invokes use first for normal continuation and second for exception transfer.
  int kind;
  int value;
  SsaEdge first;
  SsaEdge second;

  SsaTerminator(this.kind, this.value, this.first, this.second);

  bool get hasFirst => kind == 1 || kind == 2 || kind == 5;
  bool get hasSecond => kind == 2 || kind == 5 || kind == 6;
}

Never ssaError(String message) {
  print('dartc SSA: ' + message);
  hostExit(1);
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

void resolveValues(List<int> aliases, List<int> values) {
  for (var i = 0; i < values.length; i++)
    values[i] = resolveValue(aliases, values[i]);
}

int ssaEffects(int op, int target) {
  if (op == opTypeCast) return ssaRead | ssaAllocate | ssaThrow | ssaGc;
  if (op == opLoadGlobal) return ssaRead;
  if (op == opStoreGlobal) return ssaWrite;
  if (op == opDiv || op == opMod || op == opShl || op == opShr || op == opUshr)
    return ssaThrow;
  if (op == opCall || op == opGenericCall) {
    return ssaRead | ssaWrite | ssaAllocate | ssaThrow | ssaGc | ssaNative;
  }
  if (op == opBuiltin) {
    if (target >= bNativeFloat64Add && target <= bNativeValueFromBits) return 0;
    if (target == bFunctionEntry || target == bFunctionType)
      return ssaRead | ssaNative;
    if (target == bValueIdentical || target == bObjectClassId) return ssaRead;
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
    if (target == bNativeSyscall ||
        target == bNativeExit ||
        target == bNativeCaptureContext ||
        target == bNativeResumeContext)
      return ssaRead | ssaWrite | ssaNative;
    return ssaRead | ssaWrite | ssaAllocate | ssaThrow | ssaGc | ssaNative;
  }
  return 0;
}
