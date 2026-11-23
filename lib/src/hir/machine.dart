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
  writeError([.integer], null),
  resume([.integer, .integer, .reference, .reference], null),
  frameAddress([], .integer),
  codeStart([], .integer),
  stackMaps([], .integer),
  handlers([], .integer),
  classTable([], .integer),
  globalRoots([], .integer),
  globalRootCount([], .integer),
  collectsAlways([], .boolean),
}
