import 'nodes.dart';

extension ArenaFields on AstArena {
  bool hasKind(int? row, SyntaxKind kind) =>
      row != null && tags[row] == kind.index;
  int rStart(int? id) => starts[id!];
  int rEnd(int? id) => ends[id!];
  int rDotShorthandExpressionExpression(int? id) => childIndex(id!, 0);
  int rNullAssertionExpressionOperand(int? id) => childIndex(id!, 0);
  int? rStartOrNull(int? id) => id == null ? null : starts[id];
  String rText(int? id) => source.text.substring(starts[id!], ends[id]);
  List<int> rArgumentListArguments(int? id) => childrenOf(id!);
  int? rArgumentName(int? id) => optionalChild(id!, 0, 2);
  int? rNamedTypeAnnotationPrefix(int? id) => namedTypePrefix(id!);
  int? rEndOrNull(int? id) => id == null ? null : ends[id];
  BinaryOperator rBinaryExpressionOp(int? id) =>
      BinaryOperator.values[fields.cells[offsets[id!] + 0]];
  int? rVariableDeclarationInitializer(int? id) => optionalChild(id!, 1, 2);
  int? rNullAssertionExpressionOperandOrNull(int? id) =>
      id == null ? null : rNullAssertionExpressionOperand(id);
  List<int> rFormalParameterListParameters(int? id) => childrenOf(id!);
  FormalParameterKind rFormalParameterKind(int? id) =>
      FormalParameterKind.values[fields.cells[offsets[id!] + 0]];
  String? rTextOrNull(int? id) =>
      id == null ? null : source.text.substring(starts[id], ends[id]);
  List<int> rVariableDeclarationListDeclarations(int? id) =>
      refList(fields.cells[offsets[id!] + 4]);
  int rVariableDeclarationName(int? id) => childIndex(id!, 0);
  bool rExpressionFunctionBodyIsAsync(int? id) =>
      (fields.cells[offsets[id!] + 0] == 1);
  int rArgumentValue(int? id) => trailingChild(id!, 1);
  int? rNamedTypeAnnotationQuestionOffset(int? id) => namedTypeQuestion(id!);
  bool rNamedTypeAnnotationIsNullable(int? id) =>
      (rNamedTypeAnnotationQuestionOffset(id) != null);
  int? rConstDotShorthandExpressionArguments(int? id) =>
      nullable(fields.cells[offsets[id!] + 2]);
  int asBlockStatement(int? v) => hasKind(v, .blockStatement)
      ? v!
      : throw StateError('Expected BlockStatement');
  bool isDartPattern(int? v) =>
      v != null &&
      (switch (kindAt(v)) {
        .wildcardPattern ||
        .parenthesizedPattern ||
        .relationalPattern ||
        .nullCheckPattern ||
        .logicalPattern ||
        .mapPattern ||
        .castPattern ||
        .objectPattern ||
        .constantPattern ||
        .variablePattern ||
        .recordPattern ||
        .missingPattern ||
        .nullAssertPattern ||
        .listPattern ||
        .identifierPattern => true,
        _ => false,
      });
  int asDartPattern(int? v) =>
      isDartPattern(v) ? v! : throw StateError('Expected DartPattern');
  bool isExpression(int? v) =>
      v != null &&
      (switch (kindAt(v)) {
        .nullAssertionExpression ||
        .stringLiteralExpression ||
        .awaitExpression ||
        .literalExpression ||
        .conditionalExpression ||
        .cascadeExpression ||
        .indexExpression ||
        .invocationExpression ||
        .missingExpression ||
        .updateExpression ||
        .superExpression ||
        .parenthesizedExpression ||
        .functionExpression ||
        .assignmentExpression ||
        .cascadeIndexExpression ||
        .propertyAccessExpression ||
        .dotShorthandExpression ||
        .constDotShorthandExpression ||
        .collectionExpression ||
        .interpolatedStringExpression ||
        .dotShorthandReferenceExpression ||
        .castExpression ||
        .thisExpression ||
        .switchExpression ||
        .unaryExpression ||
        .adjacentStringsExpression ||
        .binaryExpression ||
        .typeInstantiationExpression ||
        .identifierExpression ||
        .typeTestExpression ||
        .recordExpression ||
        .instanceCreationExpression ||
        .missingStringExpression ||
        .cascadePropertyExpression ||
        .throwExpression ||
        .patternAssignmentExpression => true,
        _ => false,
      });
  int asExpressionFunctionBody(int? v) => hasKind(v, .expressionFunctionBody)
      ? v!
      : throw StateError('Expected ExpressionFunctionBody');
  int asNullAssertionExpression(int? v) => hasKind(v, .nullAssertionExpression)
      ? v!
      : throw StateError('Expected NullAssertionExpression');
  bool isStringExpression(int? v) =>
      v != null &&
      (switch (kindAt(v)) {
        .stringLiteralExpression ||
        .interpolatedStringExpression ||
        .adjacentStringsExpression ||
        .missingStringExpression => true,
        _ => false,
      });
  int asStringExpression(int? v) => isStringExpression(v)
      ? v!
      : throw StateError('Expected StringExpression');
  bool isTypeAnnotation(int? v) =>
      v != null &&
      (switch (kindAt(v)) {
        .functionTypeAnnotation ||
        .namedTypeAnnotation ||
        .missingTypeAnnotation ||
        .recordTypeAnnotation => true,
        _ => false,
      });
  int asTypeAnnotation(int? v) =>
      isTypeAnnotation(v) ? v! : throw StateError('Expected TypeAnnotation');
  int? asTypeAnnotationOrNull(int? v) => v == null ? null : asTypeAnnotation(v);
  int asTypeArgumentList(int? v) => hasKind(v, .typeArgumentList)
      ? v!
      : throw StateError('Expected TypeArgumentList');
  int? asTypeArgumentListOrNull(int? v) =>
      v == null ? null : asTypeArgumentList(v);
  int asTypeParameterList(int? v) => hasKind(v, .typeParameterList)
      ? v!
      : throw StateError('Expected TypeParameterList');
  int? asTypeParameterListOrNull(int? v) =>
      v == null ? null : asTypeParameterList(v);
}
