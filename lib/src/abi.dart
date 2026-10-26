import 'host.dart';
import 'ir.dart';

int abiFunction(String name) {
  int i = 0;
  while (i < functions.length) {
    if (functions[i].name == name) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

int runtimeFunction(int builtin) {
  if (builtin == bPrintString) return abiFunction('rtPrintString');
  if (builtin == bPrintInt) return abiFunction('rtPrintInt');
  if (builtin == bPrintBool) return abiFunction('rtPrintBool');
  if (builtin == bIntToString) return abiFunction('rtIntToString');
  if (builtin == bStringConcat) return abiFunction('rtStringConcat');
  if (builtin == bStringEqual) return abiFunction('rtStringEqual');
  if (builtin == bStringLength) return abiFunction('rtStringLength');
  if (builtin == bStringCodeUnit) return abiFunction('rtStringCodeUnit');
  if (builtin == bStringSubstring) return abiFunction('rtStringSubstring');
  if (builtin == bStringFromCodes) return abiFunction('rtStringFromCodes');
  if (builtin == bStringIndexOf) return abiFunction('rtStringIndexOf');
  if (builtin == bStringStartsWith) return abiFunction('rtStringStartsWith');
  if (builtin == bStringEndsWith) return abiFunction('rtStringEndsWith');
  if (builtin == bStringLastIndexOf) return abiFunction('rtStringLastIndexOf');
  if (builtin == bIntParse) return abiFunction('rtIntParse');
  if (builtin == bListNew) return abiFunction('rtListNew');
  if (builtin == bListLength) return abiFunction('rtListLength');
  if (builtin == bListGet) return abiFunction('rtListGet');
  if (builtin == bListSet) return abiFunction('rtListSet');
  if (builtin == bListAdd) return abiFunction('rtListAdd');
  if (builtin == bListRemoveLast) return abiFunction('rtListRemoveLast');
  if (builtin == bListClear) return abiFunction('rtListClear');
  if (builtin == bListFilled) return abiFunction('rtListFilled');
  if (builtin == bHostRead) return abiFunction('rtHostRead');
  if (builtin == bHostWrite) return abiFunction('rtHostWrite');
  if (builtin == bHostFinish) return abiFunction('rtHostFinish');
  if (builtin == bHostExit) return abiFunction('rtHostExit');
  if (builtin == bHostStdPath) return abiFunction('rtHostStdPath');
  if (builtin == bArguments) return abiFunction('rtArguments');
  if (builtin == bHostTarget) return abiFunction('rtHostTarget');
  if (builtin == bObjectNew) return abiFunction('rtObjectNew');
  if (builtin == bObjectGet) return abiFunction('rtObjectGet');
  if (builtin == bObjectSet) return abiFunction('rtObjectSet');
  print('Unknown native builtin: ' + builtin.toString());
  hostExit(1);
}
