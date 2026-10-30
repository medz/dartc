import 'graph.dart';

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

const int tDouble = 11;

const int kNullable = 12;
const int kList = 13;
const int kClass = 14;
const int kFunction = 15;
const int kTypeParameter = 16;
const int kSchemaHole = 17;
const int kFfi = 18;

const int ffiVoid = 0;
const int ffiInt8 = 1;
const int ffiUint8 = 2;
const int ffiInt16 = 3;
const int ffiUint16 = 4;
const int ffiInt32 = 5;
const int ffiUint32 = 6;
const int ffiInt64 = 7;
const int ffiUint64 = 8;
const int ffiIntPtr = 9;
const int ffiUintPtr = 10;
const int ffiFloat = 11;
const int ffiDouble = 12;
const int ffiBool = 13;
const int ffiPointer = 14;
const int ffiNativeFunction = 15;
const int ffiNativeType = 16;
const int ffiSizedNativeType = 17;
const int ffiHandle = 18;

int schemaHole = -1;

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

// Positional parameters precede named parameters, sorted by public name.
class FunctionSignature(
  final int result,
  final List<int> parameters,
  final int required,
  final List<String> names,
  final List<bool> requiredNamed,
) {
  int get positional => parameters.length - names.length;

  int namedIndex(String name) {
    for (var i = 0; i < names.length; i++)
      if (names[i] == name) return positional + i;
    return -1;
  }

  int corresponding(FunctionSignature source, int index) =>
      index < source.positional
      ? (index < positional ? index : -1)
      : namedIndex(source.names[index - source.positional]);
}

class DartType {
  int kind;
  int argument;
  int listType;
  int nullableType;
  bool containsParameters = false;
  bool containsSchemaHole = false;
  List<int> arguments = const <int>[];

  DartType(this.kind, this.argument, this.listType, this.nullableType);
}

List<DartType> dartTypes = <DartType>[];
List<int> classDartTypes = <int>[];
List<List<int>> classTypeParameters = <List<int>>[];
List<List<int>> classSupertypes = <List<int>>[];
List<int> classSuperclasses = <int>[];
List<FunctionSignature> functionSignatures = <FunctionSignature>[];
List<TypeParameterInfo> typeParameters = <TypeParameterInfo>[];

int compareParameterNames(String left, String right) {
  final count = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < count; i++) {
    final difference = left.codeUnitAt(i) - right.codeUnitAt(i);
    if (difference != 0) return difference;
  }
  return left.length - right.length;
}

void resetTypes() {
  schemaHole = -1;
  dartTypes.clear();
  classDartTypes.clear();
  classTypeParameters.clear();
  classSupertypes.clear();
  classSuperclasses.clear();
  functionSignatures.clear();
  typeParameters.clear();
  var i = 0;
  while (i <= tDouble) {
    dartTypes.add(DartType(i, -1, -1, -1));
    i++;
  }
}

int functionType(
  int result,
  List<int> parameters, [
  int required = -1,
  List<String> names = const <String>[],
  List<bool> requiredNamed = const <bool>[],
]) {
  final positional = parameters.length - names.length;
  if (required < 0) required = positional;
  if (names.isNotEmpty) {
    parameters = <int>[...parameters];
    names = <String>[...names];
    requiredNamed = <bool>[...requiredNamed];
    for (var i = 1; i < names.length; i++) {
      var p = i;
      while (p > 0 && compareParameterNames(names[p], names[p - 1]) < 0) {
        final name = names[p];
        names[p] = names[p - 1];
        names[p - 1] = name;
        final flag = requiredNamed[p];
        requiredNamed[p] = requiredNamed[p - 1];
        requiredNamed[p - 1] = flag;
        final type = parameters[positional + p];
        parameters[positional + p] = parameters[positional + p - 1];
        parameters[positional + p - 1] = type;
        p--;
      }
    }
  }
  var type = tDouble + 1;
  while (type < dartTypes.length) {
    if (dartTypes[type].kind == kFunction) {
      var signature = functionSignatures[dartTypes[type].argument];
      if (signature.result == result &&
          signature.required == required &&
          signature.names.length == names.length &&
          signature.parameters.length == parameters.length) {
        var same = true;
        var p = 0;
        while (same && p < parameters.length) {
          same = signature.parameters[p] == parameters[p];
          if (p >= positional)
            same =
                same &&
                signature.names[p - positional] == names[p - positional] &&
                signature.requiredNamed[p - positional] ==
                    requiredNamed[p - positional];
          p++;
        }
        if (same) return type;
      }
    }
    type++;
  }
  var owned = <int>[...parameters];
  var signature = functionSignatures.length;
  functionSignatures.add(
    FunctionSignature(result, owned, required, names, requiredNamed),
  );
  var item = DartType(kFunction, signature, -1, -1);
  item.containsParameters = typeContainsParameters(result);
  item.containsSchemaHole = typeHasSchemaHole(result);
  for (var parameter in parameters) {
    if (typeContainsParameters(parameter)) item.containsParameters = true;
    if (typeHasSchemaHole(parameter)) item.containsSchemaHole = true;
  }
  dartTypes.add(item);
  return type;
}

bool typeIsFunction(int type) => dartTypes[type].kind == kFunction;

FunctionSignature functionSignature(int type) {
  return functionSignatures[dartTypes[type].argument];
}

// Context schemas guide inference; complete them before producing executable types.
int typeSchemaHole() {
  if (schemaHole < 0) {
    schemaHole = dartTypes.length;
    dartTypes.add(DartType(kSchemaHole, -1, -1, -1)..containsSchemaHole = true);
  }
  return schemaHole;
}

bool typeHasSchemaHole(int type) => dartTypes[type].containsSchemaHole;

int typeSchemaClosure(int type, bool greatest) {
  if (!typeHasSchemaHole(type)) return type;
  return _substituteType(
    type,
    <int>[schemaHole],
    <int>[nullableType(tObject)],
    <int>[tNever],
    greatest ? 1 : -1,
  );
}

int typeCompleteSchema(int schema, int inferred) {
  if (!typeHasSchemaHole(schema)) return schema;
  if (inferred < 0) inferred = tDynamic;
  var kind = dartTypes[schema].kind;
  if (kind == kSchemaHole) return inferred;
  if (kind == kNullable)
    return nullableType(
      typeCompleteSchema(typeArgument(schema), typeNonNullable(inferred)),
    );
  if (kind == kList) {
    inferred = typeNonNullable(inferred);
    return listType(
      typeCompleteSchema(
        typeArgument(schema),
        typeIsList(inferred) ? typeArgument(inferred) : tDynamic,
      ),
    );
  }
  if (kind == kClass || kind == kFfi) {
    final arguments = <int>[];
    final context = dartTypes[inferred];
    final same =
        context.kind == kind &&
        context.argument == typeArgument(schema) &&
        context.arguments.length == dartTypes[schema].arguments.length;
    for (var i = 0; i < dartTypes[schema].arguments.length; i++)
      arguments.add(
        typeCompleteSchema(
          dartTypes[schema].arguments[i],
          same ? context.arguments[i] : tDynamic,
        ),
      );
    return _appliedType(kind, typeArgument(schema), arguments);
  }
  var signature = functionSignature(schema);
  var parameters = <int>[];
  for (var parameter in signature.parameters)
    parameters.add(typeCompleteSchema(parameter, tDynamic));
  return functionType(
    typeCompleteSchema(signature.result, tDynamic),
    parameters,
    signature.required,
    signature.names,
    signature.requiredNamed,
  );
}

int listType(int element) {
  var item = dartTypes[element];
  if (item.listType < 0) {
    item.listType = dartTypes.length;
    var type = DartType(kList, element, -1, -1);
    type.containsParameters = item.containsParameters;
    type.containsSchemaHole = item.containsSchemaHole;
    dartTypes.add(type);
  }
  return item.listType;
}

int classType(int classId) {
  while (classDartTypes.length <= classId) {
    var owner = classDartTypes.length;
    classDartTypes.add(dartTypes.length);
    classTypeParameters.add(const <int>[]);
    classSupertypes.add(const <int>[]);
    classSuperclasses.add(tObject);
    dartTypes.add(DartType(kClass, owner, -1, -1));
  }
  return classDartTypes[classId];
}

// Declaration identity stays in argument; applications retain every type argument.
int _appliedType(int kind, int declaration, List<int> arguments) {
  for (var type = tDouble + 1; type < dartTypes.length; type++) {
    final item = dartTypes[type];
    if (item.kind != kind ||
        item.argument != declaration ||
        item.arguments.length != arguments.length)
      continue;
    var i = 0;
    while (i < arguments.length && item.arguments[i] == arguments[i]) i++;
    if (i == arguments.length) return type;
  }
  final item = DartType(kind, declaration, -1, -1);
  item.arguments = <int>[...arguments];
  for (final argument in arguments) {
    if (typeContainsParameters(argument)) item.containsParameters = true;
    if (typeHasSchemaHole(argument)) item.containsSchemaHole = true;
  }
  dartTypes.add(item);
  return dartTypes.length - 1;
}

int classInstanceType(int owner, List<int> arguments) => arguments.isEmpty
    ? classType(owner)
    : _appliedType(kClass, owner, arguments);

int ffiType(int kind, [int argument = -1]) =>
    _appliedType(kFfi, kind, argument < 0 ? const <int>[] : <int>[argument]);

int ffiKind(int type) => dartTypes[type].kind == kFfi ? typeArgument(type) : -1;

bool _typeArgumentsSubtype(int actual, int expected) {
  final source = dartTypes[actual].arguments;
  final target = dartTypes[expected].arguments;
  if (source.length != target.length) return false;
  for (var i = 0; i < source.length; i++)
    if (!typeIsSubtype(source[i], target[i])) return false;
  return true;
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
    result.containsSchemaHole = item.containsSchemaHole;
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
      left == tDouble ||
      left == tNum ||
      left == tString ||
      left == tBool ||
      right == tInt ||
      right == tDouble ||
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
  if (dartTypes[expected].kind == kSchemaHole) return true;
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
  if ((actual == tInt || actual == tDouble) && expected == tNum) return true;
  if (actualKind == kFunction) {
    if (expected == tFunction) return true;
    if (expectedKind == kFunction) {
      var source = functionSignature(actual);
      var target = functionSignature(expected);
      if (source.required > target.required ||
          source.positional < target.positional ||
          !typeIsSubtype(source.result, target.result))
        return false;
      var p = 0;
      while (p < target.parameters.length) {
        final q = source.corresponding(target, p);
        if (q < 0 || !typeIsSubtype(target.parameters[p], source.parameters[q]))
          return false;
        p++;
      }
      for (var i = 0; i < source.names.length; i++) {
        if (!source.requiredNamed[i]) continue;
        final q = target.namedIndex(source.names[i]);
        if (q < 0 || !target.requiredNamed[q - target.positional]) return false;
      }
      return true;
    }
  }
  if (actualKind == kList && expectedKind == kList) {
    return typeIsSubtype(typeArgument(actual), typeArgument(expected));
  }
  if (actualKind == kClass && expectedKind == kClass) {
    if (typeArgument(actual) == typeArgument(expected))
      return _typeArgumentsSubtype(actual, expected);
    for (final parent in classSupertypes[typeArgument(actual)])
      if (typeIsSubtype(
        substituteType(
          parent,
          classTypeParameters[typeArgument(actual)],
          dartTypes[actual].arguments,
        ),
        expected,
      ))
        return true;
  }
  if (actualKind == kFfi && expectedKind == kFfi) {
    final source = ffiKind(actual);
    final target = ffiKind(expected);
    if (target == ffiNativeType) return true;
    if (target == ffiSizedNativeType)
      return source >= ffiInt8 && source <= ffiPointer;
    if (source == target) return _typeArgumentsSubtype(actual, expected);
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
  if (typeIsClass(left) &&
      typeIsClass(right) &&
      typeArgument(left) == typeArgument(right) &&
      dartTypes[left].arguments.length == dartTypes[right].arguments.length)
    return classInstanceType(typeArgument(left), <int>[
      for (var i = 0; i < dartTypes[left].arguments.length; i++)
        joinTypes(dartTypes[left].arguments[i], dartTypes[right].arguments[i]),
    ]);
  if (typeIsFunction(left) && typeIsFunction(right)) {
    var a = functionSignature(left);
    var b = functionSignature(right);
    if (a.required != b.required) return tFunction;
    final named = a.names.isNotEmpty || b.names.isNotEmpty;
    if (named && (a.positional != a.required || b.positional != b.required))
      return tFunction;
    var count = a.positional;
    if (b.positional < count) count = b.positional;
    var parameters = <int>[];
    var p = 0;
    while (p < count) {
      parameters.add(meetTypes(a.parameters[p], b.parameters[p]));
      p++;
    }
    final names = <String>[];
    final required = <bool>[];
    for (var i = 0; i < a.names.length; i++) {
      final q = b.namedIndex(a.names[i]);
      if (q < 0) {
        if (a.requiredNamed[i]) return tFunction;
        continue;
      }
      names.add(a.names[i]);
      required.add(a.requiredNamed[i] || b.requiredNamed[q - b.positional]);
      parameters.add(
        meetTypes(a.parameters[a.positional + i], b.parameters[q]),
      );
    }
    for (var i = 0; i < b.names.length; i++)
      if (b.requiredNamed[i] && a.namedIndex(b.names[i]) < 0) return tFunction;
    return functionType(
      joinTypes(a.result, b.result),
      parameters,
      a.required,
      names,
      required,
    );
  }
  if (typeIsSubtype(left, right)) return right;
  if (typeIsSubtype(right, left)) return left;
  if (typeIsParameter(left) || typeIsParameter(right))
    return joinTypes(typeBound(left), typeBound(right));
  if (left == tNull) return nullableType(right);
  if (right == tNull) return nullableType(left);
  if (typeIsNullable(left) || typeIsNullable(right)) {
    return nullableType(
      joinTypes(typeNonNullable(left), typeNonNullable(right)),
    );
  }
  if (typeIsSubtype(left, tNum) && typeIsSubtype(right, tNum)) return tNum;
  if (typeIsList(left) && typeIsList(right)) {
    return listType(joinTypes(typeArgument(left), typeArgument(right)));
  }
  if (typeIsClass(left) && typeIsClass(right)) {
    final common = <int>[];
    for (final type in classDartTypes)
      if (typeIsSubtype(left, type) && typeIsSubtype(right, type))
        common.add(type);
    for (final type in common) {
      var mostSpecific = true;
      for (final other in common)
        if (!typeIsSubtype(type, other)) mostSpecific = false;
      if (mostSpecific) return type;
    }
  }
  return tObject;
}

int meetTypes(int left, int right) {
  if (dartTypes[left].kind == kSchemaHole) return right;
  if (dartTypes[right].kind == kSchemaHole) return left;
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
    final named = a.names.isNotEmpty || b.names.isNotEmpty;
    if (named &&
        (a.positional != a.required ||
            b.positional != b.required ||
            a.positional != b.positional))
      return tNever;
    var count = a.positional;
    if (b.positional > count) count = b.positional;
    var parameters = <int>[];
    var p = 0;
    while (p < count) {
      if (p >= a.positional)
        parameters.add(b.parameters[p]);
      else if (p >= b.positional)
        parameters.add(a.parameters[p]);
      else
        parameters.add(joinTypes(a.parameters[p], b.parameters[p]));
      p++;
    }
    var required = a.required;
    if (b.required < required) required = b.required;
    final names = <String>[...a.names];
    final requiredNamed = <bool>[];
    for (var i = 0; i < a.names.length; i++) {
      final q = b.namedIndex(a.names[i]);
      parameters.add(
        q < 0
            ? a.parameters[a.positional + i]
            : joinTypes(a.parameters[a.positional + i], b.parameters[q]),
      );
      requiredNamed.add(
        q >= 0 && a.requiredNamed[i] && b.requiredNamed[q - b.positional],
      );
    }
    for (var i = 0; i < b.names.length; i++) {
      if (a.namedIndex(b.names[i]) >= 0) continue;
      names.add(b.names[i]);
      requiredNamed.add(false);
      parameters.add(b.parameters[b.positional + i]);
    }
    return functionType(
      meetTypes(a.result, b.result),
      parameters,
      required,
      names,
      requiredNamed,
    );
  }
  if (typeIsSubtype(left, right)) return left;
  if (typeIsSubtype(right, left)) return right;
  return tNever;
}

bool typeIsParameter(int type) => dartTypes[type].kind == kTypeParameter;

TypeParameterInfo typeParameterInfo(int type) =>
    typeParameters[dartTypes[type].argument];

bool typeContainsParameters(int type) => dartTypes[type].containsParameters;

// Boundary types describe the shared call's value representation. Runtime
// type arguments remain separate and the source signature is not erased.
int genericBoundaryType(int type) {
  if (!typeContainsParameters(type)) return type;
  if (typeIsList(type)) return listType(tDynamic);
  if (typeIsFunction(type)) return tFunction;
  if (typeIsNullable(type) && typeIsReference(type))
    return nullableType(genericBoundaryType(typeArgument(type)));
  return tDynamic;
}

int typeBound(int type) {
  while (typeIsParameter(type)) type = typeParameterInfo(type).bound;
  return type;
}

bool typeParametersInScope(int type, List<int> scope) {
  if (!typeContainsParameters(type)) return true;
  if (typeIsParameter(type)) return typeParameterIndex(scope, type) >= 0;
  if (typeIsList(type) || typeIsNullable(type))
    return typeParametersInScope(typeArgument(type), scope);
  if (typeIsClass(type) || ffiKind(type) >= 0) {
    for (final argument in dartTypes[type].arguments)
      if (!typeParametersInScope(argument, scope)) return false;
    return true;
  }
  var signature = functionSignature(type);
  if (!typeParametersInScope(signature.result, scope)) return false;
  for (var parameter in signature.parameters)
    if (!typeParametersInScope(parameter, scope)) return false;
  return true;
}

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
  if (!typeContainsParameters(type) && !typeHasSchemaHole(type)) return type;
  if (typeIsParameter(type) || type == schemaHole) {
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
  if (kind == kClass || kind == kFfi)
    return _appliedType(kind, typeArgument(type), <int>[
      for (final argument in dartTypes[type].arguments)
        _substituteType(argument, parameters, upper, lower, variance),
    ]);
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
  return functionType(
    result,
    inputs,
    signature.required,
    signature.names,
    signature.requiredNamed,
  );
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
  if (kind == kClass || kind == kFfi) {
    var found = 0;
    for (final argument in dartTypes[type].arguments)
      found |= _parameterOccurrences(argument, parameter, variance);
    return found;
  }
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
  if (kind == kClass || kind == kFfi) {
    for (final argument in dartTypes[type].arguments)
      if (typeContainsAnyParameter(argument, parameters)) return true;
    return false;
  }
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
  if (kind == kClass || kind == kFfi) {
    for (final argument in dartTypes[type].arguments)
      _parameterDependencies(argument, parameters, found);
    return;
  }
  var signature = functionSignature(type);
  _parameterDependencies(signature.result, parameters, found);
  for (var input in signature.parameters)
    _parameterDependencies(input, parameters, found);
}

List<int> instantiateTypeParameters(
  List<int> parameters, [
  List<int> inferred = const <int>[],
]) {
  if (parameters.isEmpty) return const <int>[];
  var bounds = <int>[];
  var edges = <List<int>>[];
  for (var parameter in parameters) {
    var info = typeParameterInfo(parameter);
    var bound = info.hasBound ? info.bound : tDynamic;
    if (inferred.isNotEmpty && inferred[bounds.length] >= 0)
      bound = inferred[bounds.length];
    bounds.add(bound);
    var dependencies = <int>[];
    _parameterDependencies(bound, parameters, dependencies);
    edges.add(dependencies);
  }
  final groups = stronglyConnectedComponents(edges);
  var i = 0;
  for (var group in groups) {
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
    var lower = <int>[
      inferred.isNotEmpty && inferred[selected] >= 0
          ? bounds[selected]
          : tNever,
    ];
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
  if (kind == kClass || kind == kFfi)
    return _appliedType(kind, typeArgument(type), <int>[
      for (final argument in dartTypes[type].arguments)
        superBoundedType(argument, variance),
    ]);
  if (kind == kFunction) {
    var signature = functionSignature(type);
    var inputs = <int>[];
    for (var input in signature.parameters)
      inputs.add(superBoundedType(input, -variance));
    return functionType(
      superBoundedType(signature.result, variance),
      inputs,
      signature.required,
      signature.names,
      signature.requiredNamed,
    );
  }
  return type;
}
