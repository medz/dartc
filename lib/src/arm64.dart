import 'host.dart';
import 'ir.dart';

List<int> machineCode = <int>[];
List<int> addressSites = <int>[];
List<int> addressKinds = <int>[];
List<int> addressTargets = <int>[];
int entryOffset = 0;

List<int> armIrOffsets = <int>[];
List<int> armFunctionOffsets = <int>[];
List<int> armCallSites = <int>[];
List<int> armCallTargets = <int>[];
List<int> armBranchSites = <int>[];
List<int> armBranchTargets = <int>[];
List<int> armBranchKinds = <int>[];

void armMove(int target, int source) {
  machineCode.add(0xaa0003e0 | (source << 16) | target);
}

void armConstant(int register, int value) {
  machineCode.add(0xd2800000 | ((value & 65535) << 5) | register);
  var shift = 16;
  while (shift < 64) {
    var part = (value >>> shift) & 65535;
    if (part != 0) {
      machineCode.add(
        0xf2800000 | ((shift ~/ 16) << 21) | (part << 5) | register,
      );
    }
    shift = shift + 16;
  }
}

// One word occupies a 16-byte evaluation slot, preserving platform SP alignment.
void armPush(int register) {
  machineCode.add(0xf81f0fe0 | register);
}

void armPop(int register) {
  machineCode.add(0xf84107e0 | register);
}

void armAddress(int kind, int target) {
  addressSites.add(machineCode.length);
  addressKinds.add(kind);
  addressTargets.add(target);
  machineCode.add(0x90000000);
  machineCode.add(0x91000000);
}

void armLoadLocal(int slot, int register) {
  var offset = (slot + 1) * 8;
  if (offset <= 256) {
    machineCode.add(0xf84003a0 | (((-offset) & 511) << 12) | register);
    return;
  }
  armConstant(10, offset);
  machineCode.add(0xcb0a03a9);
  machineCode.add(0xf9400120 | register);
}

void armStoreLocal(int slot, int register) {
  var offset = (slot + 1) * 8;
  if (offset <= 256) {
    machineCode.add(0xf80003a0 | (((-offset) & 511) << 12) | register);
    return;
  }
  armConstant(10, offset);
  machineCode.add(0xcb0a03a9);
  machineCode.add(0xf9000120 | register);
}

int armFunctionId(String name) {
  var i = 0;
  while (i < functionNames.length) {
    if (functionNames[i] == name) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

int armBuiltinFunction(int builtin) {
  if (builtin == bPrintString) return armFunctionId('rtPrintString');
  if (builtin == bPrintInt) return armFunctionId('rtPrintInt');
  if (builtin == bPrintBool) return armFunctionId('rtPrintBool');
  if (builtin == bIntToString) return armFunctionId('rtIntToString');
  if (builtin == bStringConcat) return armFunctionId('rtStringConcat');
  if (builtin == bStringEqual) return armFunctionId('rtStringEqual');
  if (builtin == bStringLength) return armFunctionId('rtStringLength');
  if (builtin == bStringCodeUnit) return armFunctionId('rtStringCodeUnit');
  if (builtin == bStringSubstring) return armFunctionId('rtStringSubstring');
  if (builtin == bStringFromCodes) return armFunctionId('rtStringFromCodes');
  if (builtin == bStringIndexOf) return armFunctionId('rtStringIndexOf');
  if (builtin == bStringStartsWith) return armFunctionId('rtStringStartsWith');
  if (builtin == bStringEndsWith) return armFunctionId('rtStringEndsWith');
  if (builtin == bStringLastIndexOf)
    return armFunctionId('rtStringLastIndexOf');
  if (builtin == bIntParse) return armFunctionId('rtIntParse');
  if (builtin == bListNew) return armFunctionId('rtListNew');
  if (builtin == bListLength) return armFunctionId('rtListLength');
  if (builtin == bListGet) return armFunctionId('rtListGet');
  if (builtin == bListSet) return armFunctionId('rtListSet');
  if (builtin == bListAdd) return armFunctionId('rtListAdd');
  if (builtin == bListRemoveLast) return armFunctionId('rtListRemoveLast');
  if (builtin == bListClear) return armFunctionId('rtListClear');
  if (builtin == bListFilled) return armFunctionId('rtListFilled');
  if (builtin == bHostRead) return armFunctionId('rtHostRead');
  if (builtin == bHostWrite) return armFunctionId('rtHostWrite');
  if (builtin == bHostFinish) return armFunctionId('rtHostFinish');
  if (builtin == bHostExit) return armFunctionId('rtHostExit');
  if (builtin == bHostStdPath) return armFunctionId('rtHostStdPath');
  if (builtin == bArguments) return armFunctionId('rtArguments');
  if (builtin == bHostTarget) return armFunctionId('rtHostTarget');
  print('Unknown native builtin: ' + builtin.toString());
  hostExit(1);
}

void armCall(int target) {
  armCallSites.add(machineCode.length);
  armCallTargets.add(target);
  machineCode.add(0x94000000);
}

void armReturn() {
  armPop(0);
  machineCode.add(0x910003bf);
  machineCode.add(0xa8c17bfd);
  machineCode.add(0xd65f03c0);
}

void armArguments(int count) {
  var i = count;
  while (i > 0) {
    i = i - 1;
    armPop(i);
  }
}

void generateArm64() {
  machineCode = <int>[];
  addressSites = <int>[];
  addressKinds = <int>[];
  addressTargets = <int>[];
  armIrOffsets = <int>[];
  armFunctionOffsets = <int>[];
  armCallSites = <int>[];
  armCallTargets = <int>[];
  armBranchSites = <int>[];
  armBranchTargets = <int>[];
  armBranchKinds = <int>[];
  entryOffset = 0;
  var i = 0;
  while (i <= ir.length) {
    armIrOffsets.add(0);
    i = i + 1;
  }
  i = 0;
  while (i < functionNames.length) {
    armFunctionOffsets.add(0);
    i = i + 1;
  }
  var function = 0;
  if (imageKind == 0) {
    var argumentsFunction = armFunctionId('rtArguments');
    var mainFunction = armFunctionId('main');
    // Darwin LC_MAIN supplies registers; Linux starts with argc/argv on SP.
    if (targetOS == 1) {
      machineCode.add(0xf94003e0);
      machineCode.add(0x910023e1);
    }
    armPush(0);
    armPush(1);
    armCall(0);
    armPop(1);
    armPop(0);
    armCall(argumentsFunction);
    armCall(mainFunction);
    armConstant(0, 0);
    if (targetOS == 1) {
      armConstant(8, 93);
      machineCode.add(0xd4000001);
    } else {
      armConstant(16, 1);
      machineCode.add(0xd4001001);
    }
  } else {
    // Context-free libraries have neither application startup nor initializers.
    function = 1;
  }
  while (function < functionNames.length) {
    armFunctionOffsets[function] = machineCode.length;
    machineCode.add(0xa9bf7bfd);
    machineCode.add(0x910003fd);
    var frame = ((functionLocals[function] * 8 + 15) ~/ 16) * 16;
    while (frame >= 4096) {
      machineCode.add(0xd14007ff);
      frame = frame - 4096;
    }
    if (frame != 0) machineCode.add(0xd10003ff | (frame << 10));
    i = 0;
    while (i < functionParams[function]) {
      armStoreLocal(i, i);
      i = i + 1;
    }
    var position = functionStarts[function];
    var end = ir.length;
    if (function + 1 < functionNames.length) end = functionStarts[function + 1];
    while (position < end) {
      armIrOffsets[position] = machineCode.length;
      var op = ir[position];
      position = position + 1;
      if (imageKind != 0 &&
          (op == opString || op == opLoadGlobal || op == opStoreGlobal)) {
        print(
          'Native libraries require functions without strings or global state',
        );
        hostExit(1);
      }
      if (op == opInt) {
        armConstant(0, ir[position]);
        position = position + 1;
        armPush(0);
        continue;
      }
      if (op == opString) {
        armAddress(0, ir[position]);
        position = position + 1;
        armPush(0);
        continue;
      }
      if (op == opLoadLocal) {
        armLoadLocal(ir[position], 0);
        position = position + 1;
        armPush(0);
        continue;
      }
      if (op == opStoreLocal) {
        armPop(0);
        armStoreLocal(ir[position], 0);
        position = position + 1;
        continue;
      }
      if (op == opLoadGlobal) {
        armAddress(1, ir[position]);
        position = position + 1;
        machineCode.add(0xf9400000);
        armPush(0);
        continue;
      }
      if (op == opStoreGlobal) {
        armPop(1);
        armAddress(1, ir[position]);
        position = position + 1;
        machineCode.add(0xf9000001);
        continue;
      }
      if (op == opPop) {
        machineCode.add(0x910043ff);
        continue;
      }
      if (op == opDup) {
        machineCode.add(0xf94003e0);
        armPush(0);
        continue;
      }
      if (op == opJump || op == opJumpFalse) {
        if (op == opJumpFalse) armPop(0);
        armBranchSites.add(machineCode.length);
        armBranchTargets.add(ir[position]);
        armBranchKinds.add(op);
        position = position + 1;
        machineCode.add(0);
        continue;
      }
      if (op == opCall || op == opBuiltin) {
        var target = ir[position];
        var count = ir[position + 1];
        position = position + 2;
        if (imageKind != 0 && op == opBuiltin && target < bNativeLoad64) {
          print('Native libraries cannot use managed runtime operations');
          hostExit(1);
        }
        armArguments(count);
        if (op == opCall) {
          armCall(target);
          armPush(0);
          continue;
        }
        if (target == bNativeLoad64) {
          machineCode.add(0xf9400000);
        } else if (target == bNativeStore64) {
          machineCode.add(0xf9000001);
          armConstant(0, 0);
        } else if (target == bNativeLoad8) {
          machineCode.add(0x39400000);
        } else if (target == bNativeStore8) {
          machineCode.add(0x39000001);
          armConstant(0, 0);
        } else if (target == bNativeSyscall) {
          if (targetOS == 1) {
            armMove(8, 0);
          } else {
            armMove(16, 0);
          }
          i = 0;
          while (i < 6) {
            armMove(i, i + 1);
            i = i + 1;
          }
          if (targetOS == 1) {
            machineCode.add(0xd4000001);
          } else {
            machineCode.add(0xd4001001);
            machineCode.add(0xda803400);
          }
        } else if (target == bNativeTarget) {
          armConstant(0, targetOS);
        } else {
          var nativeFunction = armBuiltinFunction(target);
          armCall(nativeFunction);
        }
        armPush(0);
        continue;
      }
      if (op == opReturn) {
        armReturn();
        continue;
      }
      if (op == opNeg || op == opBitNot || op == opNot) {
        armPop(0);
        if (op == opNeg) machineCode.add(0xcb0003e0);
        if (op == opBitNot) machineCode.add(0xaa2003e0);
        if (op == opNot) {
          machineCode.add(0xf100001f);
          machineCode.add(0x9a9f17e0);
        }
        armPush(0);
        continue;
      }
      armPop(1);
      armPop(0);
      if (op == opAdd) machineCode.add(0x8b010000);
      if (op == opSub) machineCode.add(0xcb010000);
      if (op == opMul) machineCode.add(0x9b017c00);
      if (op == opDiv) machineCode.add(0x9ac10c00);
      if (op == opMod) {
        machineCode.add(0x9ac10c02);
        machineCode.add(0x9b018040);
        // Dart % is Euclidean: adjust a negative machine remainder.
        machineCode.add(0xf100001f);
        machineCode.add(0x540000aa);
        machineCode.add(0xf100003f);
        machineCode.add(0x5400004a);
        machineCode.add(0xcb0103e1);
        machineCode.add(0x8b010000);
      }
      if (op == opAnd) machineCode.add(0x8a010000);
      if (op == opOr) machineCode.add(0xaa010000);
      if (op == opXor) machineCode.add(0xca010000);
      if (op == opShl) machineCode.add(0x9ac12000);
      if (op == opShr) machineCode.add(0x9ac12800);
      if (op == opUshr) machineCode.add(0x9ac12400);
      if (op >= opEq && op <= opGe) {
        machineCode.add(0xeb01001f);
        var condition = 0;
        if (op == opNe) condition = 1;
        if (op == opLt) condition = 11;
        if (op == opLe) condition = 13;
        if (op == opGt) condition = 12;
        if (op == opGe) condition = 10;
        machineCode.add(0x9a9f07e0 | ((condition ^ 1) << 12));
      }
      armPush(0);
    }
    function = function + 1;
  }
  armIrOffsets[ir.length] = machineCode.length;
  i = 0;
  while (i < armCallSites.length) {
    var site = armCallSites[i];
    var target = armFunctionOffsets[armCallTargets[i]];
    machineCode[site] = 0x94000000 | ((target - site) & 0x3ffffff);
    i = i + 1;
  }
  i = 0;
  while (i < armBranchSites.length) {
    var site = armBranchSites[i];
    var target = armIrOffsets[armBranchTargets[i]];
    if (armBranchKinds[i] == opJump) {
      machineCode[site] = 0x14000000 | ((target - site) & 0x3ffffff);
    } else {
      machineCode[site] = 0xb4000000 | (((target - site) & 0x7ffff) << 5);
    }
    i = i + 1;
  }
}
