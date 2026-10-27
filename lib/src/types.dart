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
const int kTypeParameter = 15;

class TypeParameterInfo {
  final int owner;
  final int ordinal;
  final String name;
  final bool bindsName;
  final bool hasBound;
  int bound = -1;
  int variance = 0;

  TypeParameterInfo(
    this.owner,
    this.ordinal,
    this.name,
    this.bindsName,
    this.hasBound,
  );
}

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
  bool containsParameters = false;

  DartType(this.kind, this.argument, this.listType, this.nullableType);
}

List<DartType> dartTypes = <DartType>[];
List<int> classDartTypes = <int>[];
List<FunctionSignature> functionSignatures = <FunctionSignature>[];
List<TypeParameterInfo> typeParameters = <TypeParameterInfo>[];

void resetTypes() {
  dartTypes.clear();
  classDartTypes.clear();
  functionSignatures.clear();
  typeParameters.clear();
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
  var item = DartType(kFunction, signature, -1, -1);
  item.containsParameters = typeContainsParameters(result);
  for (var parameter in parameters) {
    if (typeContainsParameters(parameter)) item.containsParameters = true;
  }
  dartTypes.add(item);
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
    var type = DartType(kList, element, -1, -1);
    type.containsParameters = item.containsParameters;
    dartTypes.add(type);
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
    var result = DartType(kNullable, type, -1, -1);
    result.containsParameters = item.containsParameters;
    dartTypes.add(result);
  }
  return item.nullableType;
}

bool typeIsNullable(int type) => dartTypes[type].kind == kNullable;

int typeNonNullable(int type) {
  if (typeIsNullable(type)) return dartTypes[type].argument;
  return type;
}

bool typeCanBeNull(int type) {
  if (type == tDynamic || type == tVoid || type == tNull) return true;
  var kind = dartTypes[type].kind;
  if (kind == kTypeParameter)
    return typeCanBeNull(typeParameterInfo(type).bound);
  return kind == kNullable;
}

bool typeIsDisjoint(int left, int right) {
  if (left == tNever || right == tNever) return true;
  if (typeIsParameter(left))
    return typeIsDisjoint(typeParameterInfo(left).bound, right);
  if (typeIsParameter(right))
    return typeIsDisjoint(left, typeParameterInfo(right).bound);
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
  if (type == tVoid ||
      type == tNum ||
      type == tNever ||
      type == tDynamic ||
      type == tNull ||
      type == tObject)
    return true;
  var kind = dartTypes[type].kind;
  return kind == kTypeParameter || kind == kNullable && !typeIsReference(type);
}

bool typeIsSubtype(int actual, int expected) {
  if (actual == expected ||
      actual == tNever ||
      expected == tDynamic ||
      expected == tVoid)
    return true;
  var expectedKind = dartTypes[expected].kind;
  if (expectedKind == kNullable) {
    var base = typeNonNullable(expected);
    if (base == tObject || actual == tNull) return true;
    return typeIsSubtype(typeNonNullable(actual), base);
  }
  var actualKind = dartTypes[actual].kind;
  if (actualKind == kTypeParameter)
    return typeIsSubtype(typeParameterInfo(actual).bound, expected);
  if (expectedKind == kTypeParameter) return false;
  if (actual == tDynamic ||
      actual == tVoid ||
      actual == tNull ||
      actualKind == kNullable)
    return false;
  if (expected == tObject) return true;
  if (actual == tInt && expected == tNum) return true;
  if (actualKind == kFunction) {
    if (expected == tFunction) return true;
    if (expectedKind == kFunction) {
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
  if (actualKind == kList && expectedKind == kList) {
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

bool typeIsParameter(int type) => dartTypes[type].kind == kTypeParameter;

TypeParameterInfo typeParameterInfo(int type) =>
    typeParameters[dartTypes[type].argument];

bool typeContainsParameters(int type) => dartTypes[type].containsParameters;

int newTypeParameter(
  int owner,
  int ordinal,
  String name,
  bool bindsName,
  bool hasBound,
) {
  var index = typeParameters.length;
  typeParameters.add(
    TypeParameterInfo(owner, ordinal, name, bindsName, hasBound),
  );
  var type = DartType(kTypeParameter, index, -1, -1);
  type.containsParameters = true;
  dartTypes.add(type);
  return dartTypes.length - 1;
}

int typeParameterInScope(List<int> scope, String name) {
  var i = scope.length;
  while (i > 0) {
    i--;
    var parameter = typeParameterInfo(scope[i]);
    if (parameter.bindsName && parameter.name == name) return scope[i];
  }
  return -1;
}

int typeParameterIndex(List<int> parameters, int type) {
  var i = 0;
  while (i < parameters.length) {
    if (parameters[i] == type) return i;
    i++;
  }
  return -1;
}

int substituteType(int type, List<int> parameters, List<int> arguments) {
  return _substituteType(type, parameters, arguments, arguments, 1);
}

int _substituteType(
  int type,
  List<int> parameters,
  List<int> upper,
  List<int> lower,
  int variance,
) {
  if (!typeContainsParameters(type)) return type;
  if (typeIsParameter(type)) {
    var i = typeParameterIndex(parameters, type);
    if (i < 0) return type;
    return variance < 0 ? lower[i] : upper[i];
  }
  var kind = dartTypes[type].kind;
  if (kind == kList)
    return listType(
      _substituteType(typeArgument(type), parameters, upper, lower, variance),
    );
  if (kind == kNullable)
    return nullableType(
      _substituteType(typeArgument(type), parameters, upper, lower, variance),
    );
  var signature = functionSignature(type);
  var result = _substituteType(
    signature.result,
    parameters,
    upper,
    lower,
    variance,
  );
  var inputs = <int>[];
  for (var input in signature.parameters)
    inputs.add(_substituteType(input, parameters, upper, lower, -variance));
  return functionType(result, inputs, signature.required);
}

int _parameterOccurrences(int type, int parameter, int variance) {
  if (!typeContainsParameters(type)) return 0;
  if (type == parameter) {
    if (variance == 0) return 3;
    return variance < 0 ? 2 : 1;
  }
  if (typeIsParameter(type)) return 0;
  var kind = dartTypes[type].kind;
  if (kind == kList || kind == kNullable)
    return _parameterOccurrences(typeArgument(type), parameter, variance);
  var signature = functionSignature(type);
  var found = _parameterOccurrences(signature.result, parameter, variance);
  for (var input in signature.parameters)
    found |= _parameterOccurrences(input, parameter, -variance);
  return found;
}

int typeParameterVariance(int type, int parameter) {
  var occurrences = _parameterOccurrences(type, parameter, 1);
  if (occurrences == 1) return 1;
  if (occurrences == 2) return -1;
  return 0;
}

bool typeContainsAnyParameter(int type, List<int> parameters) {
  if (!typeContainsParameters(type)) return false;
  if (typeIsParameter(type)) return typeParameterIndex(parameters, type) >= 0;
  var kind = dartTypes[type].kind;
  if (kind == kList || kind == kNullable)
    return typeContainsAnyParameter(typeArgument(type), parameters);
  var signature = functionSignature(type);
  if (typeContainsAnyParameter(signature.result, parameters)) return true;
  for (var input in signature.parameters)
    if (typeContainsAnyParameter(input, parameters)) return true;
  return false;
}

void _parameterDependencies(int type, List<int> parameters, List<int> found) {
  if (!typeContainsParameters(type)) return;
  if (typeIsParameter(type)) {
    var index = typeParameterIndex(parameters, type);
    if (index >= 0 && typeParameterIndex(found, index) < 0) found.add(index);
    return;
  }
  var kind = dartTypes[type].kind;
  if (kind == kList || kind == kNullable) {
    _parameterDependencies(typeArgument(type), parameters, found);
    return;
  }
  var signature = functionSignature(type);
  _parameterDependencies(signature.result, parameters, found);
  for (var input in signature.parameters)
    _parameterDependencies(input, parameters, found);
}

class _ParameterComponents {
  final List<List<int>> edges;
  List<int> indices = const <int>[];
  List<int> low = const <int>[];
  List<int> active = const <int>[];
  final List<int> stack = <int>[];
  final List<List<int>> groups = <List<int>>[];
  int next = 0;

  _ParameterComponents(this.edges) {
    indices = List<int>.filled(edges.length, -1);
    low = List<int>.filled(edges.length, -1);
    active = List<int>.filled(edges.length, 0);
  }

  void visit(int vertex) {
    indices[vertex] = next;
    low[vertex] = next;
    next++;
    stack.add(vertex);
    active[vertex] = 1;
    for (var target in edges[vertex]) {
      if (indices[target] < 0) {
        visit(target);
        if (low[target] < low[vertex]) low[vertex] = low[target];
      } else if (active[target] != 0 && indices[target] < low[vertex]) {
        low[vertex] = indices[target];
      }
    }
    if (low[vertex] == indices[vertex]) {
      var group = <int>[];
      var item = -1;
      while (item != vertex) {
        item = stack.removeLast();
        active[item] = 0;
        group.add(item);
      }
      groups.add(group);
    }
  }
}

List<int> instantiateTypeParameters(List<int> parameters) {
  if (parameters.isEmpty) return const <int>[];
  var bounds = <int>[];
  var edges = <List<int>>[];
  for (var parameter in parameters) {
    var info = typeParameterInfo(parameter);
    var bound = info.hasBound ? info.bound : tDynamic;
    bounds.add(bound);
    var dependencies = <int>[];
    _parameterDependencies(bound, parameters, dependencies);
    edges.add(dependencies);
  }
  var components = _ParameterComponents(edges);
  var i = 0;
  while (i < parameters.length) {
    if (components.indices[i] < 0) components.visit(i);
    i++;
  }
  for (var group in components.groups) {
    if (group.length > 1 ||
        typeParameterIndex(edges[group[0]], group[0]) >= 0) {
      var keys = <int>[];
      for (var index in group) keys.add(parameters[index]);
      var upper = List<int>.filled(keys.length, tDynamic);
      var lower = List<int>.filled(keys.length, tNever);
      for (var index in group)
        bounds[index] = _substituteType(
          bounds[index],
          keys,
          upper,
          lower,
          typeParameterInfo(parameters[index]).variance,
        );
    }
  }
  var done = List<int>.filled(parameters.length, 0);
  var remaining = parameters.length;
  while (remaining > 0) {
    var selected = 0;
    while (done[selected] != 0 ||
        typeContainsAnyParameter(bounds[selected], parameters))
      selected++;
    done[selected] = 1;
    remaining--;
    var keys = <int>[parameters[selected]];
    var upper = <int>[bounds[selected]];
    var lower = const <int>[tNever];
    i = 0;
    while (i < bounds.length) {
      bounds[i] = _substituteType(
        bounds[i],
        keys,
        upper,
        lower,
        typeParameterInfo(parameters[i]).variance,
      );
      i++;
    }
  }
  return bounds;
}

int superBoundedType(int type, int variance) {
  if (variance >= 0 &&
      (type == tDynamic || type == tVoid || type == nullableType(tObject)))
    return tNever;
  if (variance < 0 && typeIsSubtype(type, tNever)) return nullableType(tObject);
  var kind = dartTypes[type].kind;
  if (kind == kList)
    return listType(superBoundedType(typeArgument(type), variance));
  if (kind == kNullable)
    return nullableType(superBoundedType(typeArgument(type), variance));
  if (kind == kFunction) {
    var signature = functionSignature(type);
    var inputs = <int>[];
    for (var input in signature.parameters)
      inputs.add(superBoundedType(input, -variance));
    return functionType(
      superBoundedType(signature.result, variance),
      inputs,
      signature.required,
    );
  }
  return type;
}
