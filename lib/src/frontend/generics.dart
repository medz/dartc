import '../types.dart';

// Collect actual <: template constraints. Function inputs reverse variance;
// downward result context uses the opposite direction.
void constrainGenericTypes(
  int template,
  int actual,
  List<int> parameters,
  List<int> lower,
  List<int> upper, [
  bool covariant = true,
]) {
  if (actual < 0 ||
      actual == schemaHole ||
      !typeContainsAnyParameter(template, parameters))
    return;
  var index = typeParameterIndex(parameters, template);
  if (index >= 0) {
    var constraints = covariant ? lower : upper;
    var previous = constraints[index];
    constraints[index] = previous < 0
        ? actual
        : covariant
        ? joinTypes(previous, actual)
        : meetTypes(previous, actual);
    return;
  }
  if (typeIsNullable(template)) {
    constrainGenericTypes(
      typeArgument(template),
      typeNonNullable(actual),
      parameters,
      lower,
      upper,
      covariant,
    );
    return;
  }
  actual = typeBound(actual);
  if (typeIsNullable(actual)) actual = typeArgument(actual);
  if (typeIsList(template)) {
    if (typeIsList(actual)) {
      constrainGenericTypes(
        typeArgument(template),
        typeArgument(actual),
        parameters,
        lower,
        upper,
        covariant,
      );
    }
  } else if (typeIsClass(template) || ffiKind(template) >= 0) {
    final source = dartTypes[actual];
    final target = dartTypes[template];
    if (source.kind == target.kind &&
        source.argument == target.argument &&
        source.arguments.length == target.arguments.length)
      for (var i = 0; i < target.arguments.length; i++)
        constrainGenericTypes(
          target.arguments[i],
          source.arguments[i],
          parameters,
          lower,
          upper,
          covariant,
        );
  } else if (typeIsFunction(template)) {
    var signature = functionSignature(template);
    if (typeIsFunction(actual)) {
      var source = functionSignature(actual);
      constrainGenericTypes(
        signature.result,
        source.result,
        parameters,
        lower,
        upper,
        covariant,
      );
      for (var i = 0; i < signature.parameters.length; i++)
        if (source.corresponding(signature, i) >= 0)
          constrainGenericTypes(
            signature.parameters[i],
            source.parameters[source.corresponding(signature, i)],
            parameters,
            lower,
            upper,
            !covariant,
          );
    }
  }
}

List<int> inferGenericArguments(
  List<int> parameters,
  List<int> lower,
  List<int> upper,
  List<int> fixed,
) {
  var inferred = <int>[];
  for (var i = 0; i < parameters.length; i++) {
    var value = fixed[i];
    if (value < 0) value = lower[i] < 0 ? upper[i] : lower[i];
    if (value == tDynamic) {
      if (upper[i] >= 0 && upper[i] != tDynamic)
        value = upper[i];
      else if (typeParameterInfo(parameters[i]).hasBound)
        value = typeParameterInfo(parameters[i]).bound;
    }
    if (value >= 0 && typeHasSchemaHole(value))
      value = typeCompleteSchema(value, tDynamic);
    inferred.add(value);
  }
  return instantiateTypeParameters(parameters, inferred);
}
