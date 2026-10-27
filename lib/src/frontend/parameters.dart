import '../ast.dart';
import '../scanner.dart';
import '../source.dart';

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
