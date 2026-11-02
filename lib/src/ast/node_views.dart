part of 'nodes.dart';

sealed class _Row(this._owner, this._row) implements AstNode {
  final AstArena _owner;
  final int _row;
  @override
  bool operator ==(Object other) =>
      other is _Row && identical(_owner, other._owner) && _row == other._row;
  @override
  int get hashCode => Object.hash(_owner, _row);
  @override
  SourceFile get source => _owner.source;
  @override
  int get start => _owner.starts[_row];
  @override
  int get end => _owner.ends[_row];
  @override
  int get length => end - start;
  @override
  String get text => source.text.substring(start, end);
  @override
  SourceSpan get span => SourceSpan(source, start, end);
  @override
  int get childCount => _owner.edgeOffsets[_row + 1] - _owner.edgeOffsets[_row];
  @override
  AstNode childAt(int i) {
    RangeError.checkValidIndex(i, this, 'index', childCount);
    return _owner.at(_owner.edges.cells[_owner.edgeOffsets[_row] + i]);
  }

  int word(int f) => _owner.fields.cells[_owner.offsets[_row] + f];
  T node<T>(int f) {
    final v = word(f);
    return (v == _nil ? null : _owner.at(v)) as T;
  }

  T integer<T>(int f) {
    final v = word(f);
    return (v == _nil ? null : v) as T;
  }

  T flag<T>(int f) {
    final v = word(f);
    return (v == _nil ? null : v != 0) as T;
  }

  List<T> nodes<T>(int f) {
    final v = word(f);
    return v == _nil ? const [] : _RowList<T>(_owner, v, null);
  }

  List<T> enums<T>(int f, List<Enum> values) {
    final v = word(f);
    return v == _nil ? const [] : _RowList<T>(_owner, v, values);
  }
}

final class _RowList<T>(
  final AstArena _owner,
  final int off,
  final List<Enum>? values,
) extends ListBase<T> {
  @override
  int get length => _owner.extra.cells[off];
  @override
  set length(int n) => throw UnsupportedError('immutable');
  @override
  T operator [](int i) {
    RangeError.checkValidIndex(i, this);
    final v = _owner.extra.cells[off + 1 + i];
    return (values == null ? _owner.at(v) : values![v]) as T;
  }

  @override
  void operator []=(int i, T value) => throw UnsupportedError('immutable');
}

final class _RowAdjacentStringsExpression(super._owner, super._row)
    extends _Row
    implements AdjacentStringsExpression {
  @override
  get strings => nodes(0);
}

final class _RowAnnotation(super._owner, super._row)
    extends _Row
    implements Annotation {
  @override
  get typeArguments => node(0);
  @override
  get constructorName => node(1);
  @override
  get arguments => node(2);
  @override
  get name => nodes(3);
}

final class _RowArgument(super._owner, super._row)
    extends _Row
    implements Argument {
  @override
  get name => node(0);
  @override
  get value => node(1);
}

final class _RowArgumentList(super._owner, super._row)
    extends _Row
    implements ArgumentList {
  @override
  get arguments => nodes(0);
}

final class _RowAssertInitializer(super._owner, super._row)
    extends _Row
    implements AssertInitializer {
  @override
  get condition => node(0);
  @override
  get message => node(1);
}

final class _RowAssertStatement(super._owner, super._row)
    extends _Row
    implements AssertStatement {
  @override
  get condition => node(0);
  @override
  get message => node(1);
}

final class _RowAssignmentExpression(super._owner, super._row)
    extends _Row
    implements AssignmentExpression {
  @override
  get left => node(0);
  @override
  AssignmentOperator get op => AssignmentOperator.values[word(1)];
  @override
  get right => node(2);
}

final class _RowAwaitExpression(super._owner, super._row)
    extends _Row
    implements AwaitExpression {
  @override
  get expression => node(0);
}

final class _RowBinaryExpression(super._owner, super._row)
    extends _Row
    implements BinaryExpression {
  @override
  get left => node(0);
  @override
  BinaryOperator get op => BinaryOperator.values[word(1)];
  @override
  get right => node(2);
}

final class _RowBlockStatement(super._owner, super._row)
    extends _Row
    implements BlockStatement {
  @override
  get statements => nodes(0);
}

final class _RowBreakStatement(super._owner, super._row)
    extends _Row
    implements BreakStatement {
  @override
  get label => node(0);
}

final class _RowCascadeExpression(super._owner, super._row)
    extends _Row
    implements CascadeExpression {
  @override
  get target => node(0);
  @override
  get isNullAware => flag(1);
  @override
  get sections => nodes(2);
}

final class _RowCascadeIndexExpression(super._owner, super._row)
    extends _Row
    implements CascadeIndexExpression {
  @override
  get index => node(0);
}

final class _RowCascadePropertyExpression(super._owner, super._row)
    extends _Row
    implements CascadePropertyExpression {
  @override
  get property => node(0);
}

final class _RowCastExpression(super._owner, super._row)
    extends _Row
    implements CastExpression {
  @override
  get expression => node(0);
  @override
  get type => node(1);
}

final class _RowCastPattern(super._owner, super._row)
    extends _Row
    implements CastPattern {
  @override
  get pattern => node(0);
  @override
  get type => node(1);
}

final class _RowCatchClause(super._owner, super._row)
    extends _Row
    implements CatchClause {
  @override
  get exceptionType => node(0);
  @override
  get exceptionParameter => node(1);
  @override
  get stackTraceParameter => node(2);
  @override
  get body => node(3);
}

final class _RowClassDeclaration(super._owner, super._row)
    extends _Row
    implements ClassDeclaration {
  @override
  get name => node(0);
  @override
  get typeParameters => node(1);
  @override
  get isConst => flag(2);
  @override
  get primaryConstructorName => node(3);
  @override
  get primaryParameters => node(4);
  @override
  get extendsClause => node(5);
  @override
  get withClause => node(6);
  @override
  get implementsClause => node(7);
  @override
  get isSemicolonBody => flag(8);
  @override
  get metadata => nodes(9);
  @override
  get modifiers => enums(10, ClassModifier.values);
  @override
  get members => nodes(11);
}

final class _RowClassTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements ClassTypeAliasDeclaration {
  @override
  get name => node(0);
  @override
  get typeParameters => node(1);
  @override
  get superclass => node(2);
  @override
  get withClause => node(3);
  @override
  get implementsClause => node(4);
  @override
  get metadata => nodes(5);
  @override
  get modifiers => enums(6, ClassModifier.values);
}

final class _RowCollectionExpression(super._owner, super._row)
    extends _Row
    implements CollectionExpression {
  @override
  CollectionLiteralKind get kind => CollectionLiteralKind.values[word(0)];
  @override
  get hasConstKeyword => flag(1);
  @override
  get typeArguments => node(2);
  @override
  get elements => nodes(3);
}

final class _RowCompilationUnit(super._owner, super._row)
    extends _Row
    implements CompilationUnit {
  @override
  get scriptTag => node(0);
  @override
  get members => nodes(1);
}

final class _RowConditionalExpression(super._owner, super._row)
    extends _Row
    implements ConditionalExpression {
  @override
  get condition => node(0);
  @override
  get thenExpression => node(1);
  @override
  get elseExpression => node(2);
}

final class _RowConditionalUri(super._owner, super._row)
    extends _Row
    implements ConditionalUri {
  @override
  get name => node(0);
  @override
  get value => node(1);
  @override
  get uri => node(2);
}

final class _RowConstDotShorthandExpression(super._owner, super._row)
    extends _Row
    implements ConstDotShorthandExpression {
  @override
  get name => node(0);
  @override
  get typeArguments => node(1);
  @override
  get arguments => node(2);
}

final class _RowConstantPattern(super._owner, super._row)
    extends _Row
    implements ConstantPattern {
  @override
  get hasConstKeyword => flag(0);
  @override
  get expression => node(1);
}

final class _RowConstructorDeclaration(super._owner, super._row)
    extends _Row
    implements ConstructorDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get isConst => flag(1);
  @override
  ConstructorKeyword get keyword => ConstructorKeyword.values[word(2)];
  @override
  get parameters => node(3);
  @override
  get body => node(4);
  @override
  get metadata => nodes(5);
  @override
  get name => nodes(6);
  @override
  get initializers => nodes(7);
}

final class _RowContinueStatement(super._owner, super._row)
    extends _Row
    implements ContinueStatement {
  @override
  get label => node(0);
}

final class _RowDeclaredIdentifier(super._owner, super._row)
    extends _Row
    implements DeclaredIdentifier {
  @override
  VariableKeyword get keyword => VariableKeyword.values[word(0)];
  @override
  get type => node(1);
  @override
  get name => node(2);
  @override
  get metadata => nodes(3);
}

final class _RowDoStatement(super._owner, super._row)
    extends _Row
    implements DoStatement {
  @override
  get body => node(0);
  @override
  get condition => node(1);
}

final class _RowDotShorthandExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandExpression {
  @override
  get expression => node(0);
}

final class _RowDotShorthandReferenceExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandReferenceExpression {
  @override
  get name => node(0);
}

final class _RowDottedName(super._owner, super._row)
    extends _Row
    implements DottedName {
  @override
  get components => nodes(0);
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
  get name => node(0);
  @override
  get typeArguments => node(1);
  @override
  get constructorName => node(2);
  @override
  get arguments => node(3);
  @override
  get metadata => nodes(4);
}

final class _RowEnumDeclaration(super._owner, super._row)
    extends _Row
    implements EnumDeclaration {
  @override
  get name => node(0);
  @override
  get typeParameters => node(1);
  @override
  get isConst => flag(2);
  @override
  get primaryConstructorName => node(3);
  @override
  get primaryParameters => node(4);
  @override
  get withClause => node(5);
  @override
  get implementsClause => node(6);
  @override
  get isSemicolonBody => flag(7);
  @override
  get hasMemberSeparator => flag(8);
  @override
  get metadata => nodes(9);
  @override
  get constants => nodes(10);
  @override
  get members => nodes(11);
}

final class _RowExportDirective(super._owner, super._row)
    extends _Row
    implements ExportDirective {
  @override
  get uri => node(0);
  @override
  get configurations => nodes(1);
  @override
  get combinators => nodes(2);
  @override
  get metadata => nodes(3);
}

final class _RowExpressionFunctionBody(super._owner, super._row)
    extends _Row
    implements ExpressionFunctionBody {
  @override
  get isAsync => flag(0);
  @override
  get expression => node(1);
}

final class _RowExpressionStatement(super._owner, super._row)
    extends _Row
    implements ExpressionStatement {
  @override
  get expression => node(0);
}

final class _RowExtendsClause(super._owner, super._row)
    extends _Row
    implements ExtendsClause {
  @override
  get superclass => node(0);
}

final class _RowExtensionDeclaration(super._owner, super._row)
    extends _Row
    implements ExtensionDeclaration {
  @override
  get name => node(0);
  @override
  get typeParameters => node(1);
  @override
  get onType => node(2);
  @override
  get isSemicolonBody => flag(3);
  @override
  get metadata => nodes(4);
  @override
  get members => nodes(5);
}

final class _RowExtensionTypeDeclaration(super._owner, super._row)
    extends _Row
    implements ExtensionTypeDeclaration {
  @override
  get isConst => flag(0);
  @override
  get name => node(1);
  @override
  get typeParameters => node(2);
  @override
  get primaryConstructorName => node(3);
  @override
  get primaryParameters => node(4);
  @override
  get implementsClause => node(5);
  @override
  get isSemicolonBody => flag(6);
  @override
  get metadata => nodes(7);
  @override
  get members => nodes(8);
}

final class _RowFactoryRedirectBody(super._owner, super._row)
    extends _Row
    implements FactoryRedirectBody {
  @override
  get typeArguments => node(0);
  @override
  get constructorName => node(1);
  @override
  get name => nodes(2);
}

final class _RowFieldDeclaration(super._owner, super._row)
    extends _Row
    implements FieldDeclaration {
  @override
  get isStatic => flag(0);
  @override
  get isAbstract => flag(1);
  @override
  get isExternal => flag(2);
  @override
  get isCovariant => flag(3);
  @override
  get variables => node(4);
}

final class _RowFieldInitializer(super._owner, super._row)
    extends _Row
    implements FieldInitializer {
  @override
  get hasThis => flag(0);
  @override
  get name => node(1);
  @override
  get value => node(2);
}

final class _RowForElement(super._owner, super._row)
    extends _Row
    implements ForElement {
  @override
  get isAwait => flag(0);
  @override
  get parts => node(1);
  @override
  get body => node(2);
}

final class _RowForInParts(super._owner, super._row)
    extends _Row
    implements ForInParts {
  @override
  get target => node(0);
  @override
  get iterable => node(1);
}

final class _RowForParts(super._owner, super._row)
    extends _Row
    implements ForParts {
  @override
  get initializer => node(0);
  @override
  get condition => node(1);
  @override
  get updaters => nodes(2);
}

final class _RowForStatement(super._owner, super._row)
    extends _Row
    implements ForStatement {
  @override
  get isAwait => flag(0);
  @override
  get parts => node(1);
  @override
  get body => node(2);
}

final class _RowFormalParameter(super._owner, super._row)
    extends _Row
    implements FormalParameter {
  @override
  FormalParameterKind get kind => FormalParameterKind.values[word(0)];
  @override
  ParameterPrefix get prefix => ParameterPrefix.values[word(1)];
  @override
  VariableKeyword get keyword => VariableKeyword.values[word(2)];
  @override
  get isCovariant => flag(3);
  @override
  get type => node(4);
  @override
  get name => node(5);
  @override
  get functionSuffix => node(6);
  @override
  get defaultClause => node(7);
  @override
  get metadata => nodes(8);
}

final class _RowFormalParameterList(super._owner, super._row)
    extends _Row
    implements FormalParameterList {
  @override
  get parameters => nodes(0);
}

final class _RowFunctionExpression(super._owner, super._row)
    extends _Row
    implements FunctionExpression {
  @override
  get typeParameters => node(0);
  @override
  get parameters => node(1);
  @override
  get body => node(2);
}

final class _RowFunctionParameterSuffix(super._owner, super._row)
    extends _Row
    implements FunctionParameterSuffix {
  @override
  get typeParameters => node(0);
  @override
  get parameters => node(1);
  @override
  get questionOffset => integer(2);
}

final class _RowFunctionTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements FunctionTypeAliasDeclaration {
  @override
  get returnType => node(0);
  @override
  get name => node(1);
  @override
  get typeParameters => node(2);
  @override
  get parameters => node(3);
  @override
  get metadata => nodes(4);
}

final class _RowFunctionTypeAnnotation(super._owner, super._row)
    extends _Row
    implements FunctionTypeAnnotation {
  @override
  get returnType => node(0);
  @override
  get typeParameters => node(1);
  @override
  get parameters => node(2);
  @override
  get questionOffset => integer(3);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowFunctionTypeParameter(super._owner, super._row)
    extends _Row
    implements FunctionTypeParameter {
  @override
  FunctionTypeParameterKind get kind =>
      FunctionTypeParameterKind.values[word(0)];
  @override
  get isCovariant => flag(1);
  @override
  get type => node(2);
  @override
  get name => node(3);
  @override
  get metadata => nodes(4);
}

final class _RowFunctionTypeParameterList(super._owner, super._row)
    extends _Row
    implements FunctionTypeParameterList {
  @override
  get parameters => nodes(0);
}

final class _RowGetterDeclaration(super._owner, super._row)
    extends _Row
    implements GetterDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get isStatic => flag(1);
  @override
  get returnType => node(2);
  @override
  get name => node(3);
  @override
  get body => node(4);
  @override
  get metadata => nodes(5);
}

final class _RowGuardedPattern(super._owner, super._row)
    extends _Row
    implements GuardedPattern {
  @override
  get pattern => node(0);
  @override
  get guard => node(1);
}

final class _RowIdentifier(super._owner, super._row)
    extends _Row
    implements Identifier {}

final class _RowIdentifierExpression(super._owner, super._row)
    extends _Row
    implements IdentifierExpression {
  @override
  get identifier => node(0);
}

final class _RowIdentifierPattern(super._owner, super._row)
    extends _Row
    implements IdentifierPattern {
  @override
  get name => node(0);
}

final class _RowIfElement(super._owner, super._row)
    extends _Row
    implements IfElement {
  @override
  get condition => node(0);
  @override
  get casePattern => node(1);
  @override
  get thenElement => node(2);
  @override
  get elseElement => node(3);
}

final class _RowIfStatement(super._owner, super._row)
    extends _Row
    implements IfStatement {
  @override
  get condition => node(0);
  @override
  get casePattern => node(1);
  @override
  get thenStatement => node(2);
  @override
  get elseStatement => node(3);
}

final class _RowImportDirective(super._owner, super._row)
    extends _Row
    implements ImportDirective {
  @override
  get uri => node(0);
  @override
  get isDeferred => flag(1);
  @override
  get prefix => node(2);
  @override
  get configurations => nodes(3);
  @override
  get combinators => nodes(4);
  @override
  get metadata => nodes(5);
}

final class _RowIndexExpression(super._owner, super._row)
    extends _Row
    implements IndexExpression {
  @override
  get target => node(0);
  @override
  get index => node(1);
  @override
  get isNullAware => flag(2);
}

final class _RowInstanceCreationExpression(super._owner, super._row)
    extends _Row
    implements InstanceCreationExpression {
  @override
  InstanceCreationKind get kind => InstanceCreationKind.values[word(0)];
  @override
  get typeArguments => node(1);
  @override
  get constructorName => node(2);
  @override
  get arguments => node(3);
  @override
  get name => nodes(4);
}

final class _RowInterpolatedStringExpression(super._owner, super._row)
    extends _Row
    implements InterpolatedStringExpression {
  @override
  get parts => nodes(0);
}

final class _RowInvocationExpression(super._owner, super._row)
    extends _Row
    implements InvocationExpression {
  @override
  get callee => node(0);
  @override
  get typeArguments => node(1);
  @override
  get arguments => node(2);
}

final class _RowLabel(super._owner, super._row) extends _Row implements Label {
  @override
  get name => node(0);
}

final class _RowLabeledStatement(super._owner, super._row)
    extends _Row
    implements LabeledStatement {
  @override
  get statement => node(0);
  @override
  get labels => nodes(1);
}

final class _RowLibraryDirective(super._owner, super._row)
    extends _Row
    implements LibraryDirective {
  @override
  get name => node(0);
  @override
  get metadata => nodes(1);
}

final class _RowListPattern(super._owner, super._row)
    extends _Row
    implements ListPattern {
  @override
  get typeArguments => node(0);
  @override
  get elements => nodes(1);
}

final class _RowLiteralExpression(super._owner, super._row)
    extends _Row
    implements LiteralExpression {
  @override
  LiteralKind get kind => LiteralKind.values[word(0)];
}

final class _RowLocalFunctionDeclaration(super._owner, super._row)
    extends _Row
    implements LocalFunctionDeclaration {
  @override
  get returnType => node(0);
  @override
  get name => node(1);
  @override
  get typeParameters => node(2);
  @override
  get parameters => node(3);
  @override
  get body => node(4);
  @override
  get metadata => nodes(5);
}

final class _RowLogicalPattern(super._owner, super._row)
    extends _Row
    implements LogicalPattern {
  @override
  get left => node(0);
  @override
  LogicalPatternOperator get op => LogicalPatternOperator.values[word(1)];
  @override
  get right => node(2);
}

final class _RowMapEntryElement(super._owner, super._row)
    extends _Row
    implements MapEntryElement {
  @override
  get key => node(0);
  @override
  get value => node(1);
  @override
  get isNullAwareKey => flag(2);
  @override
  get isNullAwareValue => flag(3);
}

final class _RowMapPattern(super._owner, super._row)
    extends _Row
    implements MapPattern {
  @override
  get typeArguments => node(0);
  @override
  get elements => nodes(1);
}

final class _RowMapPatternEntry(super._owner, super._row)
    extends _Row
    implements MapPatternEntry {
  @override
  get key => node(0);
  @override
  get value => node(1);
}

final class _RowMethodDeclaration(super._owner, super._row)
    extends _Row
    implements MethodDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get isStatic => flag(1);
  @override
  get returnType => node(2);
  @override
  get name => node(3);
  @override
  get typeParameters => node(4);
  @override
  get parameters => node(5);
  @override
  get body => node(6);
  @override
  get metadata => nodes(7);
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
  get questionOffset => integer(0);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowMixinDeclaration(super._owner, super._row)
    extends _Row
    implements MixinDeclaration {
  @override
  get isBase => flag(0);
  @override
  get name => node(1);
  @override
  get typeParameters => node(2);
  @override
  get onClause => node(3);
  @override
  get implementsClause => node(4);
  @override
  get isSemicolonBody => flag(5);
  @override
  get metadata => nodes(6);
  @override
  get members => nodes(7);
}

final class _RowModifiedBlockFunctionBody(super._owner, super._row)
    extends _Row
    implements ModifiedBlockFunctionBody {
  @override
  FunctionBodyModifier get modifier => FunctionBodyModifier.values[word(0)];
  @override
  get block => node(1);
}

final class _RowNamedPatternField(super._owner, super._row)
    extends _Row
    implements NamedPatternField {
  @override
  get name => node(0);
  @override
  get pattern => node(1);
}

final class _RowNamedRecordField(super._owner, super._row)
    extends _Row
    implements NamedRecordField {
  @override
  get name => node(0);
  @override
  get value => node(1);
}

final class _RowNamedRecordTypeField(super._owner, super._row)
    extends _Row
    implements NamedRecordTypeField {
  @override
  get name => node(0);
  @override
  get type => node(1);
  @override
  get metadata => nodes(2);
}

final class _RowNamedTypeAnnotation(super._owner, super._row)
    extends _Row
    implements NamedTypeAnnotation {
  @override
  get prefix => node(0);
  @override
  get name => node(1);
  @override
  get typeArguments => node(2);
  @override
  get questionOffset => integer(3);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowNamespaceCombinator(super._owner, super._row)
    extends _Row
    implements NamespaceCombinator {
  @override
  NamespaceCombinatorKind get kind => NamespaceCombinatorKind.values[word(0)];
  @override
  get names => nodes(1);
}

final class _RowNullAssertPattern(super._owner, super._row)
    extends _Row
    implements NullAssertPattern {
  @override
  get pattern => node(0);
}

final class _RowNullAssertionExpression(super._owner, super._row)
    extends _Row
    implements NullAssertionExpression {
  @override
  get operand => node(0);
}

final class _RowNullAwareElement(super._owner, super._row)
    extends _Row
    implements NullAwareElement {
  @override
  get expression => node(0);
}

final class _RowNullCheckPattern(super._owner, super._row)
    extends _Row
    implements NullCheckPattern {
  @override
  get pattern => node(0);
}

final class _RowObjectPattern(super._owner, super._row)
    extends _Row
    implements ObjectPattern {
  @override
  get type => node(0);
  @override
  get fields => nodes(1);
}

final class _RowOperatorDeclaration(super._owner, super._row)
    extends _Row
    implements OperatorDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get isStatic => flag(1);
  @override
  get returnType => node(2);
  @override
  DeclaredOperator get op => DeclaredOperator.values[word(3)];
  @override
  get parameters => node(4);
  @override
  get body => node(5);
  @override
  get metadata => nodes(6);
}

final class _RowParameterDefault(super._owner, super._row)
    extends _Row
    implements ParameterDefault {
  @override
  ParameterDefaultSeparator get separator =>
      ParameterDefaultSeparator.values[word(0)];
  @override
  get value => node(1);
}

final class _RowParenthesizedExpression(super._owner, super._row)
    extends _Row
    implements ParenthesizedExpression {
  @override
  get expression => node(0);
}

final class _RowParenthesizedPattern(super._owner, super._row)
    extends _Row
    implements ParenthesizedPattern {
  @override
  get pattern => node(0);
}

final class _RowPartDirective(super._owner, super._row)
    extends _Row
    implements PartDirective {
  @override
  get uri => node(0);
  @override
  get metadata => nodes(1);
}

final class _RowPartOfDirective(super._owner, super._row)
    extends _Row
    implements PartOfDirective {
  @override
  get target => node(0);
  @override
  get metadata => nodes(1);
}

final class _RowPatternAssignmentExpression(super._owner, super._row)
    extends _Row
    implements PatternAssignmentExpression {
  @override
  get pattern => node(0);
  @override
  get value => node(1);
}

final class _RowPatternForInBinding(super._owner, super._row)
    extends _Row
    implements PatternForInBinding {
  @override
  get isFinal => flag(0);
  @override
  get pattern => node(1);
  @override
  get metadata => nodes(2);
}

final class _RowPatternVariableDeclaration(super._owner, super._row)
    extends _Row
    implements PatternVariableDeclaration {
  @override
  get isFinal => flag(0);
  @override
  get pattern => node(1);
  @override
  get initializer => node(2);
  @override
  get metadata => nodes(3);
}

final class _RowPatternVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements PatternVariableDeclarationStatement {
  @override
  get declaration => node(0);
}

final class _RowPositionalRecordTypeField(super._owner, super._row)
    extends _Row
    implements PositionalRecordTypeField {
  @override
  get name => node(0);
  @override
  get type => node(1);
  @override
  get metadata => nodes(2);
}

final class _RowPrimaryConstructorBody(super._owner, super._row)
    extends _Row
    implements PrimaryConstructorBody {
  @override
  get body => node(0);
  @override
  get metadata => nodes(1);
  @override
  get initializers => nodes(2);
}

final class _RowPropertyAccessExpression(super._owner, super._row)
    extends _Row
    implements PropertyAccessExpression {
  @override
  get target => node(0);
  @override
  get property => node(1);
  @override
  get isNullAware => flag(2);
}

final class _RowRecordExpression(super._owner, super._row)
    extends _Row
    implements RecordExpression {
  @override
  get hasConstKeyword => flag(0);
  @override
  get fields => nodes(1);
}

final class _RowRecordPattern(super._owner, super._row)
    extends _Row
    implements RecordPattern {
  @override
  get fields => nodes(0);
}

final class _RowRecordTypeAnnotation(super._owner, super._row)
    extends _Row
    implements RecordTypeAnnotation {
  @override
  get namedFields => node(0);
  @override
  get positionalFields => nodes(1);
  @override
  get questionOffset => integer(2);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowRecordTypeNamedFields(super._owner, super._row)
    extends _Row
    implements RecordTypeNamedFields {
  @override
  get fields => nodes(0);
}

final class _RowRedirectingConstructorInitializer(super._owner, super._row)
    extends _Row
    implements RedirectingConstructorInitializer {
  @override
  get name => node(0);
  @override
  get arguments => node(1);
}

final class _RowRelationalPattern(super._owner, super._row)
    extends _Row
    implements RelationalPattern {
  @override
  RelationalPatternOperator get op => RelationalPatternOperator.values[word(0)];
  @override
  get operand => node(1);
}

final class _RowRestPatternElement(super._owner, super._row)
    extends _Row
    implements RestPatternElement {
  @override
  get pattern => node(0);
}

final class _RowRethrowStatement(super._owner, super._row)
    extends _Row
    implements RethrowStatement {}

final class _RowReturnStatement(super._owner, super._row)
    extends _Row
    implements ReturnStatement {
  @override
  get expression => node(0);
}

final class _RowScriptTag(super._owner, super._row)
    extends _Row
    implements ScriptTag {}

final class _RowSetterDeclaration(super._owner, super._row)
    extends _Row
    implements SetterDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get isStatic => flag(1);
  @override
  get isCovariant => flag(2);
  @override
  get returnType => node(3);
  @override
  get name => node(4);
  @override
  get parameters => node(5);
  @override
  get body => node(6);
  @override
  get metadata => nodes(7);
}

final class _RowSpreadElement(super._owner, super._row)
    extends _Row
    implements SpreadElement {
  @override
  get expression => node(0);
  @override
  get isNullAware => flag(1);
}

final class _RowStringInterpolation(super._owner, super._row)
    extends _Row
    implements StringInterpolation {
  @override
  get expression => node(0);
  @override
  get isBraced => flag(1);
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
  get name => node(0);
  @override
  get arguments => node(1);
}

final class _RowSuperExpression(super._owner, super._row)
    extends _Row
    implements SuperExpression {}

final class _RowSwitchExpression(super._owner, super._row)
    extends _Row
    implements SwitchExpression {
  @override
  get expression => node(0);
  @override
  get cases => nodes(1);
}

final class _RowSwitchExpressionCase(super._owner, super._row)
    extends _Row
    implements SwitchExpressionCase {
  @override
  get pattern => node(0);
  @override
  get value => node(1);
}

final class _RowSwitchStatement(super._owner, super._row)
    extends _Row
    implements SwitchStatement {
  @override
  get expression => node(0);
  @override
  get members => nodes(1);
}

final class _RowSwitchStatementMember(super._owner, super._row)
    extends _Row
    implements SwitchStatementMember {
  @override
  get pattern => node(0);
  @override
  get labels => nodes(1);
  @override
  get statements => nodes(2);
}

final class _RowThisExpression(super._owner, super._row)
    extends _Row
    implements ThisExpression {}

final class _RowThrowExpression(super._owner, super._row)
    extends _Row
    implements ThrowExpression {
  @override
  get expression => node(0);
}

final class _RowTopLevelFunctionDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelFunctionDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get returnType => node(1);
  @override
  get name => node(2);
  @override
  get typeParameters => node(3);
  @override
  get parameters => node(4);
  @override
  get body => node(5);
  @override
  get metadata => nodes(6);
}

final class _RowTopLevelGetterDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelGetterDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get returnType => node(1);
  @override
  get name => node(2);
  @override
  get body => node(3);
  @override
  get metadata => nodes(4);
}

final class _RowTopLevelSetterDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelSetterDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get returnType => node(1);
  @override
  get name => node(2);
  @override
  get parameters => node(3);
  @override
  get body => node(4);
  @override
  get metadata => nodes(5);
}

final class _RowTopLevelVariableDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelVariableDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get variables => node(1);
}

final class _RowTryStatement(super._owner, super._row)
    extends _Row
    implements TryStatement {
  @override
  get body => node(0);
  @override
  get finallyBlock => node(1);
  @override
  get catchClauses => nodes(2);
}

final class _RowTypeAliasDeclaration(super._owner, super._row)
    extends _Row
    implements TypeAliasDeclaration {
  @override
  get name => node(0);
  @override
  get typeParameters => node(1);
  @override
  get type => node(2);
  @override
  get metadata => nodes(3);
}

final class _RowTypeArgumentList(super._owner, super._row)
    extends _Row
    implements TypeArgumentList {
  @override
  get arguments => nodes(0);
}

final class _RowTypeInstantiationExpression(super._owner, super._row)
    extends _Row
    implements TypeInstantiationExpression {
  @override
  get expression => node(0);
  @override
  get typeArguments => node(1);
}

final class _RowTypeListClause(super._owner, super._row)
    extends _Row
    implements TypeListClause {
  @override
  TypeListClauseKind get kind => TypeListClauseKind.values[word(0)];
  @override
  get types => nodes(1);
}

final class _RowTypeParameter(super._owner, super._row)
    extends _Row
    implements TypeParameter {
  @override
  get name => node(0);
  @override
  get bound => node(1);
  @override
  get metadata => nodes(2);
}

final class _RowTypeParameterList(super._owner, super._row)
    extends _Row
    implements TypeParameterList {
  @override
  get parameters => nodes(0);
}

final class _RowTypeTestExpression(super._owner, super._row)
    extends _Row
    implements TypeTestExpression {
  @override
  get expression => node(0);
  @override
  get type => node(1);
  @override
  get isNegated => flag(2);
}

final class _RowUnaryExpression(super._owner, super._row)
    extends _Row
    implements UnaryExpression {
  @override
  UnaryOperator get op => UnaryOperator.values[word(0)];
  @override
  get operand => node(1);
}

final class _RowUpdateExpression(super._owner, super._row)
    extends _Row
    implements UpdateExpression {
  @override
  get operand => node(0);
  @override
  UpdateOperator get op => UpdateOperator.values[word(1)];
  @override
  get isPrefix => flag(2);
}

final class _RowVariableDeclaration(super._owner, super._row)
    extends _Row
    implements VariableDeclaration {
  @override
  get name => node(0);
  @override
  get initializer => node(1);
}

final class _RowVariableDeclarationList(super._owner, super._row)
    extends _Row
    implements VariableDeclarationList {
  @override
  VariableKeyword get keyword => VariableKeyword.values[word(0)];
  @override
  get isLate => flag(1);
  @override
  get type => node(2);
  @override
  get metadata => nodes(3);
  @override
  get declarations => nodes(4);
}

final class _RowVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements VariableDeclarationStatement {
  @override
  get variables => node(0);
}

final class _RowVariablePattern(super._owner, super._row)
    extends _Row
    implements VariablePattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[word(0)];
  @override
  get type => node(1);
  @override
  get name => node(2);
}

final class _RowWhileStatement(super._owner, super._row)
    extends _Row
    implements WhileStatement {
  @override
  get condition => node(0);
  @override
  get body => node(1);
}

final class _RowWildcardPattern(super._owner, super._row)
    extends _Row
    implements WildcardPattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[word(0)];
  @override
  get type => node(1);
}

final class _RowYieldStatement(super._owner, super._row)
    extends _Row
    implements YieldStatement {
  @override
  get isStar => flag(0);
  @override
  get expression => node(1);
}
