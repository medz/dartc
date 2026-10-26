import 'ir.dart';
import 'host.dart';

List<String> feTokens = <String>[];
List<int> feKinds = <int>[];
int feAt = 0;
List<int> feBodies = <int>[];
List<int> feGlobalValues = <int>[];
List<int> feParamStarts = <int>[];
List<String> feParamNames = <String>[];
List<int> feParamTypes = <int>[];
List<String> feLocalNames = <String>[];
List<int> feLocalTypes = <int>[];
List<int> feLocalSlots = <int>[];
List<int> feBreaks = <int>[];
List<int> feContinues = <int>[];
List<int> feLoopBreaks = <int>[];
List<int> feLoopContinues = <int>[];
int feNextLocal = 0;
int feFunction = 0;
List<int> feSlotTypes = <int>[];
List<String> feNativeNames = <String>[];
List<int> feNativeParams = <int>[];
int feInitializingGlobal = -1;
List<String> feClassNames = <String>[];
List<int> feClassFieldCounts = <int>[];
List<int> feClassConstructors = <int>[];
List<String> feFieldNames = <String>[];
List<int> feFieldTypes = <int>[];
List<int> feFieldClasses = <int>[];
List<int> feFieldIndices = <int>[];
List<int> feOwners = <int>[];
List<int> feConstructors = <int>[];
List<int> feParamFields = <int>[];

void feError(String message) {
  print('dartc: ' + message + ' near token ' + feAt.toString());
  hostExit(1);
}

bool feDigit(int c) {
  return c >= 48 && c <= 57;
}

bool feLetter(int c) {
  return c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95 || c == 36;
}

int feHex(int c) {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 55;
  if (c >= 97 && c <= 102) return c - 87;
  feError('invalid hexadecimal digit');
  return 0;
}

void feToken(String text, int kind) {
  feTokens.add(text);
  feKinds.add(kind);
}

void feScan(String source) {
  feTokens.clear();
  feKinds.clear();
  var i = 0;
  while (i < source.length) {
    var c = source.codeUnitAt(i);
    if (c <= 32) {
      i++;
      continue;
    }
    if (c == 47 && i + 1 < source.length && source.codeUnitAt(i + 1) == 47) {
      while (i < source.length && source.codeUnitAt(i) != 10) i++;
      continue;
    }
    if (c == 47 && i + 1 < source.length && source.codeUnitAt(i + 1) == 42) {
      i += 2;
      var depth = 1;
      while (i + 1 < source.length && depth > 0) {
        if (source.codeUnitAt(i) == 47 && source.codeUnitAt(i + 1) == 42) {
          depth++;
          i += 2;
        } else if (source.codeUnitAt(i) == 42 &&
            source.codeUnitAt(i + 1) == 47) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) feError('unterminated comment');
      continue;
    }
    var raw = false;
    if (c == 114 &&
        i + 1 < source.length &&
        (source.codeUnitAt(i + 1) == 39 || source.codeUnitAt(i + 1) == 34)) {
      raw = true;
      i++;
      c = source.codeUnitAt(i);
    }
    if (c == 39 || c == 34) {
      var quote = c;
      var triple =
          i + 2 < source.length &&
          source.codeUnitAt(i + 1) == quote &&
          source.codeUnitAt(i + 2) == quote;
      i++;
      if (triple) i += 2;
      var units = <int>[];
      var closed = false;
      while (i < source.length) {
        c = source.codeUnitAt(i);
        if (c == quote &&
            (!triple ||
                i + 2 < source.length &&
                    source.codeUnitAt(i + 1) == quote &&
                    source.codeUnitAt(i + 2) == quote)) {
          i++;
          if (triple) i += 2;
          closed = true;
          break;
        }
        i++;
        if (!raw && c == 92) {
          if (i == source.length) feError('unterminated escape');
          c = source.codeUnitAt(i);
          i++;
          if (c == 110) {
            c = 10;
          } else if (c == 114) {
            c = 13;
          } else if (c == 116) {
            c = 9;
          } else if (c == 98) {
            c = 8;
          } else if (c == 102) {
            c = 12;
          } else if (c == 118) {
            c = 11;
          } else if (c == 120 || c == 117) {
            var count = 2;
            if (c == 117) count = 4;
            var braces =
                c == 117 && i < source.length && source.codeUnitAt(i) == 123;
            if (braces) i++;
            c = 0;
            var digits = 0;
            while (i < source.length &&
                (braces && source.codeUnitAt(i) != 125 ||
                    !braces && digits < count)) {
              c = c * 16 + feHex(source.codeUnitAt(i));
              i++;
              digits++;
            }
            if (braces) {
              if (i == source.length) feError('unterminated unicode escape');
              i++;
            }
          }
        }
        if (c > 65535) {
          c -= 65536;
          units.add(55296 + (c >> 10));
          units.add(56320 + (c & 1023));
        } else {
          units.add(c);
        }
      }
      if (!closed) feError('unterminated string');
      feToken(String.fromCharCodes(units), 3);
      continue;
    }
    if (feLetter(c)) {
      var start = i;
      i++;
      while (i < source.length &&
          (feLetter(source.codeUnitAt(i)) || feDigit(source.codeUnitAt(i))))
        i++;
      feToken(source.substring(start, i), 1);
      continue;
    }
    if (feDigit(c)) {
      var start = i;
      i++;
      while (i < source.length &&
          (feLetter(source.codeUnitAt(i)) || feDigit(source.codeUnitAt(i))))
        i++;
      feToken(source.substring(start, i), 2);
      continue;
    }
    var size = 1;
    if (i + 3 < source.length && source.substring(i, i + 4) == '>>>=') {
      size = 4;
    } else if (i + 2 < source.length) {
      var three = source.substring(i, i + 3);
      if (three == '>>>' || three == '<<=' || three == '>>=' || three == '~/=')
        size = 3;
    }
    if (size == 1 && i + 1 < source.length) {
      var two = source.substring(i, i + 2);
      if (two == '=>' ||
          two == '==' ||
          two == '!=' ||
          two == '<=' ||
          two == '>=' ||
          two == '&&' ||
          two == '||' ||
          two == '<<' ||
          two == '>>' ||
          two == '~/' ||
          two == '+=' ||
          two == '-=' ||
          two == '*=' ||
          two == '%=' ||
          two == '&=' ||
          two == '|=' ||
          two == '^=' ||
          two == '++' ||
          two == '--')
        size = 2;
    }
    feToken(source.substring(i, i + size), 0);
    i += size;
  }
  feToken('', 0);
  feAt = 0;
}

String fePeek() {
  return feTokens[feAt];
}

bool feIs(String text) {
  return feKinds[feAt] != 3 && fePeek() == text;
}

bool feTake(String text) {
  if (feIs(text)) {
    feAt++;
    return true;
  }
  return false;
}

void feExpect(String text) {
  if (!feTake(text)) feError('expected ' + text);
}

String feName() {
  if (feKinds[feAt] != 1) feError('expected name');
  var name = fePeek();
  feAt++;
  return name;
}

int feClassId(String name) {
  for (var i = 0; i < feClassNames.length; i++) {
    if (feClassNames[i] == name) return i;
  }
  return -1;
}

bool feClassType(int type) {
  return type >= tClass && type < tClass + feClassNames.length;
}

int feField(int owner, String name) {
  for (var i = 0; i < feFieldNames.length; i++) {
    if (feFieldClasses[i] == owner && feFieldNames[i] == name) return i;
  }
  feError('unknown field ' + feClassNames[owner] + '.' + name);
  return 0;
}

void feDiscoverClasses() {
  for (var i = 0; i < feTokens.length - 1; i++) {
    if (feKinds[i] == 1 && feTokens[i] == 'class') {
      feClassNames.add(feTokens[i + 1]);
      feClassFieldCounts.add(0);
      feClassConstructors.add(-1);
      classSizes.add(16);
      classPointerMasks.add(0);
    }
  }
}

bool feTypeStart() {
  return feIs('int') ||
      feIs('String') ||
      feIs('bool') ||
      feIs('void') ||
      feIs('List') ||
      feIs('dynamic') ||
      feClassId(fePeek()) >= 0;
}

int feType() {
  if (feTake('int')) return tInt;
  if (feTake('String')) return tString;
  if (feTake('bool')) return tBool;
  if (feTake('void')) return tVoid;
  if (feTake('dynamic')) return tInt;
  if (feTake('List')) {
    var element = tInt;
    if (feTake('<')) {
      element = feType();
      feExpect('>');
    }
    return tList + element;
  }
  var owner = feClassId(fePeek());
  if (owner >= 0) {
    feAt++;
    return tClass + owner;
  }
  feError('unsupported type ' + fePeek());
  return tInt;
}

void feSkipGroup(String open, String close) {
  feExpect(open);
  var depth = 1;
  while (depth > 0 && !feIs('')) {
    if (feTake(open)) {
      depth++;
    } else if (feTake(close)) {
      depth--;
    } else {
      feAt++;
    }
  }
}

void feSkipExpression() {
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  while (!feIs('')) {
    if (feIs(';') && parens == 0 && brackets == 0 && braces == 0) return;
    if (feKinds[feAt] != 3) {
      if (feIs('(')) parens++;
      if (feIs(')')) parens--;
      if (feIs('[')) brackets++;
      if (feIs(']')) brackets--;
      if (feIs('{')) braces++;
      if (feIs('}')) braces--;
    }
    feAt++;
  }
}

void feNativeTypedef() {
  var name = feName();
  feExpect('=');
  feExpect('Int64');
  feExpect('Function');
  feExpect('(');
  var count = 0;
  while (!feIs(')')) {
    feExpect('Int64');
    if (feKinds[feAt] == 1) feName();
    count++;
    if (!feTake(',')) break;
  }
  feExpect(')');
  feExpect(';');
  if (count > 8) feError('FFI callbacks support up to eight Int64 parameters');
  feNativeNames.add(name);
  feNativeParams.add(count);
}

void feFunctionTail() {
  if (feIs('{'))
    feSkipGroup('{', '}');
  else if (feTake('=>')) {
    feSkipExpression();
    feExpect(';');
  } else
    feExpect(';');
}

void feFunctionSignature(
  String name,
  int type,
  int owner,
  bool constructor,
  bool external,
) {
  var id = functions.length;
  var paramStart = feParamNames.length;
  var count = 0;
  if (owner >= 0) {
    feParamNames.add('this');
    feParamTypes.add(tClass + owner);
    feParamFields.add(-1);
    count++;
  }
  while (!feIs(')')) {
    feTake('final');
    var paramType = tInt;
    var paramName = '';
    var field = -1;
    if (constructor && feTake('this')) {
      feExpect('.');
      paramName = feName();
      var entry = feField(owner, paramName);
      paramType = feFieldTypes[entry];
      field = feFieldIndices[entry];
    } else {
      paramType = feType();
      paramName = feName();
    }
    if (!external) {
      feParamNames.add(paramName);
      feParamTypes.add(paramType);
      feParamFields.add(field);
    }
    count++;
    if (!feTake(',')) break;
  }
  feExpect(')');
  if (external) {
    feExpect(';');
    return;
  }
  var parameterTypes = <int>[];
  for (var p = 0; p < count; p++) {
    parameterTypes.add(feParamTypes[paramStart + p]);
  }
  functions.add(
    FunctionInfo(name, 0, count, count, type, parameterTypes, <int>[]),
  );
  feParamStarts.add(paramStart);
  feBodies.add(feAt);
  feOwners.add(owner);
  if (constructor) {
    feConstructors.add(1);
    feClassConstructors[owner] = id;
  } else {
    feConstructors.add(0);
  }
  if (!constructor && feIs(';')) feError('expected function body');
  feFunctionTail();
}

void feClassSignature() {
  var name = feName();
  var owner = feClassId(name);
  feExpect('{');
  var body = feAt;
  while (!feIs('}')) {
    feTake('final');
    if (feIs(name) && feTokens[feAt + 1] == '(') {
      feAt++;
      feSkipGroup('(', ')');
      feFunctionTail();
    } else {
      var type = feType();
      var field = feName();
      if (feIs('(')) {
        feSkipGroup('(', ')');
        feFunctionTail();
      } else {
        feExpect(';');
        var index = feClassFieldCounts[owner];
        feClassFieldCounts[owner] = index + 1;
        classSizes[owner] = 16 + (index + 1) * 8;
        if (type == tString || type >= tList) {
          classPointerMasks[owner] = classPointerMasks[owner] | (1 << index);
        }
        feFieldNames.add(field);
        feFieldTypes.add(type);
        feFieldClasses.add(owner);
        feFieldIndices.add(index);
      }
    }
  }
  feAt = body;
  while (!feIs('}')) {
    feTake('final');
    if (feIs(name) && feTokens[feAt + 1] == '(') {
      feAt += 2;
      feFunctionSignature(name + '.new', tClass + owner, owner, true, false);
    } else {
      var type = feType();
      var member = feName();
      if (feTake('(')) {
        feFunctionSignature(name + '.' + member, type, owner, false, false);
      } else {
        feExpect(';');
      }
    }
  }
  feExpect('}');
}

void feSignatures() {
  while (!feIs('')) {
    if (feTake('class')) {
      feClassSignature();
      continue;
    }
    if (feTake('typedef')) {
      feNativeTypedef();
      continue;
    }
    if (feTake('import') || feTake('export') || feTake('library')) {
      while (!feIs(';') && !feIs('')) feAt++;
      feExpect(';');
      continue;
    }
    while (feTake('@')) {
      feName();
      while (feTake('.')) feName();
      if (feIs('(')) feSkipGroup('(', ')');
    }
    var external = feTake('external');
    var inferred = false;
    if (feTake('var')) {
      inferred = true;
    } else {
      feTake('const');
      feTake('final');
    }
    var type = tInt;
    if (feTypeStart()) {
      type = feType();
    } else {
      inferred = true;
    }
    var name = feName();
    if (feTake('(')) {
      feFunctionSignature(name, type, -1, false, external);
    } else {
      globalNames.add(name);
      globalTypes.add(type);
      if (inferred) globalTypes[globalTypes.length - 1] = 0;
      if (feTake('=')) {
        feGlobalValues.add(feAt);
        feSkipExpression();
      } else {
        feGlobalValues.add(-1);
      }
      feExpect(';');
    }
  }
}

void feEmit(int op) {
  var type = tVoid;
  if (op >= opAdd && op <= opBitNot) type = tInt;
  if (op >= opEq && op <= opGe || op == opNot) type = tBool;
  ir.add(op);
  irTypes.add(type);
}

void feWord(int value) {
  ir.add(value);
  irTypes.add(tVoid);
}

void feOperand(int op, int value) {
  var position = ir.length;
  feEmit(op);
  feWord(value);
  if (op == opInt) irTypes[position] = tInt;
  if (op == opString) irTypes[position] = tString;
  if (op == opDescriptor) irTypes[position] = tPointer;
  if (op == opLoadLocal) irTypes[position] = feSlotTypes[value];
  if (op == opLoadGlobal) irTypes[position] = globalTypes[value];
}

void feInteger(int value, int type) {
  feOperand(opInt, value);
  irTypes[ir.length - 2] = type;
}

void feDuplicate(int type) {
  feEmit(opDup);
  irTypes[ir.length - 1] = type;
}

int feBuiltinType(int id) {
  if (id == bIntToString ||
      id == bStringConcat ||
      id == bStringSubstring ||
      id == bStringFromCodes ||
      id == bHostRead ||
      id == bHostStdPath)
    return tString;
  if (id == bStringEqual || id == bStringStartsWith || id == bStringEndsWith)
    return tBool;
  if (id == bStringLength ||
      id == bStringCodeUnit ||
      id == bStringIndexOf ||
      id == bStringLastIndexOf ||
      id == bIntParse ||
      id == bListLength ||
      id == bHostTarget ||
      id == bNativeLoad64 ||
      id == bNativeLoad8 ||
      id == bNativeSyscall ||
      id == bNativeTarget)
    return tInt;
  if (id == bArguments) return tList + tString;
  return tVoid;
}

void feBuiltinTyped(int id, int count, int type) {
  feEmit(opBuiltin);
  irTypes[ir.length - 1] = type;
  feWord(id);
  feWord(count);
}

void feBuiltin(int id, int count) {
  feBuiltinTyped(id, count, feBuiltinType(id));
}

void feCall(int function, int count) {
  feEmit(opCall);
  irTypes[ir.length - 1] = functions[function].result;
  feWord(function);
  feWord(count);
}

int feJump(int op) {
  feOperand(op, 0);
  return ir.length - 1;
}

void fePatch(int position, int target) {
  ir[position] = target;
}

int feString(String text) {
  for (var i = 0; i < strings.length; i++) {
    if (strings[i] == text) return i;
  }
  strings.add(text);
  return strings.length - 1;
}

int feLocal(String name) {
  for (var i = feLocalNames.length - 1; i >= 0; i--) {
    if (feLocalNames[i] == name) return i;
  }
  return -1;
}

int feGlobal(String name) {
  for (var i = 0; i < globalNames.length; i++) {
    if (globalNames[i] == name) return i;
  }
  return -1;
}

int feFindFunction(String name) {
  for (var i = 1; i < functions.length; i++) {
    if (functions[i].name == name) return i;
  }
  return -1;
}

int feVariableType(String name) {
  var local = feLocal(name);
  if (local >= 0) return feLocalTypes[local];
  var global = feGlobal(name);
  if (global >= 0) return globalTypes[global];
  feError('unknown variable ' + name);
  return tInt;
}

void feLoad(String name) {
  var local = feLocal(name);
  if (local >= 0) {
    feOperand(opLoadLocal, feLocalSlots[local]);
    return;
  }
  var global = feGlobal(name);
  if (global >= 0) {
    feOperand(opLoadGlobal, global);
    return;
  }
  feError('unknown variable ' + name);
}

void feStore(String name) {
  var local = feLocal(name);
  if (local >= 0) {
    feOperand(opStoreLocal, feLocalSlots[local]);
    return;
  }
  var global = feGlobal(name);
  if (global >= 0) {
    feOperand(opStoreGlobal, global);
    return;
  }
  feError('unknown variable ' + name);
}

int feTemp(int type) {
  var slot = feNextLocal;
  feNextLocal++;
  feSlotTypes.add(type);
  return slot;
}

void feScopeEnd(int start) {
  while (feLocalNames.length > start) {
    feLocalNames.removeLast();
    feLocalTypes.removeLast();
    feLocalSlots.removeLast();
  }
}

int fePrecedence(String op) {
  if (op == '|') return 1;
  if (op == '^') return 2;
  if (op == '&') return 3;
  if (op == '==' || op == '!=') return 4;
  if (op == '<' || op == '<=' || op == '>' || op == '>=') return 5;
  if (op == '<<' || op == '>>' || op == '>>>') return 6;
  if (op == '+' || op == '-') return 7;
  if (op == '*' || op == '~/' || op == '%') return 8;
  return 0;
}

int feBinaryOp(String op) {
  if (op == '+') return opAdd;
  if (op == '-') return opSub;
  if (op == '*') return opMul;
  if (op == '~/') return opDiv;
  if (op == '%') return opMod;
  if (op == '&') return opAnd;
  if (op == '|') return opOr;
  if (op == '^') return opXor;
  if (op == '<<') return opShl;
  if (op == '>>') return opShr;
  if (op == '>>>') return opUshr;
  if (op == '==') return opEq;
  if (op == '!=') return opNe;
  if (op == '<') return opLt;
  if (op == '<=') return opLe;
  if (op == '>') return opGt;
  if (op == '>=') return opGe;
  feError('unsupported operator ' + op);
  return opAdd;
}

int feCombine(String op, int left, int right) {
  if (op == '+' && left == tString && right == tString) {
    feBuiltin(bStringConcat, 2);
    return tString;
  }
  if ((op == '==' || op == '!=') && left == tString && right == tString) {
    feBuiltin(bStringEqual, 2);
    if (op == '!=') feEmit(opNot);
    return tBool;
  }
  feEmit(feBinaryOp(op));
  if (op == '==' ||
      op == '!=' ||
      op == '<' ||
      op == '<=' ||
      op == '>' ||
      op == '>=')
    return tBool;
  return tInt;
}

int feArgumentList() {
  feExpect('(');
  var count = 0;
  while (!feIs(')')) {
    feExpression();
    count++;
    if (!feTake(',')) break;
  }
  feExpect(')');
  return count;
}

int feNamedCall(String name) {
  if (name == 'print') {
    feExpect('(');
    var type = feExpression();
    feTake(',');
    feExpect(')');
    if (type == tString)
      feBuiltin(bPrintString, 1);
    else if (type == tBool)
      feBuiltin(bPrintBool, 1);
    else
      feBuiltin(bPrintInt, 1);
    return tVoid;
  }
  var builtin = 0;
  var result = tInt;
  if (name == 'hostRead') {
    builtin = bHostRead;
    result = tString;
  }
  if (name == 'hostWrite') {
    builtin = bHostWrite;
    result = tVoid;
  }
  if (name == 'hostFinish') {
    builtin = bHostFinish;
    result = tVoid;
  }
  if (name == 'hostExit') {
    builtin = bHostExit;
    result = tVoid;
  }
  if (name == 'hostStdPath') {
    builtin = bHostStdPath;
    result = tString;
  }
  if (name == 'nativeLoad64') builtin = bNativeLoad64;
  if (name == 'nativeStore64') {
    builtin = bNativeStore64;
    result = tVoid;
  }
  if (name == 'nativeLoad8') builtin = bNativeLoad8;
  if (name == 'nativeStore8') {
    builtin = bNativeStore8;
    result = tVoid;
  }
  if (name == 'nativeSyscall') builtin = bNativeSyscall;
  if (name == 'nativeTarget') builtin = bNativeTarget;
  if (name == 'hostTarget') builtin = bHostTarget;
  var count = feArgumentList();
  if (builtin != 0) {
    feBuiltin(builtin, count);
    return result;
  }
  var function = feFindFunction(name);
  if (function < 0) {
    feError('unknown function ' + name);
    return tInt;
  }
  if (functions[function].parameters != count)
    feError('argument count for ' + name);
  feCall(function, count);
  return functions[function].result;
}

int feListLiteral(int element) {
  feExpect('[');
  var allocation = ir.length;
  var duplicates = <int>[];
  feBuiltinTyped(bListNew, 0, tList + element);
  while (!feIs(']')) {
    duplicates.add(ir.length);
    feDuplicate(tList + element);
    var valueType = feExpression();
    if (element == 0) element = valueType;
    feBuiltin(bListAdd, 2);
    feEmit(opPop);
    if (!feTake(',')) break;
  }
  feExpect(']');
  if (element == 0) element = tInt;
  var type = tList + element;
  irTypes[allocation] = type;
  for (var i = 0; i < duplicates.length; i++) irTypes[duplicates[i]] = type;
  return type;
}

int fePointerFromFunction() {
  if (imageKind == 0 || feInitializingGlobal < 0) {
    feError(
      'FFI callback bindings require library output and a top-level binding',
    );
  }
  feExpect('.');
  feExpect('fromFunction');
  feExpect('<');
  var nativeName = feName();
  feExpect('>');
  var native = -1;
  for (var i = 0; i < feNativeNames.length; i++) {
    if (feNativeNames[i] == nativeName) native = i;
  }
  if (native < 0) feError('unknown FFI signature ' + nativeName);
  feExpect('(');
  var implementation = feName();
  var function = feFindFunction(implementation);
  if (function < 0) feError('unknown callback function ' + implementation);
  if (functions[function].parameters != feNativeParams[native]) {
    feError('FFI parameter count does not match ' + implementation);
  }
  if (feTake(',') && !feIs(')')) {
    feExpression();
    feEmit(opPop);
    feTake(',');
  }
  feExpect(')');
  exportNames.add(globalNames[feInitializingGlobal]);
  exportFunctions.add(function);
  exportParameters.add(feNativeParams[native]);
  feInteger(0, tPointer);
  return tPointer;
}

int fePrimary() {
  var type = tInt;
  if (feKinds[feAt] == 2) {
    feOperand(opInt, int.parse(fePeek()));
    feAt++;
  } else if (feKinds[feAt] == 3) {
    var value = fePeek();
    feAt++;
    while (feKinds[feAt] == 3) {
      value = value + fePeek();
      feAt++;
    }
    feOperand(opString, feString(value));
    type = tString;
  } else if (feTake('true')) {
    feInteger(1, tBool);
    type = tBool;
  } else if (feTake('false') || feTake('null')) {
    feInteger(0, tBool);
    type = tBool;
  } else if (feTake('(')) {
    type = feExpression();
    feExpect(')');
  } else if (feIs('[')) {
    type = feListLiteral(0);
  } else if (feTake('<')) {
    var element = feType();
    feExpect('>');
    type = feListLiteral(element);
  } else {
    var name = feName();
    var owner = feClassId(name);
    if (owner >= 0 && feIs('(')) {
      feOperand(opDescriptor, owner);
      feBuiltinTyped(bObjectNew, 1, tClass + owner);
      var count = feArgumentList();
      var constructor = feClassConstructors[owner];
      if (constructor >= 0) {
        if (functions[constructor].parameters != count + 1)
          feError('constructor argument count for ' + name);
        feCall(constructor, count + 1);
      } else if (count != 0) {
        feError('constructor argument count for ' + name);
      }
      type = tClass + owner;
    } else if (name == 'Pointer' && feIs('.')) {
      type = fePointerFromFunction();
    } else if ((name == 'List' || name == 'String' || name == 'int') &&
        (feIs('.') || feIs('<'))) {
      var element = tInt;
      if (feTake('<')) {
        element = feType();
        feExpect('>');
      }
      feExpect('.');
      var member = feName();
      if (name == 'List' && member == 'filled') {
        feExpect('(');
        feExpression();
        feExpect(',');
        var valueType = feExpression();
        if (feTake(',') && !feIs(')')) {
          feExpect('growable');
          feExpect(':');
          feExpression();
          feEmit(opPop);
          feTake(',');
        }
        feExpect(')');
        type = tList + element;
        if (element == tInt && valueType != tInt) type = tList + valueType;
        feBuiltinTyped(bListFilled, 2, type);
      } else if (name == 'String' && member == 'fromCharCodes') {
        var count = feArgumentList();
        feBuiltin(bStringFromCodes, count);
        type = tString;
      } else if (name == 'int' && member == 'parse') {
        var count = feArgumentList();
        feBuiltin(bIntParse, count);
        type = tInt;
      } else {
        feError('unsupported static call ' + name + '.' + member);
      }
    } else if (feIs('(')) {
      type = feNamedCall(name);
    } else {
      type = feVariableType(name);
      feLoad(name);
    }
  }
  while (true) {
    if (feTake('[')) {
      feExpression();
      feExpect(']');
      if (type == tString) {
        feDuplicate(tInt);
        feOperand(opInt, 1);
        feEmit(opAdd);
        feBuiltin(bStringSubstring, 3);
        type = tString;
      } else {
        type -= tList;
        feBuiltinTyped(bListGet, 2, type);
      }
    } else if (feTake('.')) {
      var member = feName();
      if (feClassType(type)) {
        var owner = type - tClass;
        if (feIs('(')) {
          var function = feFindFunction(feClassNames[owner] + '.' + member);
          if (function < 0) feError('unknown method ' + member);
          var count = feArgumentList() + 1;
          if (functions[function].parameters != count)
            feError('method argument count for ' + member);
          feCall(function, count);
          type = functions[function].result;
        } else {
          var field = feField(owner, member);
          feOperand(opInt, feFieldIndices[field]);
          type = feFieldTypes[field];
          feBuiltinTyped(bObjectGet, 2, type);
        }
      } else if (member == 'length' ||
          member == 'isEmpty' ||
          member == 'isNotEmpty') {
        if (type == tString)
          feBuiltin(bStringLength, 1);
        else
          feBuiltin(bListLength, 1);
        type = tInt;
        if (member != 'length') {
          feOperand(opInt, 0);
          if (member == 'isEmpty')
            feEmit(opEq);
          else
            feEmit(opNe);
          type = tBool;
        }
      } else if (member == 'first' || member == 'last') {
        if (member == 'first')
          feOperand(opInt, 0);
        else {
          feDuplicate(type);
          feBuiltin(bListLength, 1);
          feOperand(opInt, 1);
          feEmit(opSub);
        }
        type -= tList;
        feBuiltinTyped(bListGet, 2, type);
      } else if (member == 'toString') {
        feExpect('(');
        feExpect(')');
        if (type != tString) feBuiltin(bIntToString, 1);
        type = tString;
      } else if (type >= tList) {
        var count = feArgumentList();
        if (member == 'add') {
          feBuiltin(bListAdd, count + 1);
          type = tVoid;
        } else if (member == 'removeLast') {
          type -= tList;
          feBuiltinTyped(bListRemoveLast, count + 1, type);
        } else if (member == 'clear') {
          feBuiltin(bListClear, count + 1);
          type = tVoid;
        } else {
          feError('unsupported List method ' + member);
        }
      } else if (type == tString) {
        var count = feArgumentList();
        if (member == 'codeUnitAt') {
          feBuiltin(bStringCodeUnit, count + 1);
          type = tInt;
        } else if (member == 'substring') {
          if (count == 1) feOperand(opInt, -1);
          feBuiltin(bStringSubstring, 3);
          type = tString;
        } else if (member == 'indexOf' || member == 'lastIndexOf') {
          if (count == 1) {
            if (member == 'indexOf')
              feOperand(opInt, 0);
            else
              feOperand(opInt, -1);
          }
          if (member == 'indexOf')
            feBuiltin(bStringIndexOf, 3);
          else
            feBuiltin(bStringLastIndexOf, 3);
          type = tInt;
        } else if (member == 'startsWith') {
          if (count == 1) feOperand(opInt, 0);
          feBuiltin(bStringStartsWith, 3);
          type = tBool;
        } else if (member == 'endsWith') {
          feBuiltin(bStringEndsWith, count + 1);
          type = tBool;
        } else {
          feError('unsupported String method ' + member);
        }
      } else {
        feError('unsupported member ' + member);
      }
    } else {
      break;
    }
  }
  return type;
}

int feUnary() {
  if (feTake('-')) {
    feUnary();
    feEmit(opNeg);
    return tInt;
  }
  if (feTake('+')) return feUnary();
  if (feTake('!')) {
    feUnary();
    feEmit(opNot);
    return tBool;
  }
  if (feTake('~')) {
    feUnary();
    feEmit(opBitNot);
    return tInt;
  }
  if (feTake('++') || feTake('--')) {
    var op = feTokens[feAt - 1];
    var name = feName();
    feLoad(name);
    feOperand(opInt, 1);
    if (op == '++')
      feEmit(opAdd);
    else
      feEmit(opSub);
    feDuplicate(tInt);
    feStore(name);
    return tInt;
  }
  return fePrimary();
}

int feBinary(int minimum) {
  var type = feUnary();
  while (feKinds[feAt] != 3 && fePrecedence(fePeek()) >= minimum) {
    var op = fePeek();
    var precedence = fePrecedence(op);
    feAt++;
    var right = feBinary(precedence + 1);
    type = feCombine(op, type, right);
  }
  return type;
}

int feAnd() {
  var type = feBinary(1);
  while (feTake('&&')) {
    feDuplicate(tBool);
    var end = feJump(opJumpFalse);
    feEmit(opPop);
    feBinary(1);
    fePatch(end, ir.length);
    type = tBool;
  }
  return type;
}

int feOr() {
  var type = feAnd();
  while (feTake('||')) {
    feDuplicate(tBool);
    var rhs = feJump(opJumpFalse);
    var end = feJump(opJump);
    fePatch(rhs, ir.length);
    feEmit(opPop);
    feAnd();
    fePatch(end, ir.length);
    type = tBool;
  }
  return type;
}

bool feAssignmentOp(String op) {
  return op == '=' ||
      op == '+=' ||
      op == '-=' ||
      op == '*=' ||
      op == '~/=' ||
      op == '%=' ||
      op == '&=' ||
      op == '|=' ||
      op == '^=' ||
      op == '<<=' ||
      op == '>>=' ||
      op == '>>>=' ||
      op == '++' ||
      op == '--';
}

int feLvalueEnd() {
  if (feKinds[feAt] != 1) return -1;
  var end = feAt + 1;
  while (true) {
    if (feTokens[end] == '[') {
      var depth = 1;
      end++;
      while (depth > 0 && feTokens[end] != '') {
        if (feKinds[end] != 3) {
          if (feTokens[end] == '[') depth++;
          if (feTokens[end] == ']') depth--;
        }
        end++;
      }
    } else if (feTokens[end] == '.' && feKinds[end + 1] == 1) {
      end += 2;
    } else
      break;
  }
  if (feAssignmentOp(feTokens[end])) return end;
  return -1;
}

int feExpression() {
  var end = feLvalueEnd();
  if (end >= 0) {
    var name = feName();
    var type = feVariableType(name);
    var container = 0;
    var receiver = -1;
    var index = -1;
    if (feAt < end) {
      feLoad(name);
      while (feAt < end) {
        var receiverType = type;
        var current = 1;
        if (feTake('[')) {
          feExpression();
          feExpect(']');
          type -= tList;
        } else {
          feExpect('.');
          var field = feField(type - tClass, feName());
          feOperand(opInt, feFieldIndices[field]);
          type = feFieldTypes[field];
          current = 2;
        }
        if (feAt == end) {
          container = current;
          index = feTemp(tInt);
          feOperand(opStoreLocal, index);
          receiver = feTemp(receiverType);
          feOperand(opStoreLocal, receiver);
        } else {
          if (current == 1)
            feBuiltinTyped(bListGet, 2, type);
          else
            feBuiltinTyped(bObjectGet, 2, type);
        }
      }
    }
    var op = fePeek();
    feAt++;
    if (op != '=') {
      if (container != 0) {
        feOperand(opLoadLocal, receiver);
        feOperand(opLoadLocal, index);
        if (container == 1)
          feBuiltinTyped(bListGet, 2, type);
        else
          feBuiltinTyped(bObjectGet, 2, type);
      } else {
        feLoad(name);
      }
    }
    var postfix = op == '++' || op == '--';
    var previous = -1;
    if (postfix) {
      previous = feTemp(type);
      feDuplicate(type);
      feOperand(opStoreLocal, previous);
      feOperand(opInt, 1);
      if (op == '++')
        feEmit(opAdd);
      else
        feEmit(opSub);
    } else {
      var right = feExpression();
      if (op != '=') feCombine(op.substring(0, op.length - 1), type, right);
    }
    if (container != 0) {
      var value = feTemp(type);
      feOperand(opStoreLocal, value);
      feOperand(opLoadLocal, receiver);
      feOperand(opLoadLocal, index);
      feOperand(opLoadLocal, value);
      if (container == 1)
        feBuiltinTyped(bListSet, 3, type);
      else
        feBuiltinTyped(bObjectSet, 3, type);
    } else {
      feDuplicate(type);
      feStore(name);
    }
    if (postfix) {
      feEmit(opPop);
      feOperand(opLoadLocal, previous);
    }
    return type;
  }
  var type = feOr();
  if (feTake('?')) {
    var otherwise = feJump(opJumpFalse);
    var thenType = feExpression();
    feExpect(':');
    var done = feJump(opJump);
    fePatch(otherwise, ir.length);
    feExpression();
    fePatch(done, ir.length);
    return thenType;
  }
  return type;
}

bool feDeclarationStart() {
  return feIs('var') || feIs('final') || feIs('const') || feTypeStart();
}

void feDeclaration() {
  var inferred = false;
  if (feTake('var'))
    inferred = true;
  else {
    feTake('final');
    feTake('const');
  }
  var type = 0;
  if (feTypeStart())
    type = feType();
  else
    inferred = true;
  var name = feName();
  var value = tInt;
  if (feTake('='))
    value = feExpression();
  else
    feOperand(opInt, 0);
  if (inferred || type == 0) type = value;
  var slot = feTemp(type);
  feLocalNames.add(name);
  feLocalTypes.add(type);
  feLocalSlots.add(slot);
  feOperand(opStoreLocal, slot);
}

void feLoopEnd(int breakBase, int continueBase, int end, int repeat) {
  while (feBreaks.length > breakBase) fePatch(feBreaks.removeLast(), end);
  while (feContinues.length > continueBase)
    fePatch(feContinues.removeLast(), repeat);
  feLoopBreaks.removeLast();
  feLoopContinues.removeLast();
}

void feStatement() {
  if (feTake('{')) {
    var scope = feLocalNames.length;
    while (!feIs('}')) feStatement();
    feExpect('}');
    feScopeEnd(scope);
    return;
  }
  if (feTake(';')) return;
  if (feTake('return')) {
    if (feIs(';') && feConstructors[feFunction] == 1)
      feOperand(opLoadLocal, 0);
    else if (feIs(';'))
      feInteger(0, tVoid);
    else
      feExpression();
    feExpect(';');
    feEmit(opReturn);
    return;
  }
  if (feTake('if')) {
    feExpect('(');
    feExpression();
    feExpect(')');
    var otherwise = feJump(opJumpFalse);
    feStatement();
    if (feTake('else')) {
      var done = feJump(opJump);
      fePatch(otherwise, ir.length);
      feStatement();
      fePatch(done, ir.length);
    } else {
      fePatch(otherwise, ir.length);
    }
    return;
  }
  if (feTake('while')) {
    var repeat = ir.length;
    feExpect('(');
    feExpression();
    feExpect(')');
    var exit = feJump(opJumpFalse);
    var breakBase = feBreaks.length;
    var continueBase = feContinues.length;
    feLoopBreaks.add(breakBase);
    feLoopContinues.add(continueBase);
    feStatement();
    feOperand(opJump, repeat);
    fePatch(exit, ir.length);
    feLoopEnd(breakBase, continueBase, ir.length, repeat);
    return;
  }
  if (feTake('for')) {
    var scope = feLocalNames.length;
    feExpect('(');
    if (!feIs(';')) {
      if (feDeclarationStart())
        feDeclaration();
      else {
        feExpression();
        feEmit(opPop);
      }
    }
    feExpect(';');
    var repeat = ir.length;
    if (!feIs(';'))
      feExpression();
    else
      feInteger(1, tBool);
    feExpect(';');
    var exit = feJump(opJumpFalse);
    var update = feAt;
    var depth = 0;
    while (!feIs('') && !(feIs(')') && depth == 0)) {
      if (feTake('('))
        depth++;
      else if (feTake(')'))
        depth--;
      else
        feAt++;
    }
    var updateEnd = feAt;
    feExpect(')');
    var breakBase = feBreaks.length;
    var continueBase = feContinues.length;
    feLoopBreaks.add(breakBase);
    feLoopContinues.add(continueBase);
    feStatement();
    var bodyEnd = feAt;
    var updateTarget = ir.length;
    feAt = update;
    if (feAt < updateEnd) {
      feExpression();
      feEmit(opPop);
    }
    feAt = bodyEnd;
    feOperand(opJump, repeat);
    fePatch(exit, ir.length);
    feLoopEnd(breakBase, continueBase, ir.length, updateTarget);
    feScopeEnd(scope);
    return;
  }
  if (feTake('break')) {
    if (feLoopBreaks.isEmpty) feError('break outside loop');
    feBreaks.add(feJump(opJump));
    feExpect(';');
    return;
  }
  if (feTake('continue')) {
    if (feLoopContinues.isEmpty) feError('continue outside loop');
    feContinues.add(feJump(opJump));
    feExpect(';');
    return;
  }
  if (feDeclarationStart()) {
    feDeclaration();
    feExpect(';');
    return;
  }
  feExpression();
  feEmit(opPop);
  feExpect(';');
}

void parseSource(String source) {
  ir.clear();
  irTypes.clear();
  functions.clear();
  feSlotTypes = <int>[];
  globalNames.clear();
  globalTypes.clear();
  strings.clear();
  classSizes.clear();
  classPointerMasks.clear();
  feClassNames.clear();
  feClassFieldCounts.clear();
  feClassConstructors.clear();
  feFieldNames.clear();
  feFieldTypes.clear();
  feFieldClasses.clear();
  feFieldIndices.clear();
  feOwners.clear();
  feConstructors.clear();
  feParamFields.clear();
  exportNames.clear();
  exportFunctions.clear();
  exportParameters.clear();
  feNativeNames.clear();
  feNativeParams.clear();
  feInitializingGlobal = -1;
  feBodies.clear();
  feGlobalValues.clear();
  feParamStarts.clear();
  feParamNames.clear();
  feParamTypes.clear();
  feLocalNames.clear();
  feLocalTypes.clear();
  feLocalSlots.clear();
  feBreaks.clear();
  feContinues.clear();
  feLoopBreaks.clear();
  feLoopContinues.clear();
  functions.add(FunctionInfo('__init', 0, 0, 0, tVoid, <int>[], <int>[]));
  feBodies.add(0);
  feParamStarts.add(0);
  feOwners.add(-1);
  feConstructors.add(0);
  feScan(source);
  feDiscoverClasses();
  feSignatures();
  feNextLocal = 0;
  feFunction = 0;
  for (var i = 0; i < globalNames.length; i++) {
    feInitializingGlobal = i;
    if (feGlobalValues[i] < 0) {
      feOperand(opInt, 0);
    } else {
      feAt = feGlobalValues[i];
      var type = feExpression();
      if (globalTypes[i] == 0) globalTypes[i] = type;
    }
    feOperand(opStoreGlobal, i);
  }
  feInitializingGlobal = -1;
  feInteger(0, tVoid);
  feEmit(opReturn);
  functions[0].locals = feNextLocal;
  functions[0].localTypes = feSlotTypes;
  for (var f = 1; f < functions.length; f++) {
    feFunction = f;
    feAt = feBodies[f];
    functions[f].start = ir.length;
    feLocalNames.clear();
    feLocalTypes.clear();
    feLocalSlots.clear();
    feSlotTypes = <int>[];
    feNextLocal = 0;
    var start = feParamStarts[f];
    for (var p = 0; p < functions[f].parameters; p++) {
      feLocalNames.add(feParamNames[start + p]);
      feLocalTypes.add(feParamTypes[start + p]);
      feLocalSlots.add(feTemp(feParamTypes[start + p]));
    }
    if (feConstructors[f] == 1) {
      for (var p = 1; p < functions[f].parameters; p++) {
        var field = feParamFields[start + p];
        if (field >= 0) {
          feOperand(opLoadLocal, 0);
          feOperand(opInt, field);
          feOperand(opLoadLocal, p);
          feBuiltinTyped(bObjectSet, 3, feParamTypes[start + p]);
          feEmit(opPop);
        }
      }
      if (!feTake(';')) feStatement();
      feOperand(opLoadLocal, 0);
      feEmit(opReturn);
    } else if (feTake('=>')) {
      feExpression();
      feExpect(';');
      feEmit(opReturn);
    } else {
      feStatement();
      feInteger(0, functions[f].result);
      feEmit(opReturn);
    }
    functions[f].locals = feNextLocal;
    functions[f].localTypes = feSlotTypes;
  }
}
