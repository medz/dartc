part of 'nodes.dart';

extension _NodeViews on SyntaxTreeBuilder {
  AstNode _at(int id) => switch (_kindAt(id)) {
    .adjacentStringsExpression => _RowAdjacentStringsExpression(this, id),
    .annotation => _RowAnnotation(this, id),
    .argument => _RowArgument(this, id),
    .argumentList => _RowArgumentList(this, id),
    .assertInitializer => _RowAssertInitializer(this, id),
    .assertStatement => _RowAssertStatement(this, id),
    .assignmentExpression => _RowAssignmentExpression(this, id),
    .awaitExpression => _RowAwaitExpression(this, id),
    .binaryExpression => _RowBinaryExpression(this, id),
    .blockStatement => _RowBlockStatement(this, id),
    .breakStatement => _RowBreakStatement(this, id),
    .cascadeExpression => _RowCascadeExpression(this, id),
    .cascadeIndexExpression => _RowCascadeIndexExpression(this, id),
    .cascadePropertyExpression => _RowCascadePropertyExpression(this, id),
    .castExpression => _RowCastExpression(this, id),
    .castPattern => _RowCastPattern(this, id),
    .catchClause => _RowCatchClause(this, id),
    .classDeclaration => _RowClassDeclaration(this, id),
    .classTypeAliasDeclaration => _RowClassTypeAliasDeclaration(this, id),
    .collectionExpression => _RowCollectionExpression(this, id),
    .compilationUnit => _RowCompilationUnit(this, id),
    .conditionalExpression => _RowConditionalExpression(this, id),
    .conditionalUri => _RowConditionalUri(this, id),
    .constDotShorthandExpression => _RowConstDotShorthandExpression(this, id),
    .constantPattern => _RowConstantPattern(this, id),
    .constructorDeclaration => _RowConstructorDeclaration(this, id),
    .continueStatement => _RowContinueStatement(this, id),
    .declaredIdentifier => _RowDeclaredIdentifier(this, id),
    .doStatement => _RowDoStatement(this, id),
    .dotShorthandExpression => _RowDotShorthandExpression(this, id),
    .dotShorthandReferenceExpression => _RowDotShorthandReferenceExpression(
      this,
      id,
    ),
    .dottedName => _RowDottedName(this, id),
    .emptyFunctionBody => _RowEmptyFunctionBody(this, id),
    .emptyStatement => _RowEmptyStatement(this, id),
    .enumConstantDeclaration => _RowEnumConstantDeclaration(this, id),
    .enumDeclaration => _RowEnumDeclaration(this, id),
    .exportDirective => _RowExportDirective(this, id),
    .expressionFunctionBody => _RowExpressionFunctionBody(this, id),
    .expressionStatement => _RowExpressionStatement(this, id),
    .extendsClause => _RowExtendsClause(this, id),
    .extensionDeclaration => _RowExtensionDeclaration(this, id),
    .extensionTypeDeclaration => _RowExtensionTypeDeclaration(this, id),
    .factoryRedirectBody => _RowFactoryRedirectBody(this, id),
    .fieldDeclaration => _RowFieldDeclaration(this, id),
    .fieldInitializer => _RowFieldInitializer(this, id),
    .forElement => _RowForElement(this, id),
    .forInParts => _RowForInParts(this, id),
    .forParts => _RowForParts(this, id),
    .forStatement => _RowForStatement(this, id),
    .formalParameter => _RowFormalParameter(this, id),
    .formalParameterList => _RowFormalParameterList(this, id),
    .functionExpression => _RowFunctionExpression(this, id),
    .functionParameterSuffix => _RowFunctionParameterSuffix(this, id),
    .functionTypeAliasDeclaration => _RowFunctionTypeAliasDeclaration(this, id),
    .functionTypeAnnotation => _RowFunctionTypeAnnotation(this, id),
    .functionTypeParameter => _RowFunctionTypeParameter(this, id),
    .functionTypeParameterList => _RowFunctionTypeParameterList(this, id),
    .getterDeclaration => _RowGetterDeclaration(this, id),
    .guardedPattern => _RowGuardedPattern(this, id),
    .identifier => _RowIdentifier(this, id),
    .identifierExpression => _RowIdentifierExpression(this, id),
    .identifierPattern => _RowIdentifierPattern(this, id),
    .ifElement => _RowIfElement(this, id),
    .ifStatement => _RowIfStatement(this, id),
    .importDirective => _RowImportDirective(this, id),
    .indexExpression => _RowIndexExpression(this, id),
    .instanceCreationExpression => _RowInstanceCreationExpression(this, id),
    .interpolatedStringExpression => _RowInterpolatedStringExpression(this, id),
    .invocationExpression => _RowInvocationExpression(this, id),
    .label => _RowLabel(this, id),
    .labeledStatement => _RowLabeledStatement(this, id),
    .libraryDirective => _RowLibraryDirective(this, id),
    .listPattern => _RowListPattern(this, id),
    .literalExpression => _RowLiteralExpression(this, id),
    .localFunctionDeclaration => _RowLocalFunctionDeclaration(this, id),
    .logicalPattern => _RowLogicalPattern(this, id),
    .mapEntryElement => _RowMapEntryElement(this, id),
    .mapPattern => _RowMapPattern(this, id),
    .mapPatternEntry => _RowMapPatternEntry(this, id),
    .methodDeclaration => _RowMethodDeclaration(this, id),
    .missingClassMember => _RowMissingClassMember(this, id),
    .missingExpression => _RowMissingExpression(this, id),
    .missingFunctionBody => _RowMissingFunctionBody(this, id),
    .missingPattern => _RowMissingPattern(this, id),
    .missingStatement => _RowMissingStatement(this, id),
    .missingStringExpression => _RowMissingStringExpression(this, id),
    .missingTopLevelDeclaration => _RowMissingTopLevelDeclaration(this, id),
    .missingTypeAnnotation => _RowMissingTypeAnnotation(this, id),
    .mixinDeclaration => _RowMixinDeclaration(this, id),
    .modifiedBlockFunctionBody => _RowModifiedBlockFunctionBody(this, id),
    .namedPatternField => _RowNamedPatternField(this, id),
    .namedRecordField => _RowNamedRecordField(this, id),
    .namedRecordTypeField => _RowNamedRecordTypeField(this, id),
    .namedTypeAnnotation => _RowNamedTypeAnnotation(this, id),
    .namespaceCombinator => _RowNamespaceCombinator(this, id),
    .nullAssertPattern => _RowNullAssertPattern(this, id),
    .nullAssertionExpression => _RowNullAssertionExpression(this, id),
    .nullAwareElement => _RowNullAwareElement(this, id),
    .nullCheckPattern => _RowNullCheckPattern(this, id),
    .objectPattern => _RowObjectPattern(this, id),
    .operatorDeclaration => _RowOperatorDeclaration(this, id),
    .parameterDefault => _RowParameterDefault(this, id),
    .parenthesizedExpression => _RowParenthesizedExpression(this, id),
    .parenthesizedPattern => _RowParenthesizedPattern(this, id),
    .partDirective => _RowPartDirective(this, id),
    .partOfDirective => _RowPartOfDirective(this, id),
    .patternAssignmentExpression => _RowPatternAssignmentExpression(this, id),
    .patternForInBinding => _RowPatternForInBinding(this, id),
    .patternVariableDeclaration => _RowPatternVariableDeclaration(this, id),
    .patternVariableDeclarationStatement =>
      _RowPatternVariableDeclarationStatement(this, id),
    .positionalRecordTypeField => _RowPositionalRecordTypeField(this, id),
    .primaryConstructorBody => _RowPrimaryConstructorBody(this, id),
    .propertyAccessExpression => _RowPropertyAccessExpression(this, id),
    .recordExpression => _RowRecordExpression(this, id),
    .recordPattern => _RowRecordPattern(this, id),
    .recordTypeAnnotation => _RowRecordTypeAnnotation(this, id),
    .recordTypeNamedFields => _RowRecordTypeNamedFields(this, id),
    .redirectingConstructorInitializer => _RowRedirectingConstructorInitializer(
      this,
      id,
    ),
    .relationalPattern => _RowRelationalPattern(this, id),
    .restPatternElement => _RowRestPatternElement(this, id),
    .rethrowStatement => _RowRethrowStatement(this, id),
    .returnStatement => _RowReturnStatement(this, id),
    .scriptTag => _RowScriptTag(this, id),
    .setterDeclaration => _RowSetterDeclaration(this, id),
    .spreadElement => _RowSpreadElement(this, id),
    .stringInterpolation => _RowStringInterpolation(this, id),
    .stringLiteralExpression => _RowStringLiteralExpression(this, id),
    .stringText => _RowStringText(this, id),
    .superConstructorInitializer => _RowSuperConstructorInitializer(this, id),
    .superExpression => _RowSuperExpression(this, id),
    .switchExpression => _RowSwitchExpression(this, id),
    .switchExpressionCase => _RowSwitchExpressionCase(this, id),
    .switchStatement => _RowSwitchStatement(this, id),
    .switchStatementMember => _RowSwitchStatementMember(this, id),
    .thisExpression => _RowThisExpression(this, id),
    .throwExpression => _RowThrowExpression(this, id),
    .topLevelFunctionDeclaration => _RowTopLevelFunctionDeclaration(this, id),
    .topLevelGetterDeclaration => _RowTopLevelGetterDeclaration(this, id),
    .topLevelSetterDeclaration => _RowTopLevelSetterDeclaration(this, id),
    .topLevelVariableDeclaration => _RowTopLevelVariableDeclaration(this, id),
    .tryStatement => _RowTryStatement(this, id),
    .typeAliasDeclaration => _RowTypeAliasDeclaration(this, id),
    .typeArgumentList => _RowTypeArgumentList(this, id),
    .typeInstantiationExpression => _RowTypeInstantiationExpression(this, id),
    .typeListClause => _RowTypeListClause(this, id),
    .typeParameter => _RowTypeParameter(this, id),
    .typeParameterList => _RowTypeParameterList(this, id),
    .typeTestExpression => _RowTypeTestExpression(this, id),
    .unaryExpression => _RowUnaryExpression(this, id),
    .updateExpression => _RowUpdateExpression(this, id),
    .variableDeclaration => _RowVariableDeclaration(this, id),
    .variableDeclarationList => _RowVariableDeclarationList(this, id),
    .variableDeclarationStatement => _RowVariableDeclarationStatement(this, id),
    .variablePattern => _RowVariablePattern(this, id),
    .whileStatement => _RowWhileStatement(this, id),
    .wildcardPattern => _RowWildcardPattern(this, id),
    .yieldStatement => _RowYieldStatement(this, id),
  };
}

sealed class _Row(this._owner, this._row) implements AstNode {
  final SyntaxTreeBuilder _owner;
  final int _row;
  @override
  bool operator ==(Object other) =>
      other is _Row && identical(_owner, other._owner) && _row == other._row;
  @override
  int get hashCode => Object.hash(_owner, _row);
  @override
  SourceFile get source => _owner.source;
  @override
  int get start => _owner._start(_row);
  @override
  int get end => _owner._end(_row);
  @override
  int get length => end - start;
  @override
  String get text => source.text.substring(start, end);
  @override
  SourceSpan get span => SourceSpan(source, start, end);
  @override
  int get childCount => _owner._childCount(_row);
  @override
  AstNode childAt(int i) {
    RangeError.checkValidIndex(i, this, 'index', childCount);
    return _owner._at(_owner._childIndex(_row, i));
  }

  AstNode get _firstChild => _fixedChild(0);
  AstNode get _secondChild => _fixedChild(1);

  T _fixedChild<T>(int position) =>
      _owner._at(_owner._childIndex(_row, position)) as T;
  T _trailingChild<T>(int fromEnd) =>
      _owner._at(_owner._trailingChild(_row, fromEnd)) as T;
  T _optionalChild<T>(int index, int fullCount) {
    final id = _owner._optionalChild(_row, index, fullCount);
    return (id == null ? null : _owner._at(id)) as T;
  }

  List<T> _allChildren<T>() => _RowList<T>(
    _owner,
    _owner._edges.cells,
    _owner._edgeOffsets[_row],
    childCount,
    null,
  );

  int _word(int f) => _owner._fields.cells[_owner._offsets[_row] + f];
  T _node<T>(int f) {
    final v = _word(f);
    return (v == _nil ? null : _owner._at(v)) as T;
  }

  int? _questionAt(int field) {
    final distance = _word(field);
    return distance == _nil ? null : end - distance;
  }

  T _flag<T>(int f) {
    final v = _word(f);
    return (v == _nil ? null : v != 0) as T;
  }

  List<T> _firstChildren<T>(int length) => _childSlice(0, length);
  List<T> _lastChildren<T>(int length, [int skip = 0]) =>
      _childSlice(childCount - skip - length, length);
  List<T> _childSlice<T>(int from, int length) => length == 0
      ? const []
      : _RowList<T>(
          _owner,
          _owner._edges.cells,
          _owner._edgeOffsets[_row] + from,
          length,
          null,
        );
  List<T> _enums<T>(int offset, int length, List<Enum> values) => length == 0
      ? const []
      : _RowList<T>(
          _owner,
          _owner._fields.cells,
          _owner._offsets[_row] + offset,
          length,
          values,
        );
}

final class _RowList<T>(
  final SyntaxTreeBuilder _owner,
  final Uint32List _cells,
  final int _off,
  final int _count,
  final List<Enum>? _values,
) extends ListBase<T> {
  @override
  int get length => _count;
  @override
  set length(int n) => throw UnsupportedError('immutable');
  @override
  T operator [](int i) {
    RangeError.checkValidIndex(i, this);
    final v = _cells[_off + i];
    return (_values == null ? _owner._at(v) : _values[v]) as T;
  }

  @override
  void operator []=(int i, T value) => throw UnsupportedError('immutable');
}

final class _RowAdjacentStringsExpression(super._owner, super._row)
    extends _Row
    implements AdjacentStringsExpression {
  @override
  get strings => _allChildren();
}

final class _RowAnnotation(super._owner, super._row)
    extends _Row
    implements Annotation {
  @override
  get typeArguments => _node(0);
  @override
  get constructorName => _node(1);
  @override
  get arguments => _node(2);
  @override
  get name => _firstChildren(_word(3));
}

final class _RowArgument(super._owner, super._row)
    extends _Row
    implements Argument {
  @override
  get name => _optionalChild(0, 2);
  @override
  get value => _trailingChild(1);
}

final class _RowArgumentList(super._owner, super._row)
    extends _Row
    implements ArgumentList {
  @override
  get arguments => _allChildren();
}

final class _RowAssertInitializer(super._owner, super._row)
    extends _Row
    implements AssertInitializer {
  @override
  get condition => _fixedChild(0);
  @override
  get message => _optionalChild(1, 2);
}

final class _RowAssertStatement(super._owner, super._row)
    extends _Row
    implements AssertStatement {
  @override
  get condition => _fixedChild(0);
  @override
  get message => _optionalChild(1, 2);
}

final class _RowAssignmentExpression(super._owner, super._row)
    extends _Row
    implements AssignmentExpression {
  @override
  get left => _fixedChild(0);
  @override
  AssignmentOperator get op => AssignmentOperator.values[_word(0)];
  @override
  get right => _fixedChild(1);
}

final class _RowAwaitExpression(super._owner, super._row)
    extends _Row
    implements AwaitExpression {
  @override
  get expression => _fixedChild(0);
}

final class _RowBinaryExpression(super._owner, super._row)
    extends _Row
    implements BinaryExpression {
  @override
  Expression get left => _firstChild as Expression;
  @override
  BinaryOperator get op => BinaryOperator.values[_word(0)];
  @override
  Expression get right => _secondChild as Expression;
}

final class _RowBlockStatement(super._owner, super._row)
    extends _Row
    implements BlockStatement {
  @override
  get statements => _allChildren();
}

final class _RowBreakStatement(super._owner, super._row)
    extends _Row
    implements BreakStatement {
  @override
  get label => _optionalChild(0, 1);
}

final class _RowCascadeExpression(super._owner, super._row)
    extends _Row
    implements CascadeExpression {
  @override
  get target => _node(0);
  @override
  get isNullAware => _flag(1);
  @override
  get sections => _lastChildren(_word(2));
}

final class _RowCascadeIndexExpression(super._owner, super._row)
    extends _Row
    implements CascadeIndexExpression {
  @override
  get index => _fixedChild(0);
}

final class _RowCascadePropertyExpression(super._owner, super._row)
    extends _Row
    implements CascadePropertyExpression {
  @override
  get property => _fixedChild(0);
}

final class _RowCastExpression(super._owner, super._row)
    extends _Row
    implements CastExpression {
  @override
  get expression => _fixedChild(0);
  @override
  get type => _fixedChild(1);
}

final class _RowCastPattern(super._owner, super._row)
    extends _Row
    implements CastPattern {
  @override
  get pattern => _fixedChild(0);
  @override
  get type => _fixedChild(1);
}

final class _RowCatchClause(super._owner, super._row)
    extends _Row
    implements CatchClause {
  @override
  get exceptionType => _node(0);
  @override
  get exceptionParameter => _node(1);
  @override
  get stackTraceParameter => _node(2);
  @override
  get body => _node(3);
}

final class _RowClassDeclaration(super._owner, super._row)
    extends _Row
    implements ClassDeclaration {
  @override
  get name => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get isConst => _flag(2);
  @override
  get primaryConstructorName => _node(3);
  @override
  get primaryParameters => _node(4);
  @override
  get extendsClause => _node(5);
  @override
  get withClause => _node(6);
  @override
  get implementsClause => _node(7);
  @override
  get isSemicolonBody => _flag(8);
  @override
  get metadata => _firstChildren(_word(9));
  @override
  get modifiers => _enums(12, _word(10), ClassModifier.values);
  @override
  get members => _lastChildren(_word(11));
}

final class _RowClassTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements ClassTypeAliasDeclaration {
  @override
  get name => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get superclass => _node(2);
  @override
  get withClause => _node(3);
  @override
  get implementsClause => _node(4);
  @override
  get metadata => _firstChildren(_word(5));
  @override
  get modifiers => _enums(7, _word(6), ClassModifier.values);
}

final class _RowCollectionExpression(super._owner, super._row)
    extends _Row
    implements CollectionExpression {
  @override
  CollectionLiteralKind get kind => CollectionLiteralKind.values[_word(0)];
  @override
  get hasConstKeyword => _flag(1);
  @override
  get typeArguments => _node(2);
  @override
  get elements => _lastChildren(_word(3));
}

final class _RowCompilationUnit(super._owner, super._row)
    extends _Row
    implements CompilationUnit {
  @override
  get scriptTag => _node(0);
  @override
  get members => _lastChildren(_word(1));
}

final class _RowConditionalExpression(super._owner, super._row)
    extends _Row
    implements ConditionalExpression {
  @override
  get condition => _fixedChild(0);
  @override
  get thenExpression => _fixedChild(1);
  @override
  get elseExpression => _fixedChild(2);
}

final class _RowConditionalUri(super._owner, super._row)
    extends _Row
    implements ConditionalUri {
  @override
  get name => _fixedChild(0);
  @override
  get value => _optionalChild(1, 3);
  @override
  get uri => _trailingChild(1);
}

final class _RowConstDotShorthandExpression(super._owner, super._row)
    extends _Row
    implements ConstDotShorthandExpression {
  @override
  get name => _node(0);
  @override
  get typeArguments => _node(1);
  @override
  get arguments => _node(2);
}

final class _RowConstantPattern(super._owner, super._row)
    extends _Row
    implements ConstantPattern {
  @override
  get hasConstKeyword => _flag(0);
  @override
  get expression => _fixedChild(0);
}

final class _RowConstructorDeclaration(super._owner, super._row)
    extends _Row
    implements ConstructorDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get isConst => _flag(1);
  @override
  ConstructorKeyword get keyword => ConstructorKeyword.values[_word(2)];
  @override
  get parameters => _node(3);
  @override
  get body => _node(4);
  @override
  get metadata => _firstChildren(_word(5));
  @override
  get name => _childSlice(_word(5), _word(6));
  @override
  get initializers => _lastChildren(_word(7), 1);
}

final class _RowContinueStatement(super._owner, super._row)
    extends _Row
    implements ContinueStatement {
  @override
  get label => _optionalChild(0, 1);
}

final class _RowDeclaredIdentifier(super._owner, super._row)
    extends _Row
    implements DeclaredIdentifier {
  @override
  VariableKeyword get keyword => VariableKeyword.values[_word(0)];
  @override
  get type => _node(1);
  @override
  get name => _node(2);
  @override
  get metadata => _firstChildren(_word(3));
}

final class _RowDoStatement(super._owner, super._row)
    extends _Row
    implements DoStatement {
  @override
  get body => _fixedChild(0);
  @override
  get condition => _fixedChild(1);
}

final class _RowDotShorthandExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandExpression {
  @override
  get expression => _fixedChild(0);
}

final class _RowDotShorthandReferenceExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandReferenceExpression {
  @override
  get name => _fixedChild(0);
}

final class _RowDottedName(super._owner, super._row)
    extends _Row
    implements DottedName {
  @override
  get components => _allChildren();
}

final class _RowEmptyFunctionBody(super._owner, super._row)
    extends _Row
    implements EmptyFunctionBody {}

final class _RowEmptyStatement(super._owner, super._row)
    extends _Row
    implements EmptyStatement {}

final class _RowEnumConstantDeclaration(super._owner, super._row)
    extends _Row
    implements EnumConstantDeclaration {
  @override
  get name => _node(0);
  @override
  get typeArguments => _node(1);
  @override
  get constructorName => _node(2);
  @override
  get arguments => _node(3);
  @override
  get metadata => _firstChildren(_word(4));
}

final class _RowEnumDeclaration(super._owner, super._row)
    extends _Row
    implements EnumDeclaration {
  @override
  get name => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get isConst => _flag(2);
  @override
  get primaryConstructorName => _node(3);
  @override
  get primaryParameters => _node(4);
  @override
  get withClause => _node(5);
  @override
  get implementsClause => _node(6);
  @override
  get isSemicolonBody => _flag(7);
  @override
  get hasMemberSeparator => _flag(8);
  @override
  get metadata => _firstChildren(_word(9));
  @override
  get constants => _lastChildren(_word(10), _word(11));
  @override
  get members => _lastChildren(_word(11));
}

final class _RowExportDirective(super._owner, super._row)
    extends _Row
    implements ExportDirective {
  @override
  get uri => _node(0);
  @override
  get configurations => _lastChildren(_word(1), _word(2));
  @override
  get combinators => _lastChildren(_word(2));
  @override
  get metadata => _firstChildren(_word(3));
}

final class _RowExpressionFunctionBody(super._owner, super._row)
    extends _Row
    implements ExpressionFunctionBody {
  @override
  get isAsync => _flag(0);
  @override
  get expression => _fixedChild(0);
}

final class _RowExpressionStatement(super._owner, super._row)
    extends _Row
    implements ExpressionStatement {
  @override
  get expression => _fixedChild(0);
}

final class _RowExtendsClause(super._owner, super._row)
    extends _Row
    implements ExtendsClause {
  @override
  get superclass => _fixedChild(0);
}

final class _RowExtensionDeclaration(super._owner, super._row)
    extends _Row
    implements ExtensionDeclaration {
  @override
  get name => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get onType => _node(2);
  @override
  get isSemicolonBody => _flag(3);
  @override
  get metadata => _firstChildren(_word(4));
  @override
  get members => _lastChildren(_word(5));
}

final class _RowExtensionTypeDeclaration(super._owner, super._row)
    extends _Row
    implements ExtensionTypeDeclaration {
  @override
  get isConst => _flag(0);
  @override
  get name => _node(1);
  @override
  get typeParameters => _node(2);
  @override
  get primaryConstructorName => _node(3);
  @override
  get primaryParameters => _node(4);
  @override
  get implementsClause => _node(5);
  @override
  get isSemicolonBody => _flag(6);
  @override
  get metadata => _firstChildren(_word(7));
  @override
  get members => _lastChildren(_word(8));
}

final class _RowFactoryRedirectBody(super._owner, super._row)
    extends _Row
    implements FactoryRedirectBody {
  @override
  get typeArguments => _node(0);
  @override
  get constructorName => _node(1);
  @override
  get name => _firstChildren(_word(2));
}

final class _RowFieldDeclaration(super._owner, super._row)
    extends _Row
    implements FieldDeclaration {
  @override
  get isStatic => _flag(0);
  @override
  get isAbstract => _flag(1);
  @override
  get isExternal => _flag(2);
  @override
  get isCovariant => _flag(3);
  @override
  get variables => _fixedChild(0);
}

final class _RowFieldInitializer(super._owner, super._row)
    extends _Row
    implements FieldInitializer {
  @override
  get hasThis => _flag(0);
  @override
  get name => _fixedChild(0);
  @override
  get value => _fixedChild(1);
}

final class _RowForElement(super._owner, super._row)
    extends _Row
    implements ForElement {
  @override
  get isAwait => _flag(0);
  @override
  get parts => _fixedChild(0);
  @override
  get body => _fixedChild(1);
}

final class _RowForInParts(super._owner, super._row)
    extends _Row
    implements ForInParts {
  @override
  get target => _fixedChild(0);
  @override
  get iterable => _fixedChild(1);
}

final class _RowForParts(super._owner, super._row)
    extends _Row
    implements ForParts {
  @override
  get initializer => _node(0);
  @override
  get condition => _node(1);
  @override
  get updaters => _lastChildren(_word(2));
}

final class _RowForStatement(super._owner, super._row)
    extends _Row
    implements ForStatement {
  @override
  get isAwait => _flag(0);
  @override
  get parts => _fixedChild(0);
  @override
  get body => _fixedChild(1);
}

final class _RowFormalParameter(super._owner, super._row)
    extends _Row
    implements FormalParameter {
  @override
  FormalParameterKind get kind => FormalParameterKind.values[_word(0)];
  @override
  ParameterPrefix get prefix => ParameterPrefix.values[_word(1)];
  @override
  VariableKeyword get keyword => VariableKeyword.values[_word(2)];
  bool _has(int flag) => _word(3) & flag != 0;
  int get _nameIndex => _word(4) + (_has(_formalType) ? 1 : 0);

  @override
  get isCovariant => _has(_formalCovariant);
  @override
  get type => _has(_formalType) ? _fixedChild(_word(4)) : null;
  @override
  get name => _fixedChild(_nameIndex);
  @override
  get functionSuffix =>
      _has(_formalSuffix) ? _fixedChild(_nameIndex + 1) : null;
  @override
  get defaultClause => _has(_formalDefault) ? _trailingChild(1) : null;
  @override
  get metadata => _firstChildren(_word(4));
}

final class _RowFormalParameterList(super._owner, super._row)
    extends _Row
    implements FormalParameterList {
  @override
  get parameters => _allChildren();
}

final class _RowFunctionExpression(super._owner, super._row)
    extends _Row
    implements FunctionExpression {
  @override
  get typeParameters => _optionalChild(0, 3);
  @override
  get parameters => _trailingChild(2);
  @override
  get body => _trailingChild(1);
}

final class _RowFunctionParameterSuffix(super._owner, super._row)
    extends _Row
    implements FunctionParameterSuffix {
  @override
  get typeParameters => _optionalChild(0, 2);
  @override
  get parameters => _trailingChild(1);
  @override
  get questionOffset => _questionAt(0);
}

final class _RowFunctionTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements FunctionTypeAliasDeclaration {
  @override
  get returnType => _node(0);
  @override
  get name => _node(1);
  @override
  get typeParameters => _node(2);
  @override
  get parameters => _node(3);
  @override
  get metadata => _firstChildren(_word(4));
}

final class _RowFunctionTypeAnnotation(super._owner, super._row)
    extends _Row
    implements FunctionTypeAnnotation {
  @override
  get returnType => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get parameters => _node(2);
  @override
  get questionOffset => _questionAt(3);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowFunctionTypeParameter(super._owner, super._row)
    extends _Row
    implements FunctionTypeParameter {
  @override
  FunctionTypeParameterKind get kind =>
      FunctionTypeParameterKind.values[_word(0)];
  @override
  get isCovariant => _flag(1);
  @override
  get type => _node(2);
  @override
  get name => _node(3);
  @override
  get metadata => _firstChildren(_word(4));
}

final class _RowFunctionTypeParameterList(super._owner, super._row)
    extends _Row
    implements FunctionTypeParameterList {
  @override
  get parameters => _allChildren();
}

final class _RowGetterDeclaration(super._owner, super._row)
    extends _Row
    implements GetterDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get isStatic => _flag(1);
  @override
  get returnType => _node(2);
  @override
  get name => _node(3);
  @override
  get body => _node(4);
  @override
  get metadata => _firstChildren(_word(5));
}

final class _RowGuardedPattern(super._owner, super._row)
    extends _Row
    implements GuardedPattern {
  @override
  get pattern => _fixedChild(0);
  @override
  get guard => _fixedChild(1);
}

final class _RowIdentifier(super._owner, super._row)
    extends _Row
    implements Identifier {}

final class _RowIdentifierExpression(super._owner, super._row)
    extends _Row
    implements IdentifierExpression {
  @override
  Identifier get identifier => _firstChild as Identifier;
}

final class _RowIdentifierPattern(super._owner, super._row)
    extends _Row
    implements IdentifierPattern {
  @override
  get name => _fixedChild(0);
}

final class _RowIfElement(super._owner, super._row)
    extends _Row
    implements IfElement {
  @override
  get condition => _node(0);
  @override
  get casePattern => _node(1);
  @override
  get thenElement => _node(2);
  @override
  get elseElement => _node(3);
}

final class _RowIfStatement(super._owner, super._row)
    extends _Row
    implements IfStatement {
  @override
  get condition => _node(0);
  @override
  get casePattern => _node(1);
  @override
  get thenStatement => _node(2);
  @override
  get elseStatement => _node(3);
}

final class _RowImportDirective(super._owner, super._row)
    extends _Row
    implements ImportDirective {
  @override
  get uri => _node(0);
  @override
  get isDeferred => _flag(1);
  @override
  get prefix => _node(2);
  @override
  get configurations => _childSlice(_word(5) + 1, _word(3));
  @override
  get combinators => _lastChildren(_word(4));
  @override
  get metadata => _firstChildren(_word(5));
}

final class _RowIndexExpression(super._owner, super._row)
    extends _Row
    implements IndexExpression {
  @override
  get target => _fixedChild(0);
  @override
  get index => _fixedChild(1);
  @override
  get isNullAware => _word(0) != 0;
}

final class _RowInstanceCreationExpression(super._owner, super._row)
    extends _Row
    implements InstanceCreationExpression {
  @override
  InstanceCreationKind get kind => InstanceCreationKind.values[_word(0)];
  @override
  get typeArguments => _node(1);
  @override
  get constructorName => _node(2);
  @override
  get arguments => _node(3);
  @override
  get name => _firstChildren(_word(4));
}

final class _RowInterpolatedStringExpression(super._owner, super._row)
    extends _Row
    implements InterpolatedStringExpression {
  @override
  get parts => _allChildren();
}

final class _RowInvocationExpression(super._owner, super._row)
    extends _Row
    implements InvocationExpression {
  @override
  get callee => _fixedChild(0);
  @override
  get typeArguments => _optionalChild(1, 3);
  @override
  get arguments => _trailingChild(1);
}

final class _RowLabel(super._owner, super._row) extends _Row implements Label {
  @override
  get name => _fixedChild(0);
}

final class _RowLabeledStatement(super._owner, super._row)
    extends _Row
    implements LabeledStatement {
  @override
  get statement => _node(0);
  @override
  get labels => _firstChildren(_word(1));
}

final class _RowLibraryDirective(super._owner, super._row)
    extends _Row
    implements LibraryDirective {
  @override
  get name => _node(0);
  @override
  get metadata => _firstChildren(_word(1));
}

final class _RowListPattern(super._owner, super._row)
    extends _Row
    implements ListPattern {
  @override
  get typeArguments => _node(0);
  @override
  get elements => _lastChildren(_word(1));
}

final class _RowLiteralExpression(super._owner, super._row)
    extends _Row
    implements LiteralExpression {
  @override
  LiteralKind get kind => LiteralKind.values[_word(0)];
}

final class _RowLocalFunctionDeclaration(super._owner, super._row)
    extends _Row
    implements LocalFunctionDeclaration {
  @override
  get returnType => _node(0);
  @override
  get name => _node(1);
  @override
  get typeParameters => _node(2);
  @override
  get parameters => _node(3);
  @override
  get body => _node(4);
  @override
  get metadata => _firstChildren(_word(5));
}

final class _RowLogicalPattern(super._owner, super._row)
    extends _Row
    implements LogicalPattern {
  @override
  get left => _fixedChild(0);
  @override
  LogicalPatternOperator get op => LogicalPatternOperator.values[_word(0)];
  @override
  get right => _fixedChild(1);
}

final class _RowMapEntryElement(super._owner, super._row)
    extends _Row
    implements MapEntryElement {
  @override
  get key => _fixedChild(0);
  @override
  get value => _fixedChild(1);
  @override
  get isNullAwareKey => _flag(0);
  @override
  get isNullAwareValue => _flag(1);
}

final class _RowMapPattern(super._owner, super._row)
    extends _Row
    implements MapPattern {
  @override
  get typeArguments => _node(0);
  @override
  get elements => _lastChildren(_word(1));
}

final class _RowMapPatternEntry(super._owner, super._row)
    extends _Row
    implements MapPatternEntry {
  @override
  get key => _fixedChild(0);
  @override
  get value => _fixedChild(1);
}

final class _RowMethodDeclaration(super._owner, super._row)
    extends _Row
    implements MethodDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get isStatic => _flag(1);
  @override
  get returnType => _node(2);
  @override
  get name => _node(3);
  @override
  get typeParameters => _node(4);
  @override
  get parameters => _node(5);
  @override
  get body => _node(6);
  @override
  get metadata => _firstChildren(_word(7));
}

final class _RowMissingClassMember(super._owner, super._row)
    extends _Row
    implements MissingClassMember {}

final class _RowMissingExpression(super._owner, super._row)
    extends _Row
    implements MissingExpression {}

final class _RowMissingFunctionBody(super._owner, super._row)
    extends _Row
    implements MissingFunctionBody {}

final class _RowMissingPattern(super._owner, super._row)
    extends _Row
    implements MissingPattern {}

final class _RowMissingStatement(super._owner, super._row)
    extends _Row
    implements MissingStatement {}

final class _RowMissingStringExpression(super._owner, super._row)
    extends _Row
    implements MissingStringExpression {}

final class _RowMissingTopLevelDeclaration(super._owner, super._row)
    extends _Row
    implements MissingTopLevelDeclaration {}

final class _RowMissingTypeAnnotation(super._owner, super._row)
    extends _Row
    implements MissingTypeAnnotation {
  @override
  int? get questionOffset => null;
  @override
  bool get isNullable => false;
}

final class _RowMixinDeclaration(super._owner, super._row)
    extends _Row
    implements MixinDeclaration {
  @override
  get isBase => _flag(0);
  @override
  get name => _node(1);
  @override
  get typeParameters => _node(2);
  @override
  get onClause => _node(3);
  @override
  get implementsClause => _node(4);
  @override
  get isSemicolonBody => _flag(5);
  @override
  get metadata => _firstChildren(_word(6));
  @override
  get members => _lastChildren(_word(7));
}

final class _RowModifiedBlockFunctionBody(super._owner, super._row)
    extends _Row
    implements ModifiedBlockFunctionBody {
  @override
  FunctionBodyModifier get modifier => FunctionBodyModifier.values[_word(0)];
  @override
  get block => _fixedChild(0);
}

final class _RowNamedPatternField(super._owner, super._row)
    extends _Row
    implements NamedPatternField {
  @override
  get name => _optionalChild(0, 2);
  @override
  get pattern => _trailingChild(1);
}

final class _RowNamedRecordField(super._owner, super._row)
    extends _Row
    implements NamedRecordField {
  @override
  get name => _fixedChild(0);
  @override
  get value => _fixedChild(1);
}

final class _RowNamedRecordTypeField(super._owner, super._row)
    extends _Row
    implements NamedRecordTypeField {
  @override
  get name => _node(0);
  @override
  get type => _node(1);
  @override
  get metadata => _firstChildren(_word(2));
}

final class _RowNamedTypeAnnotation(super._owner, super._row)
    extends _Row
    implements NamedTypeAnnotation {
  @override
  Identifier? get prefix {
    final id = _owner._namedTypePrefix(_row);
    return id == null ? null : _owner._at(id) as Identifier;
  }

  @override
  get name => _fixedChild(_word(0) & SyntaxTreeBuilder._typePrefix);
  @override
  get typeArguments => _word(0) & SyntaxTreeBuilder._typeArguments == 0
      ? null
      : _trailingChild<TypeArgumentList>(1);
  @override
  get questionOffset => _owner._namedTypeQuestion(_row);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowNamespaceCombinator(super._owner, super._row)
    extends _Row
    implements NamespaceCombinator {
  @override
  NamespaceCombinatorKind get kind => NamespaceCombinatorKind.values[_word(0)];
  @override
  get names => _allChildren();
}

final class _RowNullAssertPattern(super._owner, super._row)
    extends _Row
    implements NullAssertPattern {
  @override
  get pattern => _fixedChild(0);
}

final class _RowNullAssertionExpression(super._owner, super._row)
    extends _Row
    implements NullAssertionExpression {
  @override
  get operand => _fixedChild(0);
}

final class _RowNullAwareElement(super._owner, super._row)
    extends _Row
    implements NullAwareElement {
  @override
  get expression => _fixedChild(0);
}

final class _RowNullCheckPattern(super._owner, super._row)
    extends _Row
    implements NullCheckPattern {
  @override
  get pattern => _fixedChild(0);
}

final class _RowObjectPattern(super._owner, super._row)
    extends _Row
    implements ObjectPattern {
  @override
  get type => _node(0);
  @override
  get fields => _lastChildren(_word(1));
}

final class _RowOperatorDeclaration(super._owner, super._row)
    extends _Row
    implements OperatorDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get isStatic => _flag(1);
  @override
  get returnType => _node(2);
  @override
  DeclaredOperator get op => DeclaredOperator.values[_word(3)];
  @override
  get parameters => _node(4);
  @override
  get body => _node(5);
  @override
  get metadata => _firstChildren(_word(6));
}

final class _RowParameterDefault(super._owner, super._row)
    extends _Row
    implements ParameterDefault {
  @override
  ParameterDefaultSeparator get separator =>
      ParameterDefaultSeparator.values[_word(0)];
  @override
  get value => _fixedChild(0);
}

final class _RowParenthesizedExpression(super._owner, super._row)
    extends _Row
    implements ParenthesizedExpression {
  @override
  get expression => _fixedChild(0);
}

final class _RowParenthesizedPattern(super._owner, super._row)
    extends _Row
    implements ParenthesizedPattern {
  @override
  get pattern => _fixedChild(0);
}

final class _RowPartDirective(super._owner, super._row)
    extends _Row
    implements PartDirective {
  @override
  get uri => _node(0);
  @override
  get metadata => _firstChildren(_word(1));
}

final class _RowPartOfDirective(super._owner, super._row)
    extends _Row
    implements PartOfDirective {
  @override
  get target => _node(0);
  @override
  get metadata => _firstChildren(_word(1));
}

final class _RowPatternAssignmentExpression(super._owner, super._row)
    extends _Row
    implements PatternAssignmentExpression {
  @override
  get pattern => _fixedChild(0);
  @override
  get value => _fixedChild(1);
}

final class _RowPatternForInBinding(super._owner, super._row)
    extends _Row
    implements PatternForInBinding {
  @override
  get isFinal => _flag(0);
  @override
  get pattern => _node(1);
  @override
  get metadata => _firstChildren(_word(2));
}

final class _RowPatternVariableDeclaration(super._owner, super._row)
    extends _Row
    implements PatternVariableDeclaration {
  @override
  get isFinal => _flag(0);
  @override
  get pattern => _node(1);
  @override
  get initializer => _node(2);
  @override
  get metadata => _firstChildren(_word(3));
}

final class _RowPatternVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements PatternVariableDeclarationStatement {
  @override
  get declaration => _fixedChild(0);
}

final class _RowPositionalRecordTypeField(super._owner, super._row)
    extends _Row
    implements PositionalRecordTypeField {
  @override
  get name => _node(0);
  @override
  get type => _node(1);
  @override
  get metadata => _firstChildren(_word(2));
}

final class _RowPrimaryConstructorBody(super._owner, super._row)
    extends _Row
    implements PrimaryConstructorBody {
  @override
  get body => _node(0);
  @override
  get metadata => _firstChildren(_word(1));
  @override
  get initializers => _lastChildren(_word(2), 1);
}

final class _RowPropertyAccessExpression(super._owner, super._row)
    extends _Row
    implements PropertyAccessExpression {
  @override
  get target => _fixedChild(0);
  @override
  get property => _fixedChild(1);
  @override
  get isNullAware => _flag(0);
}

final class _RowRecordExpression(super._owner, super._row)
    extends _Row
    implements RecordExpression {
  @override
  get hasConstKeyword => _flag(0);
  @override
  get fields => _allChildren();
}

final class _RowRecordPattern(super._owner, super._row)
    extends _Row
    implements RecordPattern {
  @override
  get fields => _allChildren();
}

final class _RowRecordTypeAnnotation(super._owner, super._row)
    extends _Row
    implements RecordTypeAnnotation {
  @override
  get namedFields => _node(0);
  @override
  get positionalFields => _firstChildren(_word(1));
  @override
  get questionOffset => _questionAt(2);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowRecordTypeNamedFields(super._owner, super._row)
    extends _Row
    implements RecordTypeNamedFields {
  @override
  get fields => _allChildren();
}

final class _RowRedirectingConstructorInitializer(super._owner, super._row)
    extends _Row
    implements RedirectingConstructorInitializer {
  @override
  get name => _optionalChild(0, 2);
  @override
  get arguments => _trailingChild(1);
}

final class _RowRelationalPattern(super._owner, super._row)
    extends _Row
    implements RelationalPattern {
  @override
  RelationalPatternOperator get op =>
      RelationalPatternOperator.values[_word(0)];
  @override
  get operand => _fixedChild(0);
}

final class _RowRestPatternElement(super._owner, super._row)
    extends _Row
    implements RestPatternElement {
  @override
  get pattern => _optionalChild(0, 1);
}

final class _RowRethrowStatement(super._owner, super._row)
    extends _Row
    implements RethrowStatement {}

final class _RowReturnStatement(super._owner, super._row)
    extends _Row
    implements ReturnStatement {
  @override
  get expression => _optionalChild(0, 1);
}

final class _RowScriptTag(super._owner, super._row)
    extends _Row
    implements ScriptTag {}

final class _RowSetterDeclaration(super._owner, super._row)
    extends _Row
    implements SetterDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get isStatic => _flag(1);
  @override
  get isCovariant => _flag(2);
  @override
  get returnType => _node(3);
  @override
  get name => _node(4);
  @override
  get parameters => _node(5);
  @override
  get body => _node(6);
  @override
  get metadata => _firstChildren(_word(7));
}

final class _RowSpreadElement(super._owner, super._row)
    extends _Row
    implements SpreadElement {
  @override
  get expression => _fixedChild(0);
  @override
  get isNullAware => _flag(0);
}

final class _RowStringInterpolation(super._owner, super._row)
    extends _Row
    implements StringInterpolation {
  @override
  get expression => _fixedChild(0);
  @override
  get isBraced => _flag(0);
}

final class _RowStringLiteralExpression(super._owner, super._row)
    extends _Row
    implements StringLiteralExpression {}

final class _RowStringText(super._owner, super._row)
    extends _Row
    implements StringText {}

final class _RowSuperConstructorInitializer(super._owner, super._row)
    extends _Row
    implements SuperConstructorInitializer {
  @override
  get name => _optionalChild(0, 2);
  @override
  get arguments => _trailingChild(1);
}

final class _RowSuperExpression(super._owner, super._row)
    extends _Row
    implements SuperExpression {}

final class _RowSwitchExpression(super._owner, super._row)
    extends _Row
    implements SwitchExpression {
  @override
  get expression => _node(0);
  @override
  get cases => _lastChildren(_word(1));
}

final class _RowSwitchExpressionCase(super._owner, super._row)
    extends _Row
    implements SwitchExpressionCase {
  @override
  get pattern => _fixedChild(0);
  @override
  get value => _fixedChild(1);
}

final class _RowSwitchStatement(super._owner, super._row)
    extends _Row
    implements SwitchStatement {
  @override
  get expression => _node(0);
  @override
  get members => _lastChildren(_word(1));
}

final class _RowSwitchStatementMember(super._owner, super._row)
    extends _Row
    implements SwitchStatementMember {
  @override
  get pattern => _node(0);
  @override
  get labels => _firstChildren(_word(1));
  @override
  get statements => _lastChildren(_word(2));
}

final class _RowThisExpression(super._owner, super._row)
    extends _Row
    implements ThisExpression {}

final class _RowThrowExpression(super._owner, super._row)
    extends _Row
    implements ThrowExpression {
  @override
  get expression => _fixedChild(0);
}

final class _RowTopLevelFunctionDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelFunctionDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get returnType => _node(1);
  @override
  get name => _node(2);
  @override
  get typeParameters => _node(3);
  @override
  get parameters => _node(4);
  @override
  get body => _node(5);
  @override
  get metadata => _firstChildren(_word(6));
}

final class _RowTopLevelGetterDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelGetterDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get returnType => _node(1);
  @override
  get name => _node(2);
  @override
  get body => _node(3);
  @override
  get metadata => _firstChildren(_word(4));
}

final class _RowTopLevelSetterDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelSetterDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get returnType => _node(1);
  @override
  get name => _node(2);
  @override
  get parameters => _node(3);
  @override
  get body => _node(4);
  @override
  get metadata => _firstChildren(_word(5));
}

final class _RowTopLevelVariableDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelVariableDeclaration {
  @override
  get isExternal => _flag(0);
  @override
  get variables => _fixedChild(0);
}

final class _RowTryStatement(super._owner, super._row)
    extends _Row
    implements TryStatement {
  @override
  get body => _node(0);
  @override
  get finallyBlock => _node(1);
  @override
  get catchClauses => _childSlice(1, _word(2));
}

final class _RowTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements TypeAliasDeclaration {
  @override
  get name => _node(0);
  @override
  get typeParameters => _node(1);
  @override
  get type => _node(2);
  @override
  get metadata => _firstChildren(_word(3));
}

final class _RowTypeArgumentList(super._owner, super._row)
    extends _Row
    implements TypeArgumentList {
  @override
  get arguments => _allChildren();
}

final class _RowTypeInstantiationExpression(super._owner, super._row)
    extends _Row
    implements TypeInstantiationExpression {
  @override
  get expression => _fixedChild(0);
  @override
  get typeArguments => _fixedChild(1);
}

final class _RowTypeListClause(super._owner, super._row)
    extends _Row
    implements TypeListClause {
  @override
  TypeListClauseKind get kind => TypeListClauseKind.values[_word(0)];
  @override
  get types => _allChildren();
}

final class _RowTypeParameter(super._owner, super._row)
    extends _Row
    implements TypeParameter {
  @override
  get name => _node(0);
  @override
  get bound => _node(1);
  @override
  get metadata => _firstChildren(_word(2));
}

final class _RowTypeParameterList(super._owner, super._row)
    extends _Row
    implements TypeParameterList {
  @override
  get parameters => _allChildren();
}

final class _RowTypeTestExpression(super._owner, super._row)
    extends _Row
    implements TypeTestExpression {
  @override
  get expression => _fixedChild(0);
  @override
  get type => _fixedChild(1);
  @override
  get isNegated => _flag(0);
}

final class _RowUnaryExpression(super._owner, super._row)
    extends _Row
    implements UnaryExpression {
  @override
  UnaryOperator get op => UnaryOperator.values[_word(0)];
  @override
  get operand => _fixedChild(0);
}

final class _RowUpdateExpression(super._owner, super._row)
    extends _Row
    implements UpdateExpression {
  @override
  get operand => _fixedChild(0);
  @override
  UpdateOperator get op => UpdateOperator.values[_word(0)];
  @override
  get isPrefix => _word(1) != 0;
}

final class _RowVariableDeclaration(super._owner, super._row)
    extends _Row
    implements VariableDeclaration {
  @override
  get name => _fixedChild(0);
  @override
  get initializer => _optionalChild(1, 2);
}

final class _RowVariableDeclarationList(super._owner, super._row)
    extends _Row
    implements VariableDeclarationList {
  @override
  VariableKeyword get keyword => VariableKeyword.values[_word(0)];
  @override
  get isLate => _flag(1);
  @override
  get type => _node(2);
  @override
  get metadata => _firstChildren(_word(3));
  @override
  get declarations => _lastChildren(_word(4));
}

final class _RowVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements VariableDeclarationStatement {
  @override
  get variables => _fixedChild(0);
}

final class _RowVariablePattern(super._owner, super._row)
    extends _Row
    implements VariablePattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[_word(0)];
  @override
  get type => _optionalChild(0, 2);
  @override
  get name => _trailingChild(1);
}

final class _RowWhileStatement(super._owner, super._row)
    extends _Row
    implements WhileStatement {
  @override
  get condition => _fixedChild(0);
  @override
  get body => _fixedChild(1);
}

final class _RowWildcardPattern(super._owner, super._row)
    extends _Row
    implements WildcardPattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[_word(0)];
  @override
  get type => _optionalChild(0, 1);
}

final class _RowYieldStatement(super._owner, super._row)
    extends _Row
    implements YieldStatement {
  @override
  get isStar => _flag(0);
  @override
  get expression => _fixedChild(0);
}
