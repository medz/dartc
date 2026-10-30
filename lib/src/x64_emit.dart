import 'abi.dart';
import 'allocate.dart';
import 'code.dart';
import 'exports.dart';
import 'frame.dart';
import 'ir.dart';
import 'layout.dart';
import 'liveness.dart';
import 'machine.dart';
import 'root_map.dart';
import 'target.dart';
import 'types.dart';
import 'x64.dart';
import 'x64_ffi.dart';

void xValueLoad(MachineFunction function, int value, int register) {
  final location = function.allocation.locations[value];
  if (location >= 0)
    xMove(register, location);
  else
    xLoad(register, xRbp, location * 8);
}

void xValueStore(MachineFunction function, int value, int register) {
  final location = function.allocation.locations[value];
  if (location >= 0)
    xMove(location, register);
  else
    xStore(xRbp, location * 8, register);
}

int xCondition(int condition) => const <int>[4, 5, 12, 14, 15, 13][condition];

void xFloatCompare() {
  codeByte(0x66);
  codeByte(0x0f);
  codeByte(0x2e);
  codeByte(0xc1); // ucomisd xmm0, xmm1
}

void xFloatInstruction(
  MachineInstruction instruction,
  MachineFunction function,
) {
  final op = instruction.op;
  xValueLoad(function, instruction.inputs[0], xRax);
  if (op == mFloat64FromInt) {
    codeByte(0xf2);
    codeByte(0x48);
    codeByte(0x0f);
    codeByte(0x2a);
    codeByte(0xc0); // cvtsi2sd xmm0, rax
    xFloatBits(0, xRax, false);
    return;
  }
  if (op == mFloat64Neg) {
    xConstant(xR10, 0x8000000000000000);
    xRegister(0x31, xRax, xR10);
    return;
  }
  xFloatBits(0, xRax, true);
  if (op == mFloat64ToInt) {
    xFloatBits(1, xRax, true);
    xFloatCompare();
    final nan = xBranch(10); // parity: unordered
    xConstant(xRax, 0x43e0000000000000); // 2^63
    xFloatBits(1, xRax, true);
    xFloatCompare();
    final overflow = xBranch(3); // above or equal
    codeByte(0xf2);
    codeByte(0x48);
    codeByte(0x0f);
    codeByte(0x2c);
    codeByte(0xc0); // cvttsd2si rax, xmm0; negative overflow is MIN_INT.
    final done = xBranch();
    xPatchRelative(overflow, codeSize);
    xConstant(xRax, 0x7fffffffffffffff);
    final saturated = xBranch();
    xPatchRelative(nan, codeSize);
    xConstant(xRax, 0);
    xPatchRelative(done, codeSize);
    xPatchRelative(saturated, codeSize);
    return;
  }
  xValueLoad(function, instruction.inputs[1], xR10);
  xFloatBits(1, xR10, true);
  if (op == mFloat64Compare) {
    xFloatCompare();
    final nan = xBranch(10);
    final less = xBranch(2);
    xSetCondition(7); // above
    final done = xBranch();
    xPatchRelative(less, codeSize);
    xConstant(xRax, -1);
    final negative = xBranch();
    xPatchRelative(nan, codeSize);
    xConstant(xRax, 2);
    xPatchRelative(done, codeSize);
    xPatchRelative(negative, codeSize);
  } else {
    codeByte(0xf2);
    codeByte(0x0f);
    codeByte(switch (op) {
      mFloat64Add => 0x58,
      mFloat64Sub => 0x5c,
      mFloat64Mul => 0x59,
      mFloat64Div => 0x5e,
      _ => xCodeError('invalid floating instruction'),
    });
    codeByte(0xc1);
    xFloatBits(0, xRax, false);
  }
}

void xDivision(bool modulo) {
  xImmediate(7, xR10, -1);
  final ordinary = xBranch(5);
  xConstant(xR11, 0x8000000000000000);
  xRegister(0x39, xRax, xR11);
  final representable = xBranch(5);
  if (modulo) xConstant(xRax, 0);
  final overflow = xBranch();
  xPatchRelative(ordinary, codeSize);
  xPatchRelative(representable, codeSize);
  codeByte(0x48);
  codeByte(0x99); // cqo
  xUnary(7, xR10); // idiv
  if (modulo) {
    xMove(xRax, xRdx);
    xRegister(0x85, xRax, xRax);
    final positive = xBranch(9); // nonnegative
    xRegister(0x85, xR10, xR10);
    final divisorPositive = xBranch(9);
    xUnary(3, xR10);
    xPatchRelative(divisorPositive, codeSize);
    xRegister(0x01, xRax, xR10);
    xPatchRelative(positive, codeSize);
  }
  xPatchRelative(overflow, codeSize);
}

void xInstruction(
  MachineInstruction instruction,
  MachineFunction function,
  CallRootMap? roots,
  EmittedHandler? handler,
) {
  final MachineInstruction(:op, :output, :inputs) = instruction;
  if (op == mConstant) {
    xConstant(xRax, instruction.target);
  } else if (op == mMove) {
    xValueLoad(function, inputs[0], xRax);
  } else if (op >= mFloat64Add && op <= mFloat64Neg) {
    xFloatInstruction(instruction, function);
  } else if (op == mFramePointer) {
    xMove(xRax, xRbp);
  } else if (op == mCaptureContext) {
    xValueLoad(function, inputs[0], xR11);
    xStore(xR11, unwindFrameOffset, xRbp);
    xStore(xR11, unwindStackOffset, xRsp);
    codeByte(0x48);
    codeByte(0x8d);
    codeByte(0x05);
    codeWord(0); // lea rax, [rip]
    xStore(xR11, unwindPcOffset, xRax);
    final registers = targetRegisters;
    for (var i = 0; i < registers.length; i++)
      xStore(xR11, unwindRegistersOffset + i * 8, registers[i]);
    xConstant(xRax, 0);
  } else if (op == mResumeContext) {
    xValueLoad(function, inputs[0], xR11);
    xLoad(xRbp, xR11, unwindFrameOffset);
    xLoad(xR10, xR11, unwindStackOffset);
    xLoad(xRax, xR11, unwindPcOffset);
    final registers = targetRegisters;
    for (var i = 0; i < registers.length; i++)
      xLoad(registers[i], xR11, unwindRegistersOffset + i * 8);
    xMove(xRsp, xR10);
    codeByte(0xff);
    codeByte(0xe0); // jmp rax
    return;
  } else if (op == mAddress) {
    xAddress(instruction.extra, instruction.target);
  } else if (op == mLoad64 || op == mLoad8 || op == mLoad16) {
    xValueLoad(function, inputs[0], xRax);
    xLoad(xRax, xRax, 0, op == mLoad64 ? 8 : (op == mLoad16 ? 2 : 1));
  } else if (op == mStore64 || op == mStore8 || op == mStore16) {
    xValueLoad(function, inputs[0], xR10);
    xValueLoad(function, inputs[1], xRax);
    xStore(xR10, 0, xRax, op == mStore64 ? 8 : (op == mStore16 ? 2 : 1));
  } else if (op == mCall || op == mCallIndirect) {
    final vector = op == mCallIndirect && instruction.extra == 1;
    final first = vector ? 3 : (op == mCallIndirect ? 1 : 0);
    final count = inputs.length - first;
    final stacked = vector ? count : (count > 6 ? count - 6 : 0);
    final outgoing = alignFrame(stacked * 8);
    if (outgoing != 0) xImmediate(5, xRsp, outgoing);
    for (var argument = vector ? 0 : 6; argument < count; argument++) {
      xValueLoad(function, inputs[first + argument], xRax);
      xStore(xRsp, (vector ? argument : argument - 6) * 8, xRax);
    }
    if (vector) {
      xValueLoad(function, inputs[1], xRdi);
      xValueLoad(function, inputs[2], xRsi);
      xMove(xRdx, xRsp);
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
      for (var i = 0; i < count && i < 6; i++)
        xValueLoad(function, inputs[first + i], xArguments[i]);
    }
    if (op == mCallIndirect) {
      xValueLoad(function, inputs[0], xR11);
      xCallRegister(xR11);
    } else {
      xCall(instruction.target);
    }
    if (roots != null) {
      roots.returnOffset = codeSize;
      emittedRootMaps.add(roots);
    }
    if (handler != null) {
      handler.returnOffset = codeSize;
      emittedHandlers.add(handler);
    }
    if (outgoing != 0) xImmediate(0, xRsp, outgoing);
  } else if (op == mExit) {
    xValueLoad(function, inputs[0], xRdi);
    xConstant(xRax, targetOS == 0 ? 0x2000001 : 231);
    codeByte(0x0f);
    codeByte(0x05);
    xTrap();
    return;
  } else if (op == mSyscall) {
    xValueLoad(function, inputs[0], xRax);
    for (var i = 1; i < inputs.length; i++)
      xValueLoad(function, inputs[i], xSyscallArguments[i - 1]);
    if (targetOS == 0) xImmediate(1, xRax, 0x2000000); // Darwin UNIX class
    codeByte(0x0f);
    codeByte(0x05);
    if (targetOS == 0) {
      final success = xBranch(3); // carry clear
      xUnary(3, xRax); // normalize Darwin errno to a negative result
      xPatchRelative(success, codeSize);
    }
  } else if (op == mShlImmediate ||
      op == mShrImmediate ||
      op == mUshrImmediate) {
    xValueLoad(function, inputs[0], xRax);
    xShift(
      op == mShlImmediate ? 4 : (op == mShrImmediate ? 7 : 5),
      xRax,
      instruction.target,
    );
  } else if (op == mShl || op == mShr || op == mUshr) {
    xValueLoad(function, inputs[0], xRax);
    xValueLoad(function, inputs[1], xRcx);
    xRegister(0x85, xRcx, xRcx);
    final valid = xBranch(9);
    xExit(70);
    xPatchRelative(valid, codeSize);
    xImmediate(7, xRcx, 64);
    final small = xBranch(2);
    if (op == mShr)
      xShift(7, xRax, 63);
    else
      xConstant(xRax, 0);
    final done = xBranch();
    xPatchRelative(small, codeSize);
    xShift(op == mShl ? 4 : (op == mShr ? 7 : 5), xRax, -1);
    xPatchRelative(done, codeSize);
  } else if (op == mNeg || op == mBitNot || op == mNot) {
    xValueLoad(function, inputs[0], xRax);
    if (op == mNot) {
      xRegister(0x85, xRax, xRax);
      xSetCondition(4);
    } else {
      xUnary(op == mNeg ? 3 : 2, xRax);
    }
  } else {
    xValueLoad(function, inputs[0], xRax);
    xValueLoad(function, inputs[1], xR10);
    if (op == mDiv || op == mMod) {
      xDivision(op == mMod);
    } else if (op == mMul) {
      xRex(true, xRax, xR10);
      codeByte(0x0f);
      codeByte(0xaf);
      codeByte(0xc0 | (xR10 & 7));
    } else if (op == mCompare) {
      xRegister(0x39, xRax, xR10);
      xSetCondition(xCondition(instruction.extra));
    } else {
      xRegister(
        switch (op) {
          mAdd => 0x01,
          mSub => 0x29,
          mAnd => 0x21,
          mOr => 0x09,
          mXor => 0x31,
          _ => xCodeError('unsupported machine instruction'),
        },
        xRax,
        xR10,
      );
    }
  }
  if (output >= 0) xValueStore(function, output, xRax);
}

class XBlockBranch(final int offset, final int block);

void xEdge(
  MachineEdge edge,
  MachineFunction function,
  int fallthrough,
  List<XBlockBranch> branches,
) {
  final parameters = function.blocks[edge.target].parameters;
  final locations = function.allocation.locations;
  for (var i = 0; i < edge.arguments.length; i++) {
    if (locations[edge.arguments[i]] != locations[parameters[i]]) {
      xValueLoad(function, edge.arguments[i], xRax);
      xPush(xRax);
    }
  }
  for (var i = edge.arguments.length - 1; i >= 0; i--) {
    if (locations[edge.arguments[i]] != locations[parameters[i]]) {
      xPop(xRax);
      xValueStore(function, parameters[i], xRax);
    }
  }
  if (edge.target != fallthrough)
    branches.add(XBlockBranch(xBranch(), edge.target));
}

void xFunction(
  MachineFunction function,
  List<CallRootMap> roots,
  bool framesEnabled,
  int number,
) {
  var nextRoot = 0;
  final start = codeSize;
  final allocation = function.allocation;
  final frame = alignFrame(
    (allocation.spillSlots + allocation.savedRegisters.length) * 8,
  );
  xPush(xRbp);
  xMove(xRbp, xRsp);
  if (frame != 0) xImmediate(5, xRsp, frame);
  for (var i = 0; i < allocation.savedRegisters.length; i++)
    xStore(
      xRbp,
      -(allocation.spillSlots + i + 1) * 8,
      allocation.savedRegisters[i],
    );
  for (var i = 0; i < function.arguments.length; i++) {
    if (i < 6) {
      xValueStore(function, function.arguments[i], xArguments[i]);
    } else {
      xLoad(xRax, xRbp, 16 + (i - 6) * 8);
      xValueStore(function, function.arguments[i], xRax);
    }
  }
  final offsets = <int>[];
  final branches = <XBlockBranch>[];
  for (var b = 0; b < function.blocks.length; b++) {
    offsets.add(codeSize);
    final block = function.blocks[b];
    final end = block.end;
    final handler = end.kind == 5 || end.kind == 6 ? EmittedHandler() : null;
    for (var i = 0; i < block.instructions.length; i++) {
      CallRootMap? callRoots;
      if (nextRoot < roots.length &&
          roots[nextRoot].block == b &&
          roots[nextRoot].instruction == i)
        callRoots = roots[nextRoot++];
      xInstruction(
        block.instructions[i],
        function,
        callRoots,
        i + 1 == block.instructions.length ? handler : null,
      );
    }
    if (end.kind == 1) {
      xEdge(end.first, function, b + 1, branches);
    } else if (end.kind == 2) {
      xValueLoad(function, end.value, xRax);
      xRegister(0x85, xRax, xRax);
      final otherwise = xBranch(4);
      xEdge(end.first, function, -1, branches);
      xPatchRelative(otherwise, codeSize);
      xEdge(end.second, function, b + 1, branches);
    } else if (end.kind == 5 || end.kind == 6) {
      if (end.kind == 5)
        xEdge(end.first, function, -1, branches);
      else
        xTrap();
      handler!.landingOffset = codeSize;
      xEdge(end.second, function, b + 1, branches);
    } else if (end.kind == 4) {
      xTrap();
    } else {
      if (end.value >= 0)
        xValueLoad(function, end.value, xRax);
      else
        xConstant(xRax, 0);
      for (var i = 0; i < allocation.savedRegisters.length; i++)
        xLoad(
          allocation.savedRegisters[i],
          xRbp,
          -(allocation.spillSlots + i + 1) * 8,
        );
      xMove(xRsp, xRbp);
      xPop(xRbp);
      codeByte(0xc3);
    }
  }
  for (final branch in branches)
    xPatchRelative(branch.offset, offsets[branch.block]);
  if (framesEnabled) {
    var mask = 0;
    final registers = targetRegisters;
    for (var i = 0; i < registers.length; i++) {
      for (final saved in allocation.savedRegisters) {
        if (saved == registers[i]) mask |= 1 << i;
      }
    }
    emittedFrames.add(
      EmittedFrame(
        start,
        codeSize,
        frame,
        -(allocation.spillSlots + 1) * 8,
        mask,
        number,
      ),
    );
  }
}

void xRootBoundary(bool enabled) {
  if (!enabled) return;
  emittedRootMaps.add(
    CallRootMap(-1, -1, const <int>[], const <int>[])
      ..boundary = true
      ..returnOffset = codeSize,
  );
}

void generateX64(List<MachineFunction> program, int features) {
  final roots = (features & metadataRoots) != 0;
  final frames = (features & (metadataFrames | metadataHandlers)) != 0;
  if (imageKind == ImageKind.executable) {
    // LC_MAIN receives argc/argv in rdi/rsi with a return address on the
    // stack. Linux enters with a 16-byte-aligned argc/argv process stack.
    if (targetOS == 0) xPush(xRbp);
    final main = entryFunction;
    if (targetOS == 1) {
      xLoad(xRdi, xRsp, 0);
      xMove(xRsi, xRsp);
      xImmediate(0, xRsi, 8);
    }
    xPush(xRdi);
    xPush(xRsi);
    xCall(0);
    xRootBoundary(roots);
    xPop(xRsi);
    xPop(xRdi);
    if (functions[main].parameters == 0) {
      xCall(abiFunction('rtValidateArguments', 0));
    } else {
      xAddress(4, listType(tString));
      xMove(xRdx, xRax);
      xCall(runtimeFunction(bArguments, -1));
    }
    xRootBoundary(roots);
    if (functions[main].parameters > 0) xMove(xRdi, xRax);
    xCall(main);
    xRootBoundary(roots);
    xExit(0);
    if (frames) emittedFrames.add(EmittedFrame(0, codeSize, -1, 0, 0, -1));
  }
  for (
    var i = imageKind == ImageKind.executable ? 0 : 1;
    i < program.length;
    i++
  ) {
    final function = program[i];
    if (function.reachable) {
      final live = machineLiveness(function);
      allocateFunction(function, live);
      final rootMaps = roots
          ? buildCallRootMaps(function, live)
          : const <CallRootMap>[];
      functionOffsets[i] = codeSize;
      xFunction(function, rootMaps, frames, i);
    }
  }
  if (imageKind != ImageKind.executable) {
    for (final declaration in checkedExports) {
      exportOffsets.add(
        declaration.function < 0
            ? -1
            : emitX64Export(declaration.function, declaration.signature),
      );
    }
  }
  for (final call in codeCalls)
    xPatchRelative(call.offset, functionOffsets[call.function]);
}
