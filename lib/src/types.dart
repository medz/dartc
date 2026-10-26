const int tVoid = 0;
const int tInt = 1;
const int tString = 2;
const int tBool = 3;
const int tPointer = 4;
const int tDynamic = 5;
const int tNull = 6;
const int tObject = 7;

const int kNullable = 8;
const int kList = 9;
const int kClass = 10;

class DartType {
  int kind;
  int argument;
  int listType;
  int nullableType;

  DartType(this.kind, this.argument, this.listType, this.nullableType);
}

List<DartType> dartTypes = <DartType>[];
List<int> classDartTypes = <int>[];

void resetTypes() {
  dartTypes.clear();
  classDartTypes.clear();
  var i = 0;
  while (i <= tObject) {
    dartTypes.add(DartType(i, -1, -1, -1));
    i++;
  }
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
  return kind == tString || kind == kList || kind == kClass;
}

int nullableType(int type) {
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

bool typeIsTagged(int type) {
  return type == tVoid ||
      type == tDynamic ||
      type == tNull ||
      type == tObject ||
      typeIsNullable(type) && !typeIsReference(type);
}

bool typeIsSubtype(int actual, int expected) {
  if (actual == expected || expected == tDynamic || expected == tVoid)
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
  if (typeIsList(actual) && typeIsList(expected)) {
    return typeIsSubtype(typeArgument(actual), typeArgument(expected));
  }
  return false;
}

int joinTypes(int left, int right) {
  if (left < 0) return right;
  if (left == right) return left;
  if (left == tDynamic || right == tDynamic) return tDynamic;
  if (left == tVoid || right == tVoid) return tVoid;
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
