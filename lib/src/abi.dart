import 'host.dart';
import 'ir.dart';
import 'types.dart';

int abiFunction(String name, int source) {
  int i = 0;
  while (i < functions.length) {
    if (functions[i].name == name && functions[i].source == source) return i;
    i = i + 1;
  }
  print('Missing native function: ' + name);
  hostExit(1);
}

int runtimeFunction(int builtin, int castType) {
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
  if (builtin == bListInsert) return abiFunction('rtListInsert', 0);
  if (builtin == bListRemoveLast) return abiFunction('rtListRemoveLast', 0);
  if (builtin == bListRemoveAt) return abiFunction('rtListRemoveAt', 0);
  if (builtin == bListClear) return abiFunction('rtListClear', 0);
  if (builtin == bListFilled) return abiFunction('rtListFilled', 0);
  if (builtin == bListSublist) return abiFunction('rtListSublist', 0);
  if (builtin == bListFromData) return abiFunction('rtListFromData', 0);
  if (builtin == bObjectFromData) return abiFunction('rtObjectFromData', 0);
  if (builtin == bValueIdentical) return abiFunction('rtValueIdentical', 0);
  if (builtin == bHostRead) return abiFunction('rtHostRead', 0);
  if (builtin == bHostReadIfExists) return abiFunction('rtHostReadIfExists', 0);
  if (builtin == bHostCurrentDirectory)
    return abiFunction('rtHostCurrentDirectory', 0);
  if (builtin == bFunctionEntry) return abiFunction('rtFunctionEntry', 0);
  if (builtin == bFunctionType) return abiFunction('rtFunctionType', 0);
  if (builtin == bHostWrite) return abiFunction('rtHostWrite', 0);
  if (builtin == bHostFinish) return abiFunction('rtHostFinish', 0);
  if (builtin == bHostExit) return abiFunction('rtHostExit', 0);
  if (builtin == bHostStdPath) return abiFunction('rtHostStdPath', 0);
  if (builtin == bArguments) return abiFunction('rtArguments', 0);
  if (builtin == bHostTarget) return abiFunction('rtHostTarget', 0);
  if (builtin == bObjectNew) return abiFunction('rtObjectNew', 0);
  if (builtin == bObjectGet) return abiFunction('rtObjectGet', 0);
  if (builtin == bObjectSet) return abiFunction('rtObjectSet', 0);
  if (builtin == bBoxInt) return abiFunction('rtBoxInt', 0);
  if (builtin == bBoxBool) return abiFunction('rtBoxBool', 0);
  if (builtin == bValueCast) {
    if (castType == tInt) return abiFunction('rtValueInt', 0);
    if (castType == tBool) return abiFunction('rtValueBool', 0);
    return abiFunction('rtValueCast', 0);
  }
  if (builtin == bValueIs) return abiFunction('rtValueMatches', 0);
  if (builtin == bValueBool) return abiFunction('rtValueBool', 0);
  if (builtin == bValueAdd) return abiFunction('rtValueAdd', 0);
  if (builtin == bValueSub) return abiFunction('rtValueSub', 0);
  if (builtin == bValueMul) return abiFunction('rtValueMul', 0);
  if (builtin == bValueDiv) return abiFunction('rtValueDiv', 0);
  if (builtin == bValueMod) return abiFunction('rtValueMod', 0);
  if (builtin == bValueAnd) return abiFunction('rtValueAnd', 0);
  if (builtin == bValueOr) return abiFunction('rtValueOr', 0);
  if (builtin == bValueXor) return abiFunction('rtValueXor', 0);
  if (builtin == bValueShl) return abiFunction('rtValueShl', 0);
  if (builtin == bValueShr) return abiFunction('rtValueShr', 0);
  if (builtin == bValueUshr) return abiFunction('rtValueUshr', 0);
  if (builtin == bValueEq) return abiFunction('rtValueEq', 0);
  if (builtin == bValueLt) return abiFunction('rtValueLt', 0);
  if (builtin == bValueLe) return abiFunction('rtValueLe', 0);
  if (builtin == bValueGt) return abiFunction('rtValueGt', 0);
  if (builtin == bValueGe) return abiFunction('rtValueGe', 0);
  if (builtin == bValueToString) return abiFunction('rtValueToString', 0);
  print('Unknown native builtin: ' + builtin.toString());
  hostExit(1);
}
