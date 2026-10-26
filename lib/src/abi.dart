import 'host.dart';
import 'ir.dart';

int abiFunction(String name, int source) {
  int i = 0;
  while (i < functions.length) {
    if (functions[i].name == name && functions[i].source == source) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

int runtimeFunction(int builtin) {
  if (imageKind != 0) {
    print('Library output cannot use managed runtime operations.');
    hostExit(1);
  }
  if (builtin == bPrintString) return abiFunction('rtPrintString', 0);
  if (builtin == bPrintInt) return abiFunction('rtPrintInt', 0);
  if (builtin == bPrintBool) return abiFunction('rtPrintBool', 0);
  if (builtin == bIntToString) return abiFunction('rtIntToString', 0);
  if (builtin == bStringConcat) return abiFunction('rtStringConcat', 0);
  if (builtin == bStringEqual) return abiFunction('rtStringEqual', 0);
  if (builtin == bStringLength) return abiFunction('rtStringLength', 0);
  if (builtin == bStringCodeUnit) return abiFunction('rtStringCodeUnit', 0);
  if (builtin == bStringSubstring) return abiFunction('rtStringSubstring', 0);
  if (builtin == bStringFromCodes) return abiFunction('rtStringFromCodes', 0);
  if (builtin == bStringIndexOf) return abiFunction('rtStringIndexOf', 0);
  if (builtin == bStringStartsWith) return abiFunction('rtStringStartsWith', 0);
  if (builtin == bStringEndsWith) return abiFunction('rtStringEndsWith', 0);
  if (builtin == bStringLastIndexOf)
    return abiFunction('rtStringLastIndexOf', 0);
  if (builtin == bIntParse) return abiFunction('rtIntParse', 0);
  if (builtin == bListNew) return abiFunction('rtListNew', 0);
  if (builtin == bListLength) return abiFunction('rtListLength', 0);
  if (builtin == bListGet) return abiFunction('rtListGet', 0);
  if (builtin == bListSet) return abiFunction('rtListSet', 0);
  if (builtin == bListAdd) return abiFunction('rtListAdd', 0);
  if (builtin == bListRemoveLast) return abiFunction('rtListRemoveLast', 0);
  if (builtin == bListClear) return abiFunction('rtListClear', 0);
  if (builtin == bListFilled) return abiFunction('rtListFilled', 0);
  if (builtin == bHostRead) return abiFunction('rtHostRead', 0);
  if (builtin == bHostWrite) return abiFunction('rtHostWrite', 0);
  if (builtin == bHostFinish) return abiFunction('rtHostFinish', 0);
  if (builtin == bHostExit) return abiFunction('rtHostExit', 0);
  if (builtin == bHostStdPath) return abiFunction('rtHostStdPath', 0);
  if (builtin == bArguments) return abiFunction('rtArguments', 0);
  if (builtin == bHostTarget) return abiFunction('rtHostTarget', 0);
  if (builtin == bObjectNew) return abiFunction('rtObjectNew', 0);
  if (builtin == bObjectGet) return abiFunction('rtObjectGet', 0);
  if (builtin == bObjectSet) return abiFunction('rtObjectSet', 0);
  print('Unknown native builtin: ' + builtin.toString());
  hostExit(1);
}
