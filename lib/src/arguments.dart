import 'ast.dart';
import 'source.dart';

String parameterName(AstParameter parameter) {
  var name = parameter.name;
  if (parameter.kind == astNamedParameter &&
      parameter.fieldFormal &&
      name.startsWith('_'))
    return name.substring(1);
  return name;
}

List<int> bindArguments(
  SourceProgram source,
  AstFunction function,
  AstExpression call,
  int start,
) {
  var parameters = function.parameters;
  var supplied = List<bool>.filled(parameters.length, false);
  var result = <int>[];
  var positional = 0;
  var i = start;
  while (i < call.children.length) {
    var argument = call.children[i];
    var parameter = -1;
    if (argument.kind == astNamedArgument) {
      var p = 0;
      while (p < parameters.length) {
        if (parameters[p].kind == astNamedParameter &&
            parameterName(parameters[p]) == argument.text) {
          parameter = p;
          break;
        }
        p++;
      }
      if (parameter < 0) {
        sourceError(
          source,
          source.tokens[argument.token],
          'unknown named argument ' + argument.text,
        );
      }
    } else {
      if (positional >= parameters.length ||
          parameters[positional].kind == astNamedParameter) {
        sourceError(
          source,
          source.tokens[argument.token],
          'too many positional arguments',
        );
      }
      parameter = positional;
      positional++;
    }
    if (supplied[parameter]) {
      sourceError(
        source,
        source.tokens[argument.token],
        'duplicate argument ' + parameterName(parameters[parameter]),
      );
    }
    supplied[parameter] = true;
    result.add(parameter);
    i++;
  }
  var p = 0;
  while (p < parameters.length) {
    if (!supplied[p] &&
        (parameters[p].kind == astRequiredPositional ||
            parameters[p].required)) {
      sourceError(
        source,
        source.tokens[call.token],
        'missing argument ' + parameterName(parameters[p]),
      );
    }
    p++;
  }
  return result;
}
