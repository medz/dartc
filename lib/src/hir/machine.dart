import 'value.dart';

/// Operations of the machine, which only the runtime uses.
///
/// Each is named after a function of the runtime's source.
enum HirMachineOp(final List<HirType> parameters, final HirType? result) {
  load64([.integer], .integer),
  store64([.integer, .integer], null),
  load32([.integer], .integer),
  load32Signed([.integer], .integer),
  store32([.integer, .integer], null),
  mapMemory([.integer], .integer),
  unmapMemory([.integer, .integer], null),
  trap([], null),
  load8([.integer], .integer),
  store8([.integer, .integer], null),
  outputBuffer([], .integer),
  write([.integer, .integer, .integer], null),
  formatDouble([.float, .integer, .integer], null),
  parseDouble([.integer], .float),
  resume([.integer, .integer, .reference, .reference], null),
  frameAddress([], .integer),
  codeStart([], .integer),
  stackMaps([], .integer),
  handlers([], .integer),
  classTable([], .integer),
  globalRoots([], .integer),
  globalRootCount([], .integer),
  collectsAlways([], .boolean),
  isSame([.reference, .reference], .boolean),
  classNumber([.reference], .integer),
  addressOf([.reference], .integer),
}
