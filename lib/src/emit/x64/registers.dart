import '../allocate.dart';
import '../machine.dart';

/// The word registers that hold a value only within one operation: rax is free
/// for any of it, and the others hold operands.
const freeScratch = 0, leftScratch = 10, rightScratch = 11;

/// The double registers that hold a value only within one operation.
const leftFloatScratch = 14, rightFloatScratch = 15;

/// Values cannot be in rsp and rbp, which form the frame, in r15, which has
/// where the data of the isolate is, or in scratch registers. Calls preserve no doubles.
const x64Registers = MachineRegisters(
  values: {
    .word: RegisterSet(
      volatile: [1, 2, 6, 7, 8, 9],
      preserved: [3, 12, 13, 14],
    ),
    .float: RegisterSet(
      volatile: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13],
      preserved: [],
    ),
  },
  arguments: {
    .word: [7, 6, 2, 1, 8, 9],
    .float: [0, 1, 2, 3, 4, 5, 6, 7],
  },
  results: {.word: 0, .float: 0},
  operands: {
    .word: [leftScratch, rightScratch, freeScratch],
    .float: [leftFloatScratch, rightFloatScratch, leftFloatScratch],
  },
  cycles: {.word: rightScratch, .float: rightFloatScratch},
  carrier: leftScratch,
  callee: freeScratch,
  resumedFrame: 1,
  caught: [7, 6],
  isolate: 15,
);
