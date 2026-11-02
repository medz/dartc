part of 'nodes.dart';

/// An immutable syntax tree for one source snapshot.
///
/// A node index belongs to this tree. [walk] visits its reachable nodes in
/// depth-first source order. [view] exposes fields specific to a syntax kind.
///
/// {@example /example/indexed_syntax.dart}
final class SyntaxTree._(final AstArena _data, final int root) {
  /// The snapshot that owns every source range.
  SourceFile get source => _data.source;

  /// The grammar kind of [node].
  SyntaxKind kind(int node) => _data.kindAt(_check(node));

  /// The index of a typed node obtained from this snapshot.
  int indexOf(AstNode node) {
    if (node is _Row && identical(node._owner, _data)) return node._row;
    throw ArgumentError.value(node, 'node', 'belongs to a different tree');
  }

  /// A typed view of [node]. Equal views identify the same row.
  AstNode view(int node) => _data.at(_check(node));

  /// The inclusive UTF-16 start of [node].
  int start(int node) => _data.starts[_check(node)];

  /// The exclusive UTF-16 end of [node].
  int end(int node) => _data.ends[_check(node)];

  /// The number of direct children of [node].
  int childCount(int node) {
    final i = _check(node);
    return _data.edgeOffsets[i + 1] - _data.edgeOffsets[i];
  }

  /// The child index at source-order position [index] in [node].
  int childAt(int node, int index) {
    RangeError.checkValidIndex(index, this, 'index', childCount(node));
    return _data.childIndex(node, index);
  }

  /// Starts a depth-first traversal of [node] and its descendants in source order.
  ///
  /// The traversal starts at [root] when [node] is omitted.
  SyntaxCursor cursor([int? node]) =>
      SyntaxCursor._(_data, node == null ? root : _check(node));

  /// Iterates over [node] and its descendants, starting at [root] by default.
  Iterable<int> walk([int? node]) =>
      _IndexWalk(_data, node == null ? root : _check(node));
  int _check(int id) {
    RangeError.checkValidIndex(id, this, 'node', _data.count);
    return id;
  }
}

final class _IndexWalk(final AstArena data, final int root)
    extends Iterable<int> {
  @override
  Iterator<int> get iterator => SyntaxCursor._(data, root);
}

/// Reads the current syntax row during a source-order traversal.
///
/// Call [moveNext] to select a row before reading its kind, range or view.
final class SyntaxCursor._(final AstArena _data, this._next)
    implements Iterator<int> {
  final List<int> _ranges = [];
  int _edge = 0, _end = 0;
  int _id = -1, _next;

  @override
  int get current =>
      _id >= 0 ? _id : throw StateError('No current syntax node');
  SyntaxKind get kind => _data.kindAt(_id);
  int get start => _data.starts[_id];
  int get end => _data.ends[_id];
  int get childCount => _data.edgeOffsets[_id + 1] - _data.edgeOffsets[_id];
  AstNode get view => _data.at(_id);

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
      id = _data.edges.cells[_edge++];
    }
    _id = id;
    final first = _data.edgeOffsets[id], limit = _data.edgeOffsets[id + 1];
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
  adjacentStringsExpression,
  annotation,
  argument,
  argumentList,
  assertInitializer,
  assertStatement,
  assignmentExpression,
  awaitExpression,
  binaryExpression,
  blockStatement,
  breakStatement,
  cascadeExpression,
  cascadeIndexExpression,
  cascadePropertyExpression,
  castExpression,
  castPattern,
  catchClause,
  classDeclaration,
  classTypeAliasDeclaration,
  collectionExpression,
  compilationUnit,
  conditionalExpression,
  conditionalUri,
  constDotShorthandExpression,
  constantPattern,
  constructorDeclaration,
  continueStatement,
  declaredIdentifier,
  doStatement,
  dotShorthandExpression,
  dotShorthandReferenceExpression,
  dottedName,
  emptyFunctionBody,
  emptyStatement,
  enumConstantDeclaration,
  enumDeclaration,
  exportDirective,
  expressionFunctionBody,
  expressionStatement,
  extendsClause,
  extensionDeclaration,
  extensionTypeDeclaration,
  factoryRedirectBody,
  fieldDeclaration,
  fieldInitializer,
  forElement,
  forInParts,
  forParts,
  forStatement,
  formalParameter,
  formalParameterList,
  functionExpression,
  functionParameterSuffix,
  functionTypeAliasDeclaration,
  functionTypeAnnotation,
  functionTypeParameter,
  functionTypeParameterList,
  getterDeclaration,
  guardedPattern,
  identifier,
  identifierExpression,
  identifierPattern,
  ifElement,
  ifStatement,
  importDirective,
  indexExpression,
  instanceCreationExpression,
  interpolatedStringExpression,
  invocationExpression,
  label,
  labeledStatement,
  libraryDirective,
  listPattern,
  literalExpression,
  localFunctionDeclaration,
  logicalPattern,
  mapEntryElement,
  mapPattern,
  mapPatternEntry,
  methodDeclaration,
  missingClassMember,
  missingExpression,
  missingFunctionBody,
  missingPattern,
  missingStatement,
  missingStringExpression,
  missingTopLevelDeclaration,
  missingTypeAnnotation,
  mixinDeclaration,
  modifiedBlockFunctionBody,
  namedPatternField,
  namedRecordField,
  namedRecordTypeField,
  namedTypeAnnotation,
  namespaceCombinator,
  nullAssertPattern,
  nullAssertionExpression,
  nullAwareElement,
  nullCheckPattern,
  objectPattern,
  operatorDeclaration,
  parameterDefault,
  parenthesizedExpression,
  parenthesizedPattern,
  partDirective,
  partOfDirective,
  patternAssignmentExpression,
  patternForInBinding,
  patternVariableDeclaration,
  patternVariableDeclarationStatement,
  positionalRecordTypeField,
  primaryConstructorBody,
  propertyAccessExpression,
  recordExpression,
  recordPattern,
  recordTypeAnnotation,
  recordTypeNamedFields,
  redirectingConstructorInitializer,
  relationalPattern,
  restPatternElement,
  rethrowStatement,
  returnStatement,
  scriptTag,
  setterDeclaration,
  spreadElement,
  stringInterpolation,
  stringLiteralExpression,
  stringText,
  superConstructorInitializer,
  superExpression,
  switchExpression,
  switchExpressionCase,
  switchStatement,
  switchStatementMember,
  thisExpression,
  throwExpression,
  topLevelFunctionDeclaration,
  topLevelGetterDeclaration,
  topLevelSetterDeclaration,
  topLevelVariableDeclaration,
  tryStatement,
  typeAliasDeclaration,
  typeArgumentList,
  typeInstantiationExpression,
  typeListClause,
  typeParameter,
  typeParameterList,
  typeTestExpression,
  unaryExpression,
  updateExpression,
  variableDeclaration,
  variableDeclarationList,
  variableDeclarationStatement,
  variablePattern,
  whileStatement,
  wildcardPattern,
  yieldStatement,
}
