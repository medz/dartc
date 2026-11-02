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
  int get childCount => _owner.childCount(_row);
  @override
  AstNode childAt(int i) {
    RangeError.checkValidIndex(i, this, 'index', childCount);
    return _owner.at(_owner.childIndex(_row, i));
  }

  T fixedChild<T>(int position) =>
      _owner.at(_owner.childIndex(_row, position)) as T;
  T trailingChild<T>(int fromEnd) =>
      _owner.at(_owner.trailingChild(_row, fromEnd)) as T;
  T optionalChild<T>(int index, int fullCount) {
    final id = _owner.optionalChild(_row, index, fullCount);
    return (id == null ? null : _owner.at(id)) as T;
  }

  List<T> allChildren<T>() => _RowList<T>(
    _owner,
    _owner.edges.cells,
    _owner.edgeOffsets[_row],
    childCount,
    null,
  );

  int word(int f) => _owner.fields.cells[_owner.offsets[_row] + f];
  T node<T>(int f) {
    final v = word(f);
    return (v == _nil ? null : _owner.at(v)) as T;
  }

  int? questionAt(int field) {
    final distance = word(field);
    return distance == _nil ? null : end - distance;
  }

  T flag<T>(int f) {
    final v = word(f);
    return (v == _nil ? null : v != 0) as T;
  }

  List<T> firstChildren<T>(int length) => childSlice(0, length);
  List<T> lastChildren<T>(int length, [int skip = 0]) =>
      childSlice(childCount - skip - length, length);
  List<T> childSlice<T>(int from, int length) => length == 0
      ? const []
      : _RowList<T>(
          _owner,
          _owner.edges.cells,
          _owner.edgeOffsets[_row] + from,
          length,
          null,
        );
  List<T> enums<T>(int offset, int length, List<Enum> values) => length == 0
      ? const []
      : _RowList<T>(
          _owner,
          _owner.fields.cells,
          _owner.offsets[_row] + offset,
          length,
          values,
        );
}

final class _RowList<T>(
  final AstArena _owner,
  final Uint32List cells,
  final int off,
  final int count,
  final List<Enum>? values,
) extends ListBase<T> {
  @override
  int get length => count;
  @override
  set length(int n) => throw UnsupportedError('immutable');
  @override
  T operator [](int i) {
    RangeError.checkValidIndex(i, this);
    final v = cells[off + i];
    return (values == null ? _owner.at(v) : values![v]) as T;
  }

  @override
  void operator []=(int i, T value) => throw UnsupportedError('immutable');
}

final class _RowAdjacentStringsExpression(super._owner, super._row)
    extends _Row
    implements AdjacentStringsExpression {
  @override
  get strings => allChildren();
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
  get name => firstChildren(word(3));
}

final class _RowArgument(super._owner, super._row)
    extends _Row
    implements Argument {
  @override
  get name => optionalChild(0, 2);
  @override
  get value => trailingChild(1);
}

final class _RowArgumentList(super._owner, super._row)
    extends _Row
    implements ArgumentList {
  @override
  get arguments => allChildren();
}

final class _RowAssertInitializer(super._owner, super._row)
    extends _Row
    implements AssertInitializer {
  @override
  get condition => fixedChild(0);
  @override
  get message => optionalChild(1, 2);
}

final class _RowAssertStatement(super._owner, super._row)
    extends _Row
    implements AssertStatement {
  @override
  get condition => fixedChild(0);
  @override
  get message => optionalChild(1, 2);
}

final class _RowAssignmentExpression(super._owner, super._row)
    extends _Row
    implements AssignmentExpression {
  @override
  get left => fixedChild(0);
  @override
  AssignmentOperator get op => AssignmentOperator.values[word(0)];
  @override
  get right => fixedChild(1);
}

final class _RowAwaitExpression(super._owner, super._row)
    extends _Row
    implements AwaitExpression {
  @override
  get expression => fixedChild(0);
}

final class _RowBinaryExpression(super._owner, super._row)
    extends _Row
    implements BinaryExpression {
  @override
  get left => fixedChild(0);
  @override
  BinaryOperator get op => BinaryOperator.values[word(0)];
  @override
  get right => fixedChild(1);
}

final class _RowBlockStatement(super._owner, super._row)
    extends _Row
    implements BlockStatement {
  @override
  get statements => allChildren();
}

final class _RowBreakStatement(super._owner, super._row)
    extends _Row
    implements BreakStatement {
  @override
  get label => optionalChild(0, 1);
}

final class _RowCascadeExpression(super._owner, super._row)
    extends _Row
    implements CascadeExpression {
  @override
  get target => node(0);
  @override
  get isNullAware => flag(1);
  @override
  get sections => lastChildren(word(2));
}

final class _RowCascadeIndexExpression(super._owner, super._row)
    extends _Row
    implements CascadeIndexExpression {
  @override
  get index => fixedChild(0);
}

final class _RowCascadePropertyExpression(super._owner, super._row)
    extends _Row
    implements CascadePropertyExpression {
  @override
  get property => fixedChild(0);
}

final class _RowCastExpression(super._owner, super._row)
    extends _Row
    implements CastExpression {
  @override
  get expression => fixedChild(0);
  @override
  get type => fixedChild(1);
}

final class _RowCastPattern(super._owner, super._row)
    extends _Row
    implements CastPattern {
  @override
  get pattern => fixedChild(0);
  @override
  get type => fixedChild(1);
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
  get metadata => firstChildren(word(9));
  @override
  get modifiers => enums(12, word(10), ClassModifier.values);
  @override
  get members => lastChildren(word(11));
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
  get metadata => firstChildren(word(5));
  @override
  get modifiers => enums(7, word(6), ClassModifier.values);
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
  get elements => lastChildren(word(3));
}

final class _RowCompilationUnit(super._owner, super._row)
    extends _Row
    implements CompilationUnit {
  @override
  get scriptTag => node(0);
  @override
  get members => lastChildren(word(1));
}

final class _RowConditionalExpression(super._owner, super._row)
    extends _Row
    implements ConditionalExpression {
  @override
  get condition => fixedChild(0);
  @override
  get thenExpression => fixedChild(1);
  @override
  get elseExpression => fixedChild(2);
}

final class _RowConditionalUri(super._owner, super._row)
    extends _Row
    implements ConditionalUri {
  @override
  get name => fixedChild(0);
  @override
  get value => optionalChild(1, 3);
  @override
  get uri => trailingChild(1);
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
  get expression => fixedChild(0);
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
  get metadata => firstChildren(word(5));
  @override
  get name => childSlice(word(5), word(6));
  @override
  get initializers => lastChildren(word(7), 1);
}

final class _RowContinueStatement(super._owner, super._row)
    extends _Row
    implements ContinueStatement {
  @override
  get label => optionalChild(0, 1);
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
  get metadata => firstChildren(word(3));
}

final class _RowDoStatement(super._owner, super._row)
    extends _Row
    implements DoStatement {
  @override
  get body => fixedChild(0);
  @override
  get condition => fixedChild(1);
}

final class _RowDotShorthandExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandExpression {
  @override
  get expression => fixedChild(0);
}

final class _RowDotShorthandReferenceExpression(super._owner, super._row)
    extends _Row
    implements DotShorthandReferenceExpression {
  @override
  get name => fixedChild(0);
}

final class _RowDottedName(super._owner, super._row)
    extends _Row
    implements DottedName {
  @override
  get components => allChildren();
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
  get metadata => firstChildren(word(4));
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
  get metadata => firstChildren(word(9));
  @override
  get constants => lastChildren(word(10), word(11));
  @override
  get members => lastChildren(word(11));
}

final class _RowExportDirective(super._owner, super._row)
    extends _Row
    implements ExportDirective {
  @override
  get uri => node(0);
  @override
  get configurations => lastChildren(word(1), word(2));
  @override
  get combinators => lastChildren(word(2));
  @override
  get metadata => firstChildren(word(3));
}

final class _RowExpressionFunctionBody(super._owner, super._row)
    extends _Row
    implements ExpressionFunctionBody {
  @override
  get isAsync => flag(0);
  @override
  get expression => fixedChild(0);
}

final class _RowExpressionStatement(super._owner, super._row)
    extends _Row
    implements ExpressionStatement {
  @override
  get expression => fixedChild(0);
}

final class _RowExtendsClause(super._owner, super._row)
    extends _Row
    implements ExtendsClause {
  @override
  get superclass => fixedChild(0);
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
  get metadata => firstChildren(word(4));
  @override
  get members => lastChildren(word(5));
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
  get metadata => firstChildren(word(7));
  @override
  get members => lastChildren(word(8));
}

final class _RowFactoryRedirectBody(super._owner, super._row)
    extends _Row
    implements FactoryRedirectBody {
  @override
  get typeArguments => node(0);
  @override
  get constructorName => node(1);
  @override
  get name => firstChildren(word(2));
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
  get variables => fixedChild(0);
}

final class _RowFieldInitializer(super._owner, super._row)
    extends _Row
    implements FieldInitializer {
  @override
  get hasThis => flag(0);
  @override
  get name => fixedChild(0);
  @override
  get value => fixedChild(1);
}

final class _RowForElement(super._owner, super._row)
    extends _Row
    implements ForElement {
  @override
  get isAwait => flag(0);
  @override
  get parts => fixedChild(0);
  @override
  get body => fixedChild(1);
}

final class _RowForInParts(super._owner, super._row)
    extends _Row
    implements ForInParts {
  @override
  get target => fixedChild(0);
  @override
  get iterable => fixedChild(1);
}

final class _RowForParts(super._owner, super._row)
    extends _Row
    implements ForParts {
  @override
  get initializer => node(0);
  @override
  get condition => node(1);
  @override
  get updaters => lastChildren(word(2));
}

final class _RowForStatement(super._owner, super._row)
    extends _Row
    implements ForStatement {
  @override
  get isAwait => flag(0);
  @override
  get parts => fixedChild(0);
  @override
  get body => fixedChild(1);
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
  bool _has(int flag) => word(3) & flag != 0;
  int get _nameIndex => word(4) + (_has(_formalType) ? 1 : 0);

  @override
  get isCovariant => _has(_formalCovariant);
  @override
  get type => _has(_formalType) ? fixedChild(word(4)) : null;
  @override
  get name => fixedChild(_nameIndex);
  @override
  get functionSuffix => _has(_formalSuffix) ? fixedChild(_nameIndex + 1) : null;
  @override
  get defaultClause => _has(_formalDefault) ? trailingChild(1) : null;
  @override
  get metadata => firstChildren(word(4));
}

final class _RowFormalParameterList(super._owner, super._row)
    extends _Row
    implements FormalParameterList {
  @override
  get parameters => allChildren();
}

final class _RowFunctionExpression(super._owner, super._row)
    extends _Row
    implements FunctionExpression {
  @override
  get typeParameters => optionalChild(0, 3);
  @override
  get parameters => trailingChild(2);
  @override
  get body => trailingChild(1);
}

final class _RowFunctionParameterSuffix(super._owner, super._row)
    extends _Row
    implements FunctionParameterSuffix {
  @override
  get typeParameters => optionalChild(0, 2);
  @override
  get parameters => trailingChild(1);
  @override
  get questionOffset => questionAt(0);
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
  get metadata => firstChildren(word(4));
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
  get questionOffset => questionAt(3);
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
  get metadata => firstChildren(word(4));
}

final class _RowFunctionTypeParameterList(super._owner, super._row)
    extends _Row
    implements FunctionTypeParameterList {
  @override
  get parameters => allChildren();
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
  get metadata => firstChildren(word(5));
}

final class _RowGuardedPattern(super._owner, super._row)
    extends _Row
    implements GuardedPattern {
  @override
  get pattern => fixedChild(0);
  @override
  get guard => fixedChild(1);
}

final class _RowIdentifier(super._owner, super._row)
    extends _Row
    implements Identifier {}

final class _RowIdentifierExpression(super._owner, super._row)
    extends _Row
    implements IdentifierExpression {
  @override
  get identifier => fixedChild(0);
}

final class _RowIdentifierPattern(super._owner, super._row)
    extends _Row
    implements IdentifierPattern {
  @override
  get name => fixedChild(0);
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
  get configurations => childSlice(word(5) + 1, word(3));
  @override
  get combinators => lastChildren(word(4));
  @override
  get metadata => firstChildren(word(5));
}

final class _RowIndexExpression(super._owner, super._row)
    extends _Row
    implements IndexExpression {
  @override
  get target => fixedChild(0);
  @override
  get index => fixedChild(1);
  @override
  get isNullAware => _owner.indexIsNullAware(_row);
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
  get name => firstChildren(word(4));
}

final class _RowInterpolatedStringExpression(super._owner, super._row)
    extends _Row
    implements InterpolatedStringExpression {
  @override
  get parts => allChildren();
}

final class _RowInvocationExpression(super._owner, super._row)
    extends _Row
    implements InvocationExpression {
  @override
  get callee => fixedChild(0);
  @override
  get typeArguments => optionalChild(1, 3);
  @override
  get arguments => trailingChild(1);
}

final class _RowLabel(super._owner, super._row) extends _Row implements Label {
  @override
  get name => fixedChild(0);
}

final class _RowLabeledStatement(super._owner, super._row)
    extends _Row
    implements LabeledStatement {
  @override
  get statement => node(0);
  @override
  get labels => firstChildren(word(1));
}

final class _RowLibraryDirective(super._owner, super._row)
    extends _Row
    implements LibraryDirective {
  @override
  get name => node(0);
  @override
  get metadata => firstChildren(word(1));
}

final class _RowListPattern(super._owner, super._row)
    extends _Row
    implements ListPattern {
  @override
  get typeArguments => node(0);
  @override
  get elements => lastChildren(word(1));
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
  get metadata => firstChildren(word(5));
}

final class _RowLogicalPattern(super._owner, super._row)
    extends _Row
    implements LogicalPattern {
  @override
  get left => fixedChild(0);
  @override
  LogicalPatternOperator get op => LogicalPatternOperator.values[word(0)];
  @override
  get right => fixedChild(1);
}

final class _RowMapEntryElement(super._owner, super._row)
    extends _Row
    implements MapEntryElement {
  @override
  get key => fixedChild(0);
  @override
  get value => fixedChild(1);
  @override
  get isNullAwareKey => flag(0);
  @override
  get isNullAwareValue => flag(1);
}

final class _RowMapPattern(super._owner, super._row)
    extends _Row
    implements MapPattern {
  @override
  get typeArguments => node(0);
  @override
  get elements => lastChildren(word(1));
}

final class _RowMapPatternEntry(super._owner, super._row)
    extends _Row
    implements MapPatternEntry {
  @override
  get key => fixedChild(0);
  @override
  get value => fixedChild(1);
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
  get metadata => firstChildren(word(7));
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
  get metadata => firstChildren(word(6));
  @override
  get members => lastChildren(word(7));
}

final class _RowModifiedBlockFunctionBody(super._owner, super._row)
    extends _Row
    implements ModifiedBlockFunctionBody {
  @override
  FunctionBodyModifier get modifier => FunctionBodyModifier.values[word(0)];
  @override
  get block => fixedChild(0);
}

final class _RowNamedPatternField(super._owner, super._row)
    extends _Row
    implements NamedPatternField {
  @override
  get name => optionalChild(0, 2);
  @override
  get pattern => trailingChild(1);
}

final class _RowNamedRecordField(super._owner, super._row)
    extends _Row
    implements NamedRecordField {
  @override
  get name => fixedChild(0);
  @override
  get value => fixedChild(1);
}

final class _RowNamedRecordTypeField(super._owner, super._row)
    extends _Row
    implements NamedRecordTypeField {
  @override
  get name => node(0);
  @override
  get type => node(1);
  @override
  get metadata => firstChildren(word(2));
}

final class _RowNamedTypeAnnotation(super._owner, super._row)
    extends _Row
    implements NamedTypeAnnotation {
  @override
  Identifier? get prefix {
    final id = _owner.namedTypePrefix(_row);
    return id == null ? null : _owner.at(id) as Identifier;
  }

  @override
  get name => fixedChild(word(0) & AstArena._typePrefix);
  @override
  get typeArguments => word(0) & AstArena._typeArguments == 0
      ? null
      : trailingChild<TypeArgumentList>(1);
  @override
  get questionOffset => _owner.namedTypeQuestion(_row);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowNamespaceCombinator(super._owner, super._row)
    extends _Row
    implements NamespaceCombinator {
  @override
  NamespaceCombinatorKind get kind => NamespaceCombinatorKind.values[word(0)];
  @override
  get names => allChildren();
}

final class _RowNullAssertPattern(super._owner, super._row)
    extends _Row
    implements NullAssertPattern {
  @override
  get pattern => fixedChild(0);
}

final class _RowNullAssertionExpression(super._owner, super._row)
    extends _Row
    implements NullAssertionExpression {
  @override
  get operand => fixedChild(0);
}

final class _RowNullAwareElement(super._owner, super._row)
    extends _Row
    implements NullAwareElement {
  @override
  get expression => fixedChild(0);
}

final class _RowNullCheckPattern(super._owner, super._row)
    extends _Row
    implements NullCheckPattern {
  @override
  get pattern => fixedChild(0);
}

final class _RowObjectPattern(super._owner, super._row)
    extends _Row
    implements ObjectPattern {
  @override
  get type => node(0);
  @override
  get fields => lastChildren(word(1));
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
  get metadata => firstChildren(word(6));
}

final class _RowParameterDefault(super._owner, super._row)
    extends _Row
    implements ParameterDefault {
  @override
  ParameterDefaultSeparator get separator =>
      ParameterDefaultSeparator.values[word(0)];
  @override
  get value => fixedChild(0);
}

final class _RowParenthesizedExpression(super._owner, super._row)
    extends _Row
    implements ParenthesizedExpression {
  @override
  get expression => fixedChild(0);
}

final class _RowParenthesizedPattern(super._owner, super._row)
    extends _Row
    implements ParenthesizedPattern {
  @override
  get pattern => fixedChild(0);
}

final class _RowPartDirective(super._owner, super._row)
    extends _Row
    implements PartDirective {
  @override
  get uri => node(0);
  @override
  get metadata => firstChildren(word(1));
}

final class _RowPartOfDirective(super._owner, super._row)
    extends _Row
    implements PartOfDirective {
  @override
  get target => node(0);
  @override
  get metadata => firstChildren(word(1));
}

final class _RowPatternAssignmentExpression(super._owner, super._row)
    extends _Row
    implements PatternAssignmentExpression {
  @override
  get pattern => fixedChild(0);
  @override
  get value => fixedChild(1);
}

final class _RowPatternForInBinding(super._owner, super._row)
    extends _Row
    implements PatternForInBinding {
  @override
  get isFinal => flag(0);
  @override
  get pattern => node(1);
  @override
  get metadata => firstChildren(word(2));
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
  get metadata => firstChildren(word(3));
}

final class _RowPatternVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements PatternVariableDeclarationStatement {
  @override
  get declaration => fixedChild(0);
}

final class _RowPositionalRecordTypeField(super._owner, super._row)
    extends _Row
    implements PositionalRecordTypeField {
  @override
  get name => node(0);
  @override
  get type => node(1);
  @override
  get metadata => firstChildren(word(2));
}

final class _RowPrimaryConstructorBody(super._owner, super._row)
    extends _Row
    implements PrimaryConstructorBody {
  @override
  get body => node(0);
  @override
  get metadata => firstChildren(word(1));
  @override
  get initializers => lastChildren(word(2), 1);
}

final class _RowPropertyAccessExpression(super._owner, super._row)
    extends _Row
    implements PropertyAccessExpression {
  @override
  get target => fixedChild(0);
  @override
  get property => fixedChild(1);
  @override
  get isNullAware => flag(0);
}

final class _RowRecordExpression(super._owner, super._row)
    extends _Row
    implements RecordExpression {
  @override
  get hasConstKeyword => flag(0);
  @override
  get fields => allChildren();
}

final class _RowRecordPattern(super._owner, super._row)
    extends _Row
    implements RecordPattern {
  @override
  get fields => allChildren();
}

final class _RowRecordTypeAnnotation(super._owner, super._row)
    extends _Row
    implements RecordTypeAnnotation {
  @override
  get namedFields => node(0);
  @override
  get positionalFields => firstChildren(word(1));
  @override
  get questionOffset => questionAt(2);
  @override
  bool get isNullable => questionOffset != null;
}

final class _RowRecordTypeNamedFields(super._owner, super._row)
    extends _Row
    implements RecordTypeNamedFields {
  @override
  get fields => allChildren();
}

final class _RowRedirectingConstructorInitializer(super._owner, super._row)
    extends _Row
    implements RedirectingConstructorInitializer {
  @override
  get name => optionalChild(0, 2);
  @override
  get arguments => trailingChild(1);
}

final class _RowRelationalPattern(super._owner, super._row)
    extends _Row
    implements RelationalPattern {
  @override
  RelationalPatternOperator get op => RelationalPatternOperator.values[word(0)];
  @override
  get operand => fixedChild(0);
}

final class _RowRestPatternElement(super._owner, super._row)
    extends _Row
    implements RestPatternElement {
  @override
  get pattern => optionalChild(0, 1);
}

final class _RowRethrowStatement(super._owner, super._row)
    extends _Row
    implements RethrowStatement {}

final class _RowReturnStatement(super._owner, super._row)
    extends _Row
    implements ReturnStatement {
  @override
  get expression => optionalChild(0, 1);
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
  get metadata => firstChildren(word(7));
}

final class _RowSpreadElement(super._owner, super._row)
    extends _Row
    implements SpreadElement {
  @override
  get expression => fixedChild(0);
  @override
  get isNullAware => flag(0);
}

final class _RowStringInterpolation(super._owner, super._row)
    extends _Row
    implements StringInterpolation {
  @override
  get expression => fixedChild(0);
  @override
  get isBraced => flag(0);
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
  get name => optionalChild(0, 2);
  @override
  get arguments => trailingChild(1);
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
  get cases => lastChildren(word(1));
}

final class _RowSwitchExpressionCase(super._owner, super._row)
    extends _Row
    implements SwitchExpressionCase {
  @override
  get pattern => fixedChild(0);
  @override
  get value => fixedChild(1);
}

final class _RowSwitchStatement(super._owner, super._row)
    extends _Row
    implements SwitchStatement {
  @override
  get expression => node(0);
  @override
  get members => lastChildren(word(1));
}

final class _RowSwitchStatementMember(super._owner, super._row)
    extends _Row
    implements SwitchStatementMember {
  @override
  get pattern => node(0);
  @override
  get labels => firstChildren(word(1));
  @override
  get statements => lastChildren(word(2));
}

final class _RowThisExpression(super._owner, super._row)
    extends _Row
    implements ThisExpression {}

final class _RowThrowExpression(super._owner, super._row)
    extends _Row
    implements ThrowExpression {
  @override
  get expression => fixedChild(0);
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
  get metadata => firstChildren(word(6));
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
  get metadata => firstChildren(word(4));
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
  get metadata => firstChildren(word(5));
}

final class _RowTopLevelVariableDeclaration(super._owner, super._row)
    extends _Row
    implements TopLevelVariableDeclaration {
  @override
  get isExternal => flag(0);
  @override
  get variables => fixedChild(0);
}

final class _RowTryStatement(super._owner, super._row)
    extends _Row
    implements TryStatement {
  @override
  get body => node(0);
  @override
  get finallyBlock => node(1);
  @override
  get catchClauses => childSlice(1, word(2));
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
  get metadata => firstChildren(word(3));
}

final class _RowTypeArgumentList(super._owner, super._row)
    extends _Row
    implements TypeArgumentList {
  @override
  get arguments => allChildren();
}

final class _RowTypeInstantiationExpression(super._owner, super._row)
    extends _Row
    implements TypeInstantiationExpression {
  @override
  get expression => fixedChild(0);
  @override
  get typeArguments => fixedChild(1);
}

final class _RowTypeListClause(super._owner, super._row)
    extends _Row
    implements TypeListClause {
  @override
  TypeListClauseKind get kind => TypeListClauseKind.values[word(0)];
  @override
  get types => allChildren();
}

final class _RowTypeParameter(super._owner, super._row)
    extends _Row
    implements TypeParameter {
  @override
  get name => node(0);
  @override
  get bound => node(1);
  @override
  get metadata => firstChildren(word(2));
}

final class _RowTypeParameterList(super._owner, super._row)
    extends _Row
    implements TypeParameterList {
  @override
  get parameters => allChildren();
}

final class _RowTypeTestExpression(super._owner, super._row)
    extends _Row
    implements TypeTestExpression {
  @override
  get expression => fixedChild(0);
  @override
  get type => fixedChild(1);
  @override
  get isNegated => flag(0);
}

final class _RowUnaryExpression(super._owner, super._row)
    extends _Row
    implements UnaryExpression {
  @override
  UnaryOperator get op => UnaryOperator.values[word(0)];
  @override
  get operand => fixedChild(0);
}

final class _RowUpdateExpression(super._owner, super._row)
    extends _Row
    implements UpdateExpression {
  @override
  get operand => fixedChild(0);
  @override
  UpdateOperator get op => UpdateOperator.values[word(0)];
  @override
  get isPrefix => _owner.updateIsPrefix(_row);
}

final class _RowVariableDeclaration(super._owner, super._row)
    extends _Row
    implements VariableDeclaration {
  @override
  get name => fixedChild(0);
  @override
  get initializer => optionalChild(1, 2);
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
  get metadata => firstChildren(word(3));
  @override
  get declarations => lastChildren(word(4));
}

final class _RowVariableDeclarationStatement(super._owner, super._row)
    extends _Row
    implements VariableDeclarationStatement {
  @override
  get variables => fixedChild(0);
}

final class _RowVariablePattern(super._owner, super._row)
    extends _Row
    implements VariablePattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[word(0)];
  @override
  get type => optionalChild(0, 2);
  @override
  get name => trailingChild(1);
}

final class _RowWhileStatement(super._owner, super._row)
    extends _Row
    implements WhileStatement {
  @override
  get condition => fixedChild(0);
  @override
  get body => fixedChild(1);
}

final class _RowWildcardPattern(super._owner, super._row)
    extends _Row
    implements WildcardPattern {
  @override
  PatternVariableKeyword get keyword => PatternVariableKeyword.values[word(0)];
  @override
  get type => optionalChild(0, 1);
}

final class _RowYieldStatement(super._owner, super._row)
    extends _Row
    implements YieldStatement {
  @override
  get isStar => flag(0);
  @override
  get expression => fixedChild(0);
}
