import 'types.dart';

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
const int opJumpTrue = 38;
const int opConstantData = 39;
const int opFunctionReference = 40;
const int opClosureDescriptor = 41;
const int opCaptureCellDescriptor = 42;
const int opTypeReference = 43;
const int opGenericCall = 44;
const int opDouble = 45;
const int opDoubleAdd = 46;
const int opDoubleSub = 47;
const int opDoubleMul = 48;
const int opDoubleDiv = 49;
const int opDoubleCompare = 50;
const int opDoubleNeg = 51;
const int opIntToDouble = 52;
const int opLateCellDescriptor = 53;
const int opUnreachable = 54;
const int opBeginTry = 55;
const int opEndTry = 56;

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
const int bListFromData = 57;
const int bValueIdentical = 58;
const int bObjectFromData = 59;
const int bHostReadIfExists = 60;
const int bHostCurrentDirectory = 61;
const int bFunctionEntry = 62;
const int bFunctionInvoke = 63;
const int bListRemoveAt = 64;
const int bListInsert = 65;
const int bFunctionType = 66;
const int bListSublist = 67;
const int bTypeInstantiate = 68;
const int bValueCheck = 69;
const int bListNewTyped = 70;
const int bListFilledTyped = 71;
const int bBoxDouble = 72;
const int bDoubleToString = 73;
const int bDoubleModulo = 74;
const int bDoubleTruncDiv = 75;
const int bDoubleToInt = 76;
const int bDoubleParse = 77;
const int bDoubleTryParse = 78;
const int bValueFloatDiv = 79;
const int bValueNeg = 80;
const int bValueToDouble = 81;
const int bValueToInt = 82;
const int bValueRemainder = 83;
const int bValueCompareTo = 84;
const int bNumberProperty = 85;
const int bLateError = 86;

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
const int bNativeCall0 = 110;
const int bNativeFramePointer = 111;
// IEEE binary64 operations on raw bit patterns. Conversion to int truncates
// and saturates; NaN converts to zero. Compare returns -1, 0, 1, or 2 (NaN).
const int bNativeFloat64Add = 112;
const int bNativeFloat64Sub = 113;
const int bNativeFloat64Mul = 114;
const int bNativeFloat64Div = 115;
const int bNativeFloat64Compare = 116;
const int bNativeFloat64FromInt = 117;
const int bNativeFloat64ToInt = 118;
// Expose/restore the internal tagged word. An exposed address is not a GC root.
const int bNativeValueBits = 119;
const int bNativeValueFromBits = 120;
const int bNativeExit = 121;
// Capture or restore FP/SP/PC and x19..x27 in a raw unwind context.
const int bNativeCaptureContext = 122;
const int bNativeResumeContext = 123;

int nativeBuiltinInputType(int primitive) =>
    primitive == bNativeValueBits ? nullableType(tObject) : tInt;
int nativeBuiltinResultType(int primitive) => switch (primitive) {
  bNativeExit || bNativeResumeContext => tNever,
  bNativeValueFromBits => nullableType(tObject),
  _ => tInt,
};

int nativeBuiltinArity(int primitive) {
  if (primitive == bNativeExit ||
      primitive == bNativeCaptureContext ||
      primitive == bNativeResumeContext ||
      primitive == bNativeValueBits ||
      primitive == bNativeValueFromBits ||
      primitive == bNativeLoad64 ||
      primitive == bNativeLoad8 ||
      primitive == bNativeLoad16 ||
      primitive == bNativeMetadataAddress ||
      primitive == bNativeCall0 ||
      primitive == bNativeFloat64FromInt ||
      primitive == bNativeFloat64ToInt)
    return 1;
  if (primitive == bNativeStore64 ||
      primitive == bNativeStore8 ||
      primitive == bNativeStore16 ||
      primitive == bNativeCall1 ||
      primitive >= bNativeFloat64Add && primitive <= bNativeFloat64Compare)
    return 2;
  if (primitive == bNativeSyscall) return 7;
  if (primitive == bNativeTarget || primitive == bNativeFramePointer) return 0;
  return -1;
}

const int contractNoGc = 1;
const int contractAllocate = 2;
const int contractMayGc = 4;

class FunctionContract {
  final int flags;
  final int token;

  const FunctionContract(this.flags, this.token);
}

class ClosureLayout {
  final List<int> fieldTypes;
  final bool boundReceiver;
  // The first capture holds the enclosing invocation's type environment.
  final List<int> typeParameters;

  ClosureLayout(
    this.fieldTypes, [
    this.boundReceiver = false,
    this.typeParameters = const <int>[],
  ]);

  int get valueCaptureOffset => typeParameters.isEmpty ? 0 : 1;
}

class FunctionInfo {
  List<int> typeParameters = const <int>[];
  int typeEnvironment = -1;
  String name;
  int start;
  int end = -1;
  int parameters;
  int locals;
  int result;
  List<int> parameterTypes;
  List<int> localTypes;
  int source;
  FunctionContract? contract;
  bool callableShape = false;
  int callableType = -1;
  int callableAdapter = -1;
  ClosureLayout? closureLayout;

  List<int> get typeScope => typeParameters.isNotEmpty
      ? typeParameters
      : closureLayout?.typeParameters ?? const <int>[];

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

// The frontend checks source arguments against the substituted signature.
// This call crosses the shared body's representation boundary explicitly.
class GenericCall {
  final int function;
  final List<int> typeArguments;

  GenericCall(this.function, this.typeArguments);
}

List<GenericCall> genericCalls = <GenericCall>[];

List<int> ir = <int>[];
List<int> irTypes = <int>[];
List<FunctionInfo> functions = <FunctionInfo>[];
List<String> globalNames = <String>[];
List<int> globalTypes = <int>[];
List<String> strings = <String>[];

int entrySource = -1;
int entryFunction = -1;
int targetOS = 0;
int imageKind = 0;
List<String> exportNames = <String>[];
List<int> exportFunctions = <int>[];
List<int> exportParameters = <int>[];

List<int> classSizes = <int>[];
List<List<int>> classPointerMasks = <List<int>>[];
List<List<int>> classTaggedMasks = <List<int>>[];
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

int functionValueType(int function) {
  var info = functions[function];
  if (!info.callableShape) return -1;
  if (info.callableType < 0) {
    var parameters = info.parameterTypes;
    if (info.closureLayout != null) parameters = parameters.sublist(1);
    info.callableType = functionType(info.result, parameters);
  }
  return info.callableType;
}

int irWidth(int op) {
  if (op == opCall || op == opGenericCall || op == opBuiltin) return 3;
  if (op == opInt ||
      op == opDouble ||
      op == opString ||
      op == opDescriptor ||
      op == opMetadataAddress ||
      op == opConstantData ||
      op == opFunctionReference ||
      op == opClosureDescriptor ||
      op == opCaptureCellDescriptor ||
      op == opLateCellDescriptor ||
      op == opTypeReference ||
      op == opTypeTest ||
      op == opTypeCast ||
      op == opLoadLocal ||
      op == opStoreLocal ||
      op == opLoadGlobal ||
      op == opStoreGlobal ||
      op == opJump ||
      op == opJumpFalse ||
      op == opJumpTrue)
    return 2;
  if (op == opBeginTry) return 2;
  return 1;
}
