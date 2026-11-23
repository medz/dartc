import 'value.dart';

/// Operations of the machine, which only the collector uses.
///
/// Each is named after a function of the collector's source. Parameters are
/// integers.
enum HirMachineOp(final int parameters, final HirType? result) {
  load64(1, .integer),
  store64(2, null),
  load32(1, .integer),
  load32Signed(1, .integer),
  store32(2, null),
  mapMemory(1, .integer),
  unmapMemory(2, null),
  trap(0, null),
  frameAddress(0, .integer),
  codeStart(0, .integer),
  stackMaps(0, .integer),
  classTable(0, .integer),
  globalRoots(0, .integer),
  globalRootCount(0, .integer),
  collectsAlways(0, .boolean),
}
