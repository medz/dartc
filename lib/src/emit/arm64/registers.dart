import '../allocate.dart';
import '../machine.dart';

/// The word registers that hold a value only within one operation.
const calleeScratch = 8, leftScratch = 15, rightScratch = 16, farScratch = 17;

/// The double registers that hold a value only within one operation.
const leftFloatScratch = 29, rightFloatScratch = 30;

/// Values cannot be in x8 and x15 to x17, which are scratch, x18, which belongs
/// to the system, x28, which has where the data of the isolate is, and x29 to
/// x31, which form the frame, or in d29 and d30, which are scratch.
const arm64Registers = MachineRegisters(
  values: {
    .word: RegisterSet(
      volatile: [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14],
      preserved: [19, 20, 21, 22, 23, 24, 25, 26, 27],
    ),
    .float: RegisterSet(
      volatile: [
        0, 1, 2, 3, 4, 5, 6, 7, //
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 31,
      ],
      preserved: [8, 9, 10, 11, 12, 13, 14, 15],
    ),
  },
  arguments: {
    .word: [0, 1, 2, 3, 4, 5, 6, 7],
    .float: [0, 1, 2, 3, 4, 5, 6, 7],
  },
  results: {.word: 0, .float: 0},
  operands: {
    .word: [leftScratch, rightScratch, calleeScratch],
    .float: [leftFloatScratch, rightFloatScratch, leftFloatScratch],
  },
  cycles: {.word: rightScratch, .float: rightFloatScratch},
  carrier: leftScratch,
  callee: calleeScratch,
  resumedFrame: 9,
  caught: [0, 1],
  isolate: 28,
);
