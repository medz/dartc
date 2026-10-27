const int tVoid = 0;
const int tInt = 1;
const int tString = 2;
const int tBool = 3;
const int tPointer = 4;
const int tDynamic = 5;
const int tNull = 6;
const int tObject = 7;
const int tNum = 8;
const int tNever = 9;
const int tFunction = 10;

const int kNullable = 11;
const int kList = 12;
const int kClass = 13;
const int kFunction = 14;

class FunctionSignature {
  final int result;
  final List<int> parameters;
  final int required;

  FunctionSignature(this.result, this.parameters, this.required);
}

class DartType {
  int kind;
  int argument;
  int listType;
  int nullableType;

  DartType(this.kind, this.argument, this.listType, this.nullableType);
}

List<DartType> dartTypes = <DartType>[];
List<int> classDartTypes = <int>[];
List<FunctionSignature> functionSignatures = <FunctionSignature>[];

void resetTypes() {
  dartTypes.clear();
  classDartTypes.clear();
  functionSignatures.clear();
  var i = 0;
  while (i <= tFunction) {
    dartTypes.add(DartType(i, -1, -1, -1));
    i++;
  }
}

int functionType(int result, List<int> parameters, [int required = -1]) {
  if (required < 0) required = parameters.length;
  var type = tFunction + 1;
  while (type < dartTypes.length) {
    if (dartTypes[type].kind == kFunction) {
      var signature = functionSignatures[dartTypes[type].argument];
      if (signature.result == result &&
          signature.required == required &&
          signature.parameters.length == parameters.length) {
        var same = true;
        var p = 0;
        while (same && p < parameters.length) {
          same = signature.parameters[p] == parameters[p];
          p++;
        }
        if (same) return type;
      }
    }
    type++;
  }
  var owned = <int>[];
  for (var parameter in parameters) owned.add(parameter);
  var signature = functionSignatures.length;
  functionSignatures.add(FunctionSignature(result, owned, required));
  dartTypes.add(DartType(kFunction, signature, -1, -1));
  return type;
}

bool typeIsFunction(int type) => dartTypes[type].kind == kFunction;

FunctionSignature functionSignature(int type) {
  return functionSignatures[dartTypes[type].argument];
}

int listType(int element) {
  var item = dartTypes[element];
  if (item.listType < 0) {
    item.listType = dartTypes.length;
    dartTypes.add(DartType(kList, element, -1, -1));
  }
  return item.listType;
}

int classType(int classId) {
  while (classDartTypes.length <= classId) {
    var owner = classDartTypes.length;
    classDartTypes.add(dartTypes.length);
    dartTypes.add(DartType(kClass, owner, -1, -1));
  }
  return classDartTypes[classId];
}

bool typeIsList(int type) {
  return dartTypes[type].kind == kList;
}

bool typeIsClass(int type) {
  return dartTypes[type].kind == kClass;
}

int typeArgument(int type) {
  return dartTypes[type].argument;
}

bool typeIsReference(int type) {
  var kind = dartTypes[type].kind;
  if (kind == kNullable) return typeIsReference(dartTypes[type].argument);
  return kind == tString ||
      kind == tFunction ||
      kind == kList ||
      kind == kClass ||
      kind == kFunction;
}

int nullableType(int type) {
  if (type == tNever) return tNull;
  if (type == tDynamic || type == tNull || typeIsNullable(type)) return type;
  var item = dartTypes[type];
  if (item.nullableType < 0) {
    item.nullableType = dartTypes.length;
    dartTypes.add(DartType(kNullable, type, -1, -1));
  }
  return item.nullableType;
}

bool typeIsNullable(int type) => dartTypes[type].kind == kNullable;

int typeNonNullable(int type) {
  if (typeIsNullable(type)) return dartTypes[type].argument;
  return type;
}

bool typeCanBeNull(int type) {
  return type == tDynamic ||
      type == tVoid ||
      type == tNull ||
      typeIsNullable(type);
}

bool typeIsDisjoint(int left, int right) {
  if (left == tNever || right == tNever) return true;
  if (left == tNull) return !typeCanBeNull(right);
  if (right == tNull) return !typeCanBeNull(left);
  if (typeCanBeNull(left) && typeCanBeNull(right)) return false;
  left = typeNonNullable(left);
  right = typeNonNullable(right);
  if (typeIsSubtype(left, right) ||
      typeIsSubtype(right, left) ||
      left == tDynamic ||
      right == tDynamic ||
      left == tVoid ||
      right == tVoid ||
      left == tObject ||
      right == tObject ||
      left == tPointer ||
      right == tPointer) {
    return false;
  }
  return left == tInt ||
      left == tNum ||
      left == tString ||
      left == tBool ||
      right == tInt ||
      right == tNum ||
      right == tString ||
      right == tBool;
}

bool typeIsTagged(int type) {
  return type == tVoid ||
      type == tNum ||
      type == tNever ||
      type == tDynamic ||
      type == tNull ||
      type == tObject ||
      typeIsNullable(type) && !typeIsReference(type);
}

bool typeIsSubtype(int actual, int expected) {
  if (actual == expected ||
      actual == tNever ||
      expected == tDynamic ||
      expected == tVoid)
    return true;
  if (typeIsNullable(expected)) {
    var base = typeNonNullable(expected);
    if (base == tObject || actual == tNull) return true;
    return typeIsSubtype(typeNonNullable(actual), base);
  }
  if (actual == tDynamic ||
      actual == tVoid ||
      actual == tNull ||
      typeIsNullable(actual))
    return false;
  if (expected == tObject) return true;
  if (actual == tInt && expected == tNum) return true;
  if (typeIsFunction(actual)) {
    if (expected == tFunction) return true;
    if (typeIsFunction(expected)) {
      var source = functionSignature(actual);
      var target = functionSignature(expected);
      if (source.required > target.required ||
          source.parameters.length < target.parameters.length ||
          !typeIsSubtype(source.result, target.result))
        return false;
      var p = 0;
      while (p < target.parameters.length) {
        if (!typeIsSubtype(target.parameters[p], source.parameters[p]))
          return false;
        p++;
      }
      return true;
    }
  }
  if (typeIsList(actual) && typeIsList(expected)) {
    return typeIsSubtype(typeArgument(actual), typeArgument(expected));
  }
  return false;
}

int joinTypes(int left, int right) {
  if (left < 0) return right;
  if (left == tNever) return right;
  if (right == tNever) return left;
  if (left == right) return left;
  if (left == tVoid || right == tVoid) return tVoid;
  if (left == tDynamic || right == tDynamic) return tDynamic;
  if (typeIsFunction(left) && typeIsFunction(right)) {
    var a = functionSignature(left);
    var b = functionSignature(right);
    if (a.required != b.required) return tFunction;
    var count = a.parameters.length;
    if (b.parameters.length < count) count = b.parameters.length;
    var parameters = <int>[];
    var p = 0;
    while (p < count) {
      parameters.add(meetTypes(a.parameters[p], b.parameters[p]));
      p++;
    }
    return functionType(joinTypes(a.result, b.result), parameters, a.required);
  }
  if (typeIsSubtype(left, right)) return right;
  if (typeIsSubtype(right, left)) return left;
  if (left == tNull) return nullableType(right);
  if (right == tNull) return nullableType(left);
  if (typeIsNullable(left) || typeIsNullable(right)) {
    return nullableType(
      joinTypes(typeNonNullable(left), typeNonNullable(right)),
    );
  }
  if (typeIsList(left) && typeIsList(right)) {
    return listType(joinTypes(typeArgument(left), typeArgument(right)));
  }
  return tObject;
}

int meetTypes(int left, int right) {
  if (left == right) return left;
  if (left == tNever || right == tNever) return tNever;
  if (left == tVoid) return right;
  if (right == tVoid) return left;
  if (left == tDynamic) return right;
  if (right == tDynamic) return left;
  if (left == tNull) return typeCanBeNull(right) ? tNull : tNever;
  if (right == tNull) return typeCanBeNull(left) ? tNull : tNever;
  if (left == tObject) return typeNonNullable(right);
  if (right == tObject) return typeNonNullable(left);
  if (typeIsNullable(left) && typeArgument(left) == tObject) return right;
  if (typeIsNullable(right) && typeArgument(right) == tObject) return left;
  if (typeIsNullable(left) && typeIsNullable(right)) {
    return nullableType(meetTypes(typeArgument(left), typeArgument(right)));
  }
  if (typeIsNullable(left)) return meetTypes(typeArgument(left), right);
  if (typeIsNullable(right)) return meetTypes(left, typeArgument(right));
  if (typeIsFunction(left) && typeIsFunction(right)) {
    var a = functionSignature(left);
    var b = functionSignature(right);
    var count = a.parameters.length;
    if (b.parameters.length > count) count = b.parameters.length;
    var parameters = <int>[];
    var p = 0;
    while (p < count) {
      if (p >= a.parameters.length)
        parameters.add(b.parameters[p]);
      else if (p >= b.parameters.length)
        parameters.add(a.parameters[p]);
      else
        parameters.add(joinTypes(a.parameters[p], b.parameters[p]));
      p++;
    }
    var required = a.required;
    if (b.required < required) required = b.required;
    return functionType(meetTypes(a.result, b.result), parameters, required);
  }
  if (typeIsSubtype(left, right)) return left;
  if (typeIsSubtype(right, left)) return right;
  return tNever;
}
