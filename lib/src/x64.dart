import 'code.dart';
import 'host.dart';

const int xRax = 0;
const int xRcx = 1;
const int xRdx = 2;
const int xRsp = 4;
const int xRbp = 5;
const int xRsi = 6;
const int xRdi = 7;
const int xR8 = 8;
const int xR9 = 9;
const int xR10 = 10;
const int xR11 = 11;

const List<int> xArguments = <int>[xRdi, xRsi, xRdx, xRcx, xR8, xR9];
const List<int> xSyscallArguments = <int>[xRdi, xRsi, xRdx, xR10, xR8, xR9];

void xRex(bool wide, int reg, int base) =>
    codeByte(0x40 | (wide ? 8 : 0) | ((reg >> 3) << 2) | (base >> 3));

void xRegister(int opcode, int destination, int source) {
  xRex(true, source, destination);
  codeByte(opcode);
  codeByte(0xc0 | ((source & 7) << 3) | (destination & 7));
}

void xMove(int destination, int source) {
  if (destination != source) xRegister(0x89, destination, source);
}

void xConstant(int register, int value) {
  if (value >= 0 && value <= 0xffffffff) {
    if (register >= 8) codeByte(0x41);
    codeByte(0xb8 | (register & 7));
    codeWord(value);
  } else if (value >= -0x80000000 && value < 0) {
    xRex(true, 0, register);
    codeByte(0xc7);
    codeByte(0xc0 | (register & 7));
    codeWord(value);
  } else {
    xRex(true, 0, register);
    codeByte(0xb8 | (register & 7));
    codeWord(value);
    codeWord(value >>> 32);
  }
}

void xMemoryOperand(int reg, int base, int displacement) {
  final short = displacement >= -128 && displacement <= 127;
  codeByte((short ? 0x40 : 0x80) | ((reg & 7) << 3) | (base & 7));
  if ((base & 7) == 4) codeByte(0x24);
  if (short)
    codeByte(displacement);
  else
    codeWord(displacement);
}

void xLoad(int register, int base, int offset, [int width = 8]) {
  xRex(true, register, base);
  if (width == 8) {
    codeByte(0x8b);
  } else {
    codeByte(0x0f);
    codeByte(width == 2 ? 0xb7 : 0xb6);
  }
  xMemoryOperand(register, base, offset);
}

void xStore(int base, int offset, int register, [int width = 8]) {
  if (width == 2) codeByte(0x66);
  xRex(width == 8, register, base);
  codeByte(width == 1 ? 0x88 : 0x89);
  xMemoryOperand(register, base, offset);
}

void xImmediate(int operation, int register, int value) {
  xRex(true, 0, register);
  codeByte(0x81);
  codeByte(0xc0 | (operation << 3) | (register & 7));
  codeWord(value);
}

void xUnary(int operation, int register) {
  xRex(true, 0, register);
  codeByte(0xf7);
  codeByte(0xc0 | (operation << 3) | (register & 7));
}

void xShift(int operation, int register, int count) {
  xRex(true, 0, register);
  codeByte(count < 0 ? 0xd3 : 0xc1);
  codeByte(0xc0 | (operation << 3) | (register & 7));
  if (count >= 0) codeByte(count);
}

void xPush(int register) {
  if (register >= 8) codeByte(0x41);
  codeByte(0x50 | (register & 7));
}

void xPop(int register) {
  if (register >= 8) codeByte(0x41);
  codeByte(0x58 | (register & 7));
}

int xBranch([int condition = -1]) {
  if (condition >= 0) {
    codeByte(0x0f);
    codeByte(0x80 | condition);
  } else {
    codeByte(0xe9);
  }
  final offset = codeSize;
  codeWord(0);
  return offset;
}

void xPatchRelative(int offset, int target) {
  final displacement = target - offset - 4;
  if (displacement < -0x80000000 || displacement > 0x7fffffff) {
    xCodeError('relative address exceeds signed 32-bit range');
  }
  codePatchWord(offset, displacement);
}

void xCall(int function) {
  codeByte(0xe8);
  codeCalls.add(CodeCall(codeSize, function));
  codeWord(0);
}

void xCallRegister(int register) {
  xRex(true, 0, register);
  codeByte(0xff);
  codeByte(0xd0 | (register & 7));
}

void xAddress(int kind, int target) {
  codeByte(0x48);
  codeByte(0x8d);
  codeByte(0x05); // lea rax, [rip + disp32]
  codeAddresses.add(CodeAddress(codeSize, kind, target));
  codeWord(0);
}

void xSetCondition(int condition) {
  codeByte(0x0f);
  codeByte(0x90 | condition);
  codeByte(0xc0); // setcc al
  codeByte(0x0f);
  codeByte(0xb6);
  codeByte(0xc0); // movzx eax, al
}

void xFloatBits(int xmm, int register, bool toFloat) {
  codeByte(0x66);
  xRex(true, xmm, register);
  codeByte(0x0f);
  codeByte(toFloat ? 0x6e : 0x7e); // movq
  codeByte(0xc0 | (xmm << 3) | (register & 7));
}

void xTrap() {
  codeByte(0x0f);
  codeByte(0x0b); // ud2
}

void xExit(int status) {
  xConstant(xRdi, status);
  xConstant(xRax, 231); // Linux exit_group.
  codeByte(0x0f);
  codeByte(0x05);
  xTrap();
}

Never xCodeError(String message) {
  print('dartc x64: ' + message);
  hostExit(1);
}
