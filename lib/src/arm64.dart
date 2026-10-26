import 'host.dart';
import 'ir.dart';

List<int> machineCode = <int>[];
List<int> addressSites = <int>[];
List<int> addressKinds = <int>[];
List<int> addressTargets = <int>[];
int entryOffset = 0;

List<int> armFunctionOffsets = <int>[];
List<int> armCallSites = <int>[];
List<int> armCallTargets = <int>[];

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
  while (i < functions.length) {
    if (functions[i].name == name) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

void armCall(int target) {
  armCallSites.add(machineCode.length);
  armCallTargets.add(target);
  machineCode.add(0x94000000);
}
