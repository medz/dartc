const int opInt = 1;
const int opString = 2;
const int opLoadLocal = 3;
const int opStoreLocal = 4;
const int opLoadGlobal = 5;
const int opStoreGlobal = 6;
const int opPop = 7;
const int opDup = 8;
const int opAdd = 9;
const int opSub = 10;
const int opMul = 11;
const int opDiv = 12;
const int opMod = 13;
const int opNeg = 14;
const int opAnd = 15;
const int opOr = 16;
const int opXor = 17;
const int opShl = 18;
const int opShr = 19;
const int opUshr = 20;
const int opBitNot = 21;
const int opEq = 22;
const int opNe = 23;
const int opLt = 24;
const int opLe = 25;
const int opGt = 26;
const int opGe = 27;
const int opJump = 28;
const int opJumpFalse = 29;
const int opCall = 30;
const int opBuiltin = 31;
const int opReturn = 32;
const int opNot = 33;
const int opDescriptor = 34;
const int opMetadataAddress = 35;
const int opTypeTest = 36;
const int opTypeCast = 37;

const int bPrintString = 1;
const int bPrintInt = 2;
const int bPrintBool = 3;
const int bIntToString = 4;
const int bStringConcat = 5;
const int bStringEqual = 6;
const int bStringLength = 7;
const int bStringCodeUnit = 8;
const int bStringSubstring = 9;
const int bStringFromCodes = 10;
const int bStringIndexOf = 11;
const int bStringStartsWith = 12;
const int bStringEndsWith = 13;
const int bIntParse = 14;
const int bListNew = 15;
const int bListLength = 16;
const int bListGet = 17;
const int bListSet = 18;
const int bListAdd = 19;
const int bListRemoveLast = 20;
const int bListClear = 21;
const int bListFilled = 22;
const int bHostRead = 23;
const int bHostWrite = 24;
const int bHostFinish = 25;
const int bHostExit = 26;
const int bHostStdPath = 27;
const int bArguments = 28;
const int bStringLastIndexOf = 29;
const int bHostTarget = 30;
const int bObjectNew = 31;
const int bObjectGet = 32;
const int bObjectSet = 33;
const int bBoxInt = 34;
const int bBoxBool = 35;
const int bBoxRef = 36;
const int bValueCast = 37;
const int bValueBool = 38;
const int bValueAdd = 39;
const int bValueSub = 40;
const int bValueMul = 41;
const int bValueDiv = 42;
const int bValueMod = 43;
const int bValueAnd = 44;
const int bValueOr = 45;
const int bValueXor = 46;
const int bValueShl = 47;
const int bValueShr = 48;
const int bValueUshr = 49;
const int bValueEq = 50;
const int bValueLt = 51;
const int bValueLe = 52;
const int bValueGt = 53;
const int bValueGe = 54;
const int bValueToString = 55;
const int bValueIs = 56;

const int bNativeLoad64 = 100;
const int bNativeStore64 = 101;
const int bNativeLoad8 = 102;
const int bNativeStore8 = 103;
const int bNativeSyscall = 104;
const int bNativeTarget = 105;
const int bNativeLoad16 = 106;
const int bNativeStore16 = 107;
const int bNativeMetadataAddress = 108;
const int bNativeCall1 = 109;

class FunctionInfo {
  String name;
  int start;
  int parameters;
  int locals;
  int result;
  List<int> parameterTypes;
  List<int> localTypes;
  int source;

  FunctionInfo(
    this.name,
    this.start,
    this.parameters,
    this.locals,
    this.result,
    this.parameterTypes,
    this.localTypes,
    this.source,
  );
}

List<int> ir = <int>[];
List<int> irTypes = <int>[];
List<FunctionInfo> functions = <FunctionInfo>[];
List<String> globalNames = <String>[];
List<int> globalTypes = <int>[];
List<String> strings = <String>[];

int entrySource = -1;
int targetOS = 0;
int imageKind = 0;
List<String> exportNames = <String>[];
List<int> exportFunctions = <int>[];
List<int> exportParameters = <int>[];

List<int> classSizes = <int>[];
List<int> classPointerMasks = <int>[];
List<int> classTaggedMasks = <int>[];
List<String> classNames = <String>[];
List<int> classToStringFunctions = <int>[];

int internString(String text) {
  var i = 0;
  while (i < strings.length) {
    if (strings[i] == text) return i;
    i++;
  }
  strings.add(text);
  return strings.length - 1;
}

int irWidth(int op) {
  if (op == opCall || op == opBuiltin) return 3;
  if (op == opInt ||
      op == opString ||
      op == opDescriptor ||
      op == opMetadataAddress ||
      op == opTypeTest ||
      op == opTypeCast ||
      op == opLoadLocal ||
      op == opStoreLocal ||
      op == opLoadGlobal ||
      op == opStoreGlobal ||
      op == opJump ||
      op == opJumpFalse)
    return 2;
  return 1;
}
