import '../ast.dart';
import '../graph.dart';
import '../types.dart';
import 'parameters.dart';

List<List<int>> genericArgumentStages(
  AstExpression call,
  List<int> templates,
  List<int> parameters,
  bool horizontal,
) {
  var hasFunction = false;
  if (horizontal) {
    for (var i = 1; i < call.children.length; i++) {
      var expression = call.children[i];
      if (expression.kind == astNamedArgument)
        expression = expression.children[0];
      if (expression.function != null) {
        hasFunction = true;
        break;
      }
    }
  }
  if (!hasFunction)
    return <List<int>>[
      <int>[for (var i = 0; i < templates.length; i++) i],
    ];
  final functions = <AstFunction?>[];
  final outputs = <int>[];
  final edges = <List<int>>[];
  for (var i = 0; i < templates.length; i++) {
    var expression = call.children[i + 1];
    if (expression.kind == astNamedArgument)
      expression = expression.children[0];
    functions.add(expression.function);
    final type = typeNonNullable(templates[i]);
    outputs.add(typeIsFunction(type) ? functionSignature(type).result : type);
    edges.add(<int>[]);
  }
  for (var i = 0; i < templates.length; i++) {
    final function = functions[i];
    final type = typeNonNullable(templates[i]);
    if (function == null || !typeIsFunction(type)) continue;
    final signature = functionSignature(type);
    final inputs = <int>[];
    for (var p = 0; p < function.parameters.length; p++) {
      final formal = function.parameters[p];
      final index = functionParameterIndex(signature, formal, p);
      if (formal.type.name != '' || index < 0) continue;
      for (final parameter in parameters) {
        if (typeParameterIndex(inputs, parameter) < 0 &&
            typeContainsAnyParameter(signature.parameters[index], <int>[
              parameter,
            ]))
          inputs.add(parameter);
      }
    }
    for (var j = 0; j < templates.length; j++) {
      if (typeContainsAnyParameter(outputs[j], inputs)) edges[i].add(j);
    }
  }
  final groups = stronglyConnectedComponents(edges);
  final owners = List<int>.filled(templates.length, -1);
  final levels = List<int>.filled(groups.length, 0);
  for (var group = 0; group < groups.length; group++) {
    for (final argument in groups[group]) owners[argument] = group;
  }
  var last = 0;
  for (var group = 0; group < groups.length; group++) {
    for (final argument in groups[group]) {
      for (final dependency in edges[argument]) {
        final target = owners[dependency];
        if (target != group && levels[target] >= levels[group])
          levels[group] = levels[target] + 1;
      }
    }
    if (levels[group] > last) last = levels[group];
  }
  return <List<int>>[
    for (var level = 0; level <= last; level++)
      <int>[
        for (var i = 0; i < templates.length; i++)
          if (levels[owners[i]] == level && functions[i] == null) i,
        for (var i = 0; i < templates.length; i++)
          if (levels[owners[i]] == level && functions[i] != null) i,
      ],
  ];
}

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
  List<int> fixed, [
  bool complete = true,
]) {
  var inferred = <int>[];
  for (var i = 0; i < parameters.length; i++) {
    var value = fixed[i];
    var fromUpper = false;
    if (value < 0) {
      value = lower[i];
      if (value < 0 ||
          typeHasSchemaHole(value) &&
              upper[i] >= 0 &&
              !typeHasSchemaHole(upper[i])) {
        value = upper[i];
        fromUpper = true;
      }
    }
    if (value == tDynamic) {
      if (upper[i] >= 0 && upper[i] != tDynamic) {
        value = upper[i];
        fromUpper = true;
      } else if (typeParameterInfo(parameters[i]).hasBound)
        value = typeParameterInfo(parameters[i]).bound;
    }
    if (complete && value >= 0 && typeHasSchemaHole(value))
      value = typeSchemaClosure(value, fromUpper);
    if (!complete && value < 0) value = typeSchemaHole();
    inferred.add(value);
  }
  return complete ? instantiateTypeParameters(parameters, inferred) : inferred;
}
