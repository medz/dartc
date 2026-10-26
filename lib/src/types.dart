const int tVoid = 0;
const int tInt = 1;
const int tString = 2;
const int tBool = 3;
const int tPointer = 4;

const int kList = 5;
const int kClass = 6;

class DartType {
  int kind;
  int argument;
  int listType;

  DartType(this.kind, this.argument, this.listType);
}

List<DartType> dartTypes = <DartType>[];
List<int> classDartTypes = <int>[];

void resetTypes() {
  dartTypes.clear();
  classDartTypes.clear();
  var i = 0;
  while (i <= tPointer) {
    dartTypes.add(DartType(i, -1, -1));
    i++;
  }
}

int listType(int element) {
  var item = dartTypes[element];
  if (item.listType < 0) {
    item.listType = dartTypes.length;
    dartTypes.add(DartType(kList, element, -1));
  }
  return item.listType;
}

int classType(int classId) {
  while (classDartTypes.length <= classId) {
    var owner = classDartTypes.length;
    classDartTypes.add(dartTypes.length);
    dartTypes.add(DartType(kClass, owner, -1));
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
  return kind == tString || kind == kList || kind == kClass;
}
