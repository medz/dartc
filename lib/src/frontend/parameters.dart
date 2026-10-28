import '../ast.dart';
import '../scanner.dart';
import '../source.dart';
import '../types.dart';

int functionParameterIndex(
  FunctionSignature signature,
  AstParameter parameter,
  int index,
) => parameter.kind == astNamedParameter
    ? signature.namedIndex(parameterName(parameter))
    : index < signature.positional
    ? index
    : -1;

String parameterName(AstParameter parameter) {
  var name = parameter.name;
  if (parameter.kind == astNamedParameter &&
      parameter.fieldFormal &&
      name.startsWith('_'))
    return name.substring(1);
  return name;
}

void checkParameterName(
  SourceProgram source,
  List<AstParameter> parameters,
  int index,
) {
  var parameter = parameters[index];
  if (parameter.kind != astNamedParameter) return;
  // Compiler-owned parameters use names that source text cannot spell.
  if (parameter.name.startsWith('#')) return;
  var token = source.tokens[parameter.token];
  var privateFieldFormal =
      parameter.fieldFormal && parameter.name.startsWith('_');
  if (privateFieldFormal && !sourceVersionAtLeast(source, token.source, 3, 12))
    sourceError(
      source,
      token,
      'private named field-formals require language version 3.12',
    );
  var name = parameterName(parameter);
  if (name == '' ||
      name.startsWith('_') ||
      !scanLetter(name.codeUnitAt(0)) ||
      tokenIsReserved(Token(tokenIdentifier, name, 0, 0, 0)))
    sourceError(source, token, 'named parameter must have a public name');
  var other = 0;
  while (other < parameters.length) {
    var candidate = parameters[other];
    if (other != index &&
        (candidate.kind == astNamedParameter &&
                parameterName(candidate) == name ||
            privateFieldFormal &&
                (candidate.name == parameter.name || candidate.name == name)))
      sourceError(source, token, 'conflicting parameter name ' + name);
    other++;
  }
}

int correspondingParameter(
  List<AstParameter> parameters,
  AstParameter source,
  int index,
) {
  if (source.kind != astNamedParameter)
    return index < parameters.length &&
            parameters[index].kind != astNamedParameter
        ? index
        : -1;
  for (var i = 0; i < parameters.length; i++)
    if (parameters[i].kind == astNamedParameter &&
        parameterName(parameters[i]) == parameterName(source))
      return i;
  return -1;
}
