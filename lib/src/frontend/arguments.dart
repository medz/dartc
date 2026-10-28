import '../ast.dart';
import '../source.dart';
import '../types.dart';
import 'parameters.dart';

void checkArgumentOrder(SourceProgram source, AstExpression call) {
  if (sourceVersionAtLeast(source, source.tokens[call.token].source, 2, 17))
    return;
  var named = false;
  var i = 1;
  while (i < call.children.length) {
    var argument = call.children[i];
    if (argument.kind == astNamedArgument) {
      named = true;
    } else if (named) {
      sourceError(
        source,
        source.tokens[argument.token],
        'positional arguments after named arguments require language version 2.17',
      );
    }
    i++;
  }
}

List<int> bindArguments(
  SourceProgram source,
  AstFunction function,
  AstExpression call,
  int start, [
  int parameterStart = 0,
]) {
  var parameters = parameterStart == 0
      ? function.parameters
      : function.parameters.sublist(parameterStart);
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

List<int> bindFunctionArguments(
  SourceProgram source,
  FunctionSignature signature,
  AstExpression call,
) {
  checkArgumentOrder(source, call);
  final supplied = List<bool>.filled(signature.parameters.length, false);
  final result = <int>[];
  var positional = 0;
  for (var i = 1; i < call.children.length; i++) {
    final argument = call.children[i];
    var parameter = -1;
    if (argument.kind == astNamedArgument) {
      parameter = signature.namedIndex(argument.text);
      if (parameter < 0)
        sourceError(
          source,
          source.tokens[argument.token],
          'unknown named argument ' + argument.text,
        );
    } else {
      if (positional >= signature.positional)
        sourceError(
          source,
          source.tokens[argument.token],
          'too many positional arguments',
        );
      parameter = positional++;
    }
    if (supplied[parameter])
      sourceError(
        source,
        source.tokens[argument.token],
        'duplicate argument ' + argument.text,
      );
    supplied[parameter] = true;
    result.add(parameter);
  }
  for (var p = 0; p < supplied.length; p++)
    if (!supplied[p] &&
        (p < signature.required ||
            p >= signature.positional &&
                signature.requiredNamed[p - signature.positional]))
      sourceError(
        source,
        source.tokens[call.token],
        'missing function-value argument',
      );
  return result;
}
