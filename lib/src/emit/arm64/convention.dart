import 'package:dartc/lir.dart';

import '../allocate.dart';

/// The registers values may occupy.
///
/// Excluded words: x8 and x15 to x17 are scratch, x18 belongs to the system,
/// and x29 to x31 form the frame. Excluded doubles: d29 and d30 are scratch.
const arm64Registers = {
  RegisterBank.word: RegisterSet(
    volatile: [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14],
    preserved: [19, 20, 21, 22, 23, 24, 25, 26, 27, 28],
  ),
  RegisterBank.float: RegisterSet(
    volatile: [
      0, 1, 2, 3, 4, 5, 6, 7, //
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 31,
    ],
    preserved: [8, 9, 10, 11, 12, 13, 14, 15],
  ),
};

/// The word registers that hold a value only within one operation.
const calleeScratch = 8, leftScratch = 15, rightScratch = 16, farScratch = 17;

/// The double registers that hold a value only within one operation.
const leftFloatScratch = 29, rightFloatScratch = 30;

/// The system function that allocates: calloc(count, size).
const allocateSymbol = 'calloc';

const _argumentRegisters = 8;

/// Where a call's arguments are passed, in order.
///
/// Each bank passes eight in registers; the rest take stack words in order.
/// This agrees with the system convention for 64-bit values.
List<Location> argumentLocations(LirSignature signature, StackArea area) {
  final used = {for (final bank in RegisterBank.values) bank: 0};
  var words = 0;
  return [
    for (final type in signature.parameters)
      if (RegisterBank.of(type) case final bank
          when used[bank]! < _argumentRegisters)
        InRegister(bank, used.update(bank, (count) => count + 1) - 1)
      else
        OnStack(area, words++),
  ];
}

/// The register holding a call's result.
Location resultLocation(LirType type) => InRegister(.of(type), 0);
