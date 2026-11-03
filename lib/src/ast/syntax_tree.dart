part of 'nodes.dart';

mixin _SyntaxAccess {
  SyntaxTreeBuilder get _data;

  /// The grammar kind of [node].
  SyntaxKind kind(int node) => _data._kindAt(_check(node));

  /// The index of a typed node obtained from this snapshot.
  int indexOf(AstNode node) {
    if (node is _Row && identical(node._owner, _data)) return node._row;
    throw ArgumentError.value(node, 'node', 'belongs to a different tree');
  }

  /// A typed view of [node]. Equal views identify the same row.
  ///
  /// Throws [TypeError] when the node does not implement the requested type.
  T view<T extends AstNode>(int node) => _data._at(_check(node)) as T;

  /// The inclusive UTF-16 start of [node].
  int start(int node) => _data._start(_check(node));

  /// The exclusive UTF-16 end of [node].
  int end(int node) => _data._end(_check(node));

  /// The number of direct children of [node].
  int childCount(int node) {
    return _data._childCount(_check(node));
  }

  /// The child index at source-order position [index] in [node].
  int childAt(int node, int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount(node));
    return _data._childIndex(node, index);
  }

  int _check(int id) {
    if (id < 0 || id >= _data._count) {
      throw RangeError.index(id, this, 'node', null, _data._count);
    }
    return id;
  }
}

/// An immutable syntax tree for one source snapshot.
///
/// A node index belongs to this tree. [walk] visits its reachable nodes in
/// depth-first source order. [view] exposes fields specific to a syntax kind.
///
/// {@example /example/indexed_syntax.dart}
final class SyntaxTree._(
  @override final SyntaxTreeBuilder _data,
  final int root,
) with _SyntaxAccess {
  /// The snapshot that owns every source range.
  SourceFile get source => _data.source;

  /// Copies rows through [through] into [next], preserving their local indices.
  ///
  /// Returns null if a reused range no longer fits or a whole-file node would
  /// acquire a different extent. The caller identifies
  /// unchanged syntax in the two snapshots.
  SyntaxTreeBuilder? copyPrefix(
    SourceFile next, {
    required int through,
    int expectedTokens = 0,
  }) {
    RangeError.checkNotNegative(expectedTokens, 'expectedTokens');
    expectedTokens = expectedTokens.clamp(0, next.length + 1);
    final old = _data;
    final rows = _check(through) + 1;
    if (next.length != source.length) {
      for (var i = 0; i < rows; i++) {
        if (old._end(i) > next.length ||
            old._tags[i] == SyntaxKind.compilationUnit.index) {
          return null;
        }
      }
    }
    final edges = old._edgeOffsets[rows];
    final fields = rows == old._count ? old._fields.used : old._offsets[rows];
    return SyntaxTreeBuilder._copy(
      old,
      next,
      rows,
      edges,
      fields,
      rows + expectedTokens + expectedTokens ~/ 6,
      fields + expectedTokens,
    );
  }

  /// Starts a replacement of [node] around the first changed offset [changeStart].
  ///
  /// Local indices preceding the subtree remain available. Returns null when
  /// the prefix cannot be reused. Use [SyntaxTreeBuilder.finishReplacement] to publish the result.
  SyntaxTreeBuilder? editSubtree(
    int node,
    SourceFile next, {
    required int changeStart,
  }) {
    final old = _data;
    _check(node);
    if (node == root ||
        changeStart < start(node) ||
        changeStart > end(node) ||
        changeStart > next.length) {
      return null;
    }
    var first = node;
    while (old._childCount(first) != 0) {
      first = old._childIndex(first, 0);
    }
    if (next.length != source.length) {
      for (var i = 0; i < first; i++) {
        if (old._end(i) > changeStart ||
            old._tags[i] == SyntaxKind.compilationUnit.index) {
          return null;
        }
      }
    }
    final result = SyntaxTreeBuilder._copy(
      old,
      next,
      old._count,
      old._edges.used,
      old._fields.used,
      old._count,
      old._fields.used,
    );
    result._count = first;
    result._edges.used = old._edgeOffsets[first];
    result._fields.used = old._offsets[first];
    result._replacement = (this, node, first, changeStart);
    return result;
  }

  /// Starts a depth-first traversal of [node] and its descendants in source order.
  ///
  /// The traversal starts at [root] when [node] is omitted.
  SyntaxCursor cursor([int? node]) =>
      SyntaxCursor._(_data, node == null ? root : _check(node));

  /// Iterates over [node] and its descendants, starting at [root] by default.
  Iterable<int> walk([int? node]) =>
      _IndexWalk(_data, node == null ? root : _check(node));
}

final class _IndexWalk(final SyntaxTreeBuilder _data, final int _root)
    extends Iterable<int> {
  @override
  Iterator<int> get iterator => SyntaxCursor._(_data, _root);
}

/// Reads the current syntax row during a source-order traversal.
///
/// Call [moveNext] to select a row before reading its kind, range or view.
final class SyntaxCursor._(final SyntaxTreeBuilder _data, this._next)
    implements Iterator<int> {
  final List<int> _ranges = [];
  int _edge = 0, _end = 0;
  int _id = -1, _next;

  @override
  int get current =>
      _id >= 0 ? _id : throw StateError('No current syntax node');
  SyntaxKind get kind => _data._kindAt(_id);
  int get start => _data._start(_id);
  int get end => _data._end(_id);
  int get childCount => _data._childCount(_id);
  AstNode get view => _data._at(_id);

  @override
  bool moveNext() {
    var id = _next;
    if (id >= 0) {
      _next = -1;
    } else {
      if (_edge == _end) {
        if (_ranges.isEmpty) {
          _id = -1;
          return false;
        }
        _end = _ranges.removeLast();
        _edge = _ranges.removeLast();
      }
      id = _data._edges.cells[_edge++];
    }
    _id = id;
    final first = _data._edgeOffsets[id], limit = _data._edgeOffsets[id + 1];
    if (first < limit) {
      if (_edge < _end) {
        _ranges.add(_edge);
        _ranges.add(_end);
      }
      _edge = first;
      _end = limit;
    }
    return true;
  }
}

/// The kind of a written or recovered syntax node.
enum SyntaxKind {
  adjacentStringsExpression(_stringExpressionRoles),
  annotation,
  argument,
  argumentList,
  assertInitializer(_isConstructorInitializer),
  assertStatement(_isStatement),
  assignmentExpression(_expressionRoles),
  awaitExpression(_expressionRoles),
  binaryExpression(_expressionRoles),
  blockStatement(_isConstructorBody | _isFunctionBody | _isStatement),
  breakStatement(_isStatement),
  cascadeExpression(_expressionRoles),
  cascadeIndexExpression(_expressionRoles),
  cascadePropertyExpression(_expressionRoles),
  castExpression(_expressionRoles),
  castPattern(_dartPatternRoles),
  catchClause,
  classDeclaration(_isCompilationUnitMember),
  classTypeAliasDeclaration(_isCompilationUnitMember),
  collectionExpression(_expressionRoles),
  compilationUnit,
  conditionalExpression(_expressionRoles),
  conditionalUri,
  constDotShorthandExpression(_expressionRoles),
  constantPattern(_dartPatternRoles),
  constructorDeclaration(_isClassMember),
  continueStatement(_isStatement),
  declaredIdentifier(_isForInTarget),
  doStatement(_isStatement),
  dotShorthandExpression(_expressionRoles),
  dotShorthandReferenceExpression(_expressionRoles),
  dottedName(_isPartOfTarget),
  emptyFunctionBody(_functionBodyRoles),
  emptyStatement(_isStatement),
  enumConstantDeclaration,
  enumDeclaration(_isCompilationUnitMember),
  exportDirective(_isCompilationUnitMember),
  expressionFunctionBody(_functionBodyRoles),
  expressionStatement(_isStatement),
  extendsClause,
  extensionDeclaration(_isCompilationUnitMember),
  extensionTypeDeclaration(_isCompilationUnitMember),
  factoryRedirectBody(_isConstructorBody),
  fieldDeclaration(_isClassMember),
  fieldInitializer(_isConstructorInitializer),
  forElement(_isCollectionElement),
  forInParts(_isForLoopParts),
  forParts(_isForLoopParts),
  forStatement(_isStatement),
  formalParameter,
  formalParameterList,
  functionExpression(_expressionRoles),
  functionParameterSuffix,
  functionTypeAliasDeclaration(_isCompilationUnitMember),
  functionTypeAnnotation(_isTypeAnnotation),
  functionTypeParameter,
  functionTypeParameterList,
  getterDeclaration(_isClassMember),
  guardedPattern(_isCasePattern),
  identifier(_isForInTarget),
  identifierExpression(_expressionRoles),
  identifierPattern(_dartPatternRoles),
  ifElement(_isCollectionElement),
  ifStatement(_isStatement),
  importDirective(_isCompilationUnitMember),
  indexExpression(_expressionRoles),
  instanceCreationExpression(_expressionRoles),
  interpolatedStringExpression(_stringExpressionRoles),
  invocationExpression(_expressionRoles),
  label,
  labeledStatement(_isStatement),
  libraryDirective(_isCompilationUnitMember),
  listPattern(_dartPatternRoles),
  literalExpression(_expressionRoles),
  localFunctionDeclaration(_isStatement),
  logicalPattern(_dartPatternRoles),
  mapEntryElement(_isCollectionElement),
  mapPattern(_dartPatternRoles),
  mapPatternEntry(_isMapPatternElement),
  methodDeclaration(_isClassMember),
  missingClassMember(_isClassMember),
  missingExpression(_expressionRoles),
  missingFunctionBody(_functionBodyRoles),
  missingPattern(_dartPatternRoles),
  missingStatement(_isStatement),
  missingStringExpression(_stringExpressionRoles),
  missingTopLevelDeclaration(_isCompilationUnitMember),
  missingTypeAnnotation(_isTypeAnnotation),
  mixinDeclaration(_isCompilationUnitMember),
  modifiedBlockFunctionBody(_functionBodyRoles),
  namedPatternField(_isPatternField),
  namedRecordField(_isRecordField),
  namedRecordTypeField,
  namedTypeAnnotation(_isTypeAnnotation),
  namespaceCombinator,
  nullAssertPattern(_dartPatternRoles),
  nullAssertionExpression(_expressionRoles),
  nullAwareElement(_isCollectionElement),
  nullCheckPattern(_dartPatternRoles),
  objectPattern(_dartPatternRoles),
  operatorDeclaration(_isClassMember),
  parameterDefault,
  parenthesizedExpression(_expressionRoles),
  parenthesizedPattern(_dartPatternRoles),
  partDirective(_isCompilationUnitMember),
  partOfDirective(_isCompilationUnitMember),
  patternAssignmentExpression(_expressionRoles),
  patternForInBinding(_isForInTarget),
  patternVariableDeclaration(_isForInitializer),
  patternVariableDeclarationStatement(_isStatement),
  positionalRecordTypeField,
  primaryConstructorBody(_isClassMember),
  propertyAccessExpression(_expressionRoles),
  recordExpression(_expressionRoles),
  recordPattern(_dartPatternRoles),
  recordTypeAnnotation(_isTypeAnnotation),
  recordTypeNamedFields,
  redirectingConstructorInitializer(_isConstructorInitializer),
  relationalPattern(_dartPatternRoles),
  restPatternElement(_isListPatternElement | _isMapPatternElement),
  rethrowStatement(_isStatement),
  returnStatement(_isStatement),
  scriptTag,
  setterDeclaration(_isClassMember),
  spreadElement(_isCollectionElement),
  stringInterpolation(_isStringPart),
  stringLiteralExpression(_stringExpressionRoles),
  stringText(_isStringPart),
  superConstructorInitializer(_isConstructorInitializer),
  superExpression(_expressionRoles),
  switchExpression(_expressionRoles),
  switchExpressionCase,
  switchStatement(_isStatement),
  switchStatementMember,
  thisExpression(_expressionRoles),
  throwExpression(_expressionRoles),
  topLevelFunctionDeclaration(_isCompilationUnitMember),
  topLevelGetterDeclaration(_isCompilationUnitMember),
  topLevelSetterDeclaration(_isCompilationUnitMember),
  topLevelVariableDeclaration(_isCompilationUnitMember),
  tryStatement(_isStatement),
  typeAliasDeclaration(_isCompilationUnitMember),
  typeArgumentList,
  typeInstantiationExpression(_expressionRoles),
  typeListClause,
  typeParameter,
  typeParameterList,
  typeTestExpression(_expressionRoles),
  unaryExpression(_expressionRoles),
  updateExpression(_expressionRoles),
  variableDeclaration,
  variableDeclarationList(_isForInitializer),
  variableDeclarationStatement(_isStatement),
  variablePattern(_dartPatternRoles),
  whileStatement(_isStatement),
  wildcardPattern(_dartPatternRoles),
  yieldStatement(_isStatement);

  const SyntaxKind([this._roles = 0]);
  final int _roles;

  /// Whether this kind is an expression.
  bool get isExpression => _roles & _isExpression != 0;

  /// Whether this kind is a pattern.
  bool get isPattern => _roles & _isDartPattern != 0;

  /// Whether this kind is a type annotation.
  bool get isTypeAnnotation => _roles & _isTypeAnnotation != 0;
}

const _isCasePattern = 1 << 0;
const _isClassMember = 1 << 1;
const _isCollectionElement = 1 << 2;
const _isCompilationUnitMember = 1 << 3;
const _isConstructorBody = 1 << 4;
const _isConstructorInitializer = 1 << 5;
const _isDartPattern = 1 << 6;
const _isExpression = 1 << 7;
const _isForInTarget = 1 << 8;
const _isForInitializer = 1 << 9;
const _isForLoopParts = 1 << 10;
const _isFunctionBody = 1 << 11;
const _isListPatternElement = 1 << 12;
const _isMapPatternElement = 1 << 13;
const _isPartOfTarget = 1 << 14;
const _isPatternField = 1 << 15;
const _isRecordField = 1 << 16;
const _isStatement = 1 << 17;
const _isStringExpression = 1 << 18;
const _isStringPart = 1 << 19;
const _isTypeAnnotation = 1 << 20;

const _stringExpressionRoles =
    _isCollectionElement |
    _isExpression |
    _isForInitializer |
    _isPartOfTarget |
    _isRecordField |
    _isStringExpression;
const _expressionRoles =
    _isCollectionElement | _isExpression | _isForInitializer | _isRecordField;
const _dartPatternRoles =
    _isCasePattern | _isDartPattern | _isListPatternElement | _isPatternField;
const _functionBodyRoles = _isConstructorBody | _isFunctionBody;
