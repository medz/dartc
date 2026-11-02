part of 'nodes.dart';

// shortcut: rows use 32-bit indices, widen the columns for larger inputs.
const _nil = 0xffffffff;
const _formalType = 1,
    _formalSuffix = 2,
    _formalDefault = 4,
    _formalCovariant = 8;

final class _Words(int cap) {
  Uint32List cells = Uint32List(cap > _nil ? _nil : cap);
  int used = 0;
  int reserve(int n) {
    final start = used;
    final end = start + n;
    if (end > cells.length) _grow(end, used);
    used = end;
    return start;
  }

  void _grow(int end, int keep) {
    if (end > _nil) throw RangeError('Syntax payload exceeds 32-bit indices');
    final size = (cells.length * 2 + 16).clamp(end, _nil);
    cells = Uint32List(size)..setRange(0, keep, cells);
  }

  void add(int value) {
    final p = reserve(1);
    cells[p] = value;
  }
}

// Edges become visible together after every child has passed its range check.
final class _Children(final AstArena arena, final int start, final int end) {
  int _next = arena.edges.used;
  int _previous = start;
  this {
    arena._checkRange(start, end);
  }
  void add(int? child) {
    if (child == null) return;
    _previous = arena._checkEdge(child, _previous, end);
    final edges = arena.edges;
    if (_next == edges.cells.length) edges._grow(_next + 1, _next);
    edges.cells[_next++] = child;
  }

  void addAll(List<int> children) {
    for (var i = 0; i < children.length; i++) {
      add(children[i]);
    }
  }

  int finish(SyntaxKind kind) {
    arena.edges.used = _next;
    return arena._finishRow(kind, start, end);
  }
}

final class AstArena._(final SourceFile source, int capacity, int tokenCount) {
  // A name can produce both an identifier row and an expression or type row.
  factory AstArena(SourceFile source, int tokenCount) =>
      AstArena._(source, tokenCount + (tokenCount >> 2), tokenCount);

  SyntaxTree finish(int root) => SyntaxTree._(this, rawRef(root));

  int count = 0;
  Uint8List tags = Uint8List(capacity);
  Uint32List starts = Uint32List(capacity),
      ends = Uint32List(capacity),
      edgeOffsets = Uint32List(capacity + 1),
      offsets = Uint32List(capacity);
  final edges = _Words(capacity), fields = _Words(tokenCount);
  void grow() {
    final n = count * 2 + 16;
    tags = Uint8List(n)..setRange(0, count, tags);
    starts = Uint32List(n)..setRange(0, count, starts);
    ends = Uint32List(n)..setRange(0, count, ends);
    offsets = Uint32List(n)..setRange(0, count, offsets);
    edgeOffsets = Uint32List(n + 1)..setRange(0, count + 1, edgeOffsets);
  }

  void _checkRange(int start, int end) {
    if (start < 0 || start > end || end > source.length) {
      RangeError.checkValidRange(start, end, source.length);
    }
    if (end >= _nil || count == _nil) {
      throw RangeError('Syntax range or node index exceeds 32 bits');
    }
  }

  int _finishRow(SyntaxKind kind, int start, int end) {
    if (count == tags.length) grow();
    final row = count++;
    tags[row] = kind.index;
    starts[row] = start;
    ends[row] = end;
    edgeOffsets[row + 1] = edges.used;
    offsets[row] = fields.used;
    return row;
  }

  int _leaf(SyntaxKind kind, int start, int end) {
    _checkRange(start, end);
    return _finishRow(kind, start, end);
  }

  int _checkEdge(int id, int start, int end) {
    if (id < 0 || id >= count) {
      RangeError.checkValidIndex(id, this, 'child', count);
    }
    final childEnd = ends[id];
    if (starts[id] < start || childEnd > end) {
      throw ArgumentError('Child outside range');
    }
    return childEnd;
  }

  int _appendOne(SyntaxKind kind, int start, int end, int id) {
    _checkRange(start, end);
    _checkEdge(id, start, end);
    edges.add(id);
    return _finishRow(kind, start, end);
  }

  int _appendTwo(SyntaxKind kind, int start, int end, int first, int second) {
    _checkRange(start, end);
    final next = _checkEdge(first, start, end);
    _checkEdge(second, next, end);
    final base = edges.reserve(2);
    edges.cells[base] = first;
    edges.cells[base + 1] = second;
    return _finishRow(kind, start, end);
  }

  int childCount(int row) => edgeOffsets[row + 1] - edgeOffsets[row];
  int childIndex(int row, int index) => edges.cells[edgeOffsets[row] + index];
  int trailingChild(int row, int fromEnd) =>
      edges.cells[edgeOffsets[row + 1] - fromEnd];
  int? optionalChild(int row, int index, int fullCount) =>
      childCount(row) == fullCount ? childIndex(row, index) : null;

  int _appendOptional(
    SyntaxKind kind,
    int start,
    int end,
    int? a, [
    int? b,
    int? c,
  ]) {
    _checkRange(start, end);
    var next = start;
    if (a != null) next = _checkEdge(a, next, end);
    if (b != null) next = _checkEdge(b, next, end);
    if (c != null) _checkEdge(c, next, end);
    final length =
        (a == null ? 0 : 1) + (b == null ? 0 : 1) + (c == null ? 0 : 1);
    var slot = edges.reserve(length);
    if (a != null) edges.cells[slot++] = a;
    if (b != null) edges.cells[slot++] = b;
    if (c != null) edges.cells[slot] = c;
    return _finishRow(kind, start, end);
  }

  Uint32List childrenOf(int row) => Uint32List.sublistView(
    edges.cells,
    edgeOffsets[row],
    edgeOffsets[row + 1],
  );

  int _appendList(SyntaxKind kind, int start, int end, List<int> children) {
    _checkRange(start, end);
    final base = edges.used;
    try {
      edges.reserve(children.length);
      var previous = start;
      for (var i = 0; i < children.length; i++) {
        final id = children[i];
        previous = _checkEdge(id, previous, end);
        edges.cells[base + i] = id;
      }
    } catch (_) {
      edges.used = base;
      rethrow;
    }
    return _finishRow(kind, start, end);
  }

  int putAdjacentStringsExpression({
    required int start,
    required int end,
    required List<int> strings,
  }) {
    return _appendList(.adjacentStringsExpression, start, end, strings);
  }

  int putAnnotation({
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    final children = _Children(this, start, end)
      ..addAll(name)
      ..add(typeArguments)
      ..add(constructorName)
      ..add(arguments);
    final row = children.finish(.annotation);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    fields.cells[fieldOffset + 3] = name.length;
    return row;
  }

  int putArgument({
    required int start,
    required int end,
    int? name,
    required int value,
  }) {
    return _appendOptional(.argument, start, end, name, value);
  }

  int putArgumentList({
    required int start,
    required int end,
    required List<int> arguments,
  }) {
    return _appendList(.argumentList, start, end, arguments);
  }

  int putAssertInitializer({
    required int start,
    required int end,
    required int condition,
    int? message,
  }) {
    return _appendOptional(.assertInitializer, start, end, condition, message);
  }

  int putAssertStatement({
    required int start,
    required int end,
    required int condition,
    int? message,
  }) {
    return _appendOptional(.assertStatement, start, end, condition, message);
  }

  int putAssignmentExpression({
    required int start,
    required int end,
    required int left,
    required AssignmentOperator op,
    required int right,
  }) {
    final row = _appendTwo(.assignmentExpression, start, end, left, right);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = op.index;
    return row;
  }

  int putAwaitExpression({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.awaitExpression, start, end, expression);
  }

  int putBinaryExpression({
    required int start,
    required int end,
    required int left,
    required BinaryOperator op,
    required int right,
  }) {
    final row = _appendTwo(.binaryExpression, start, end, left, right);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = op.index;
    return row;
  }

  int putBlockStatement({
    required int start,
    required int end,
    required List<int> statements,
  }) {
    return _appendList(.blockStatement, start, end, statements);
  }

  int putBreakStatement({required int start, required int end, int? label}) {
    return _appendOptional(.breakStatement, start, end, label);
  }

  int putCascadeExpression({
    required int start,
    required int end,
    required int target,
    bool isNullAware = false,
    required List<int> sections,
  }) {
    final children = _Children(this, start, end)
      ..add(target)
      ..addAll(sections);
    final row = children.finish(.cascadeExpression);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = isNullAware ? 1 : 0;
    fields.cells[fieldOffset + 2] = sections.length;
    return row;
  }

  int putCascadeIndexExpression({
    required int start,
    required int end,
    required int index,
  }) {
    return _appendOne(.cascadeIndexExpression, start, end, index);
  }

  int putCascadePropertyExpression({
    required int start,
    required int end,
    required int property,
  }) {
    return _appendOne(.cascadePropertyExpression, start, end, property);
  }

  int putCastExpression({
    required int start,
    required int end,
    required int expression,
    required int type,
  }) {
    return _appendTwo(.castExpression, start, end, expression, type);
  }

  int putCastPattern({
    required int start,
    required int end,
    required int pattern,
    required int type,
  }) {
    return _appendTwo(.castPattern, start, end, pattern, type);
  }

  int putCatchClause({
    required int start,
    required int end,
    int? exceptionType,
    int? exceptionParameter,
    int? stackTraceParameter,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..add(exceptionType)
      ..add(exceptionParameter)
      ..add(stackTraceParameter)
      ..add(body);
    final row = children.finish(.catchClause);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(exceptionType);
    fields.cells[fieldOffset + 1] = rawRef(exceptionParameter);
    fields.cells[fieldOffset + 2] = rawRef(stackTraceParameter);
    fields.cells[fieldOffset + 3] = rawRef(body);
    return row;
  }

  int putClassDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    List<ClassModifier> modifiers = const [],
    required int name,
    int? typeParameters,
    bool isConst = false,
    int? primaryConstructorName,
    int? primaryParameters,
    int? extendsClause,
    int? withClause,
    int? implementsClause,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(primaryConstructorName)
      ..add(primaryParameters)
      ..add(extendsClause)
      ..add(withClause)
      ..add(implementsClause)
      ..addAll(members);
    final row = children.finish(.classDeclaration);
    final fieldOffset = fields.reserve(12 + modifiers.length);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = isConst ? 1 : 0;
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(extendsClause);
    fields.cells[fieldOffset + 6] = rawRef(withClause);
    fields.cells[fieldOffset + 7] = rawRef(implementsClause);
    fields.cells[fieldOffset + 8] = isSemicolonBody ? 1 : 0;
    fields.cells[fieldOffset + 9] = metadata.length;
    fields.cells[fieldOffset + 10] = modifiers.length;
    fields.cells[fieldOffset + 11] = members.length;
    for (var i = 0; i < modifiers.length; i++) {
      fields.cells[fieldOffset + 12 + i] = modifiers[i].index;
    }
    return row;
  }

  int putClassTypeAliasDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    List<ClassModifier> modifiers = const [],
    required int name,
    int? typeParameters,
    required int superclass,
    required int withClause,
    int? implementsClause,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(superclass)
      ..add(withClause)
      ..add(implementsClause);
    final row = children.finish(.classTypeAliasDeclaration);
    final fieldOffset = fields.reserve(7 + modifiers.length);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(superclass);
    fields.cells[fieldOffset + 3] = rawRef(withClause);
    fields.cells[fieldOffset + 4] = rawRef(implementsClause);
    fields.cells[fieldOffset + 5] = metadata.length;
    fields.cells[fieldOffset + 6] = modifiers.length;
    for (var i = 0; i < modifiers.length; i++) {
      fields.cells[fieldOffset + 7 + i] = modifiers[i].index;
    }
    return row;
  }

  int putCollectionExpression({
    required int start,
    required int end,
    required CollectionLiteralKind kind,
    bool hasConstKeyword = false,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end)
      ..add(typeArguments)
      ..addAll(elements);
    final row = children.finish(.collectionExpression);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = hasConstKeyword ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(typeArguments);
    fields.cells[fieldOffset + 3] = elements.length;
    return row;
  }

  int putCompilationUnit({int? scriptTag, required List<int> members}) {
    final start = 0;
    final end = source.length;
    final children = _Children(this, start, end)
      ..add(scriptTag)
      ..addAll(members);
    final row = children.finish(.compilationUnit);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(scriptTag);
    fields.cells[fieldOffset + 1] = members.length;
    return row;
  }

  int putConditionalExpression({
    required int start,
    required int end,
    required int condition,
    required int thenExpression,
    required int elseExpression,
  }) {
    final children = _Children(this, start, end)
      ..add(condition)
      ..add(thenExpression)
      ..add(elseExpression);
    return children.finish(.conditionalExpression);
  }

  int putConditionalUri({
    required int start,
    required int end,
    required int name,
    int? value,
    required int uri,
  }) {
    return _appendOptional(.conditionalUri, start, end, name, value, uri);
  }

  int putConstDotShorthandExpression({
    required int start,
    required int end,
    required int name,
    int? typeArguments,
    int? arguments,
  }) {
    final children = _Children(this, start, end)
      ..add(name)
      ..add(typeArguments)
      ..add(arguments);
    final row = children.finish(.constDotShorthandExpression);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    return row;
  }

  int putConstantPattern({
    required int start,
    required int end,
    bool hasConstKeyword = false,
    required int expression,
  }) {
    final row = _appendOne(.constantPattern, start, end, expression);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = hasConstKeyword ? 1 : 0;
    return row;
  }

  int putConstructorDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isConst = false,
    ConstructorKeyword keyword = .none,
    List<int> name = const [],
    required int parameters,
    List<int> initializers = const [],
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..addAll(name)
      ..add(parameters)
      ..addAll(initializers)
      ..add(body);
    final row = children.finish(.constructorDeclaration);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = isConst ? 1 : 0;
    fields.cells[fieldOffset + 2] = keyword.index;
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = metadata.length;
    fields.cells[fieldOffset + 6] = name.length;
    fields.cells[fieldOffset + 7] = initializers.length;
    return row;
  }

  int putContinueStatement({required int start, required int end, int? label}) {
    return _appendOptional(.continueStatement, start, end, label);
  }

  int putDeclaredIdentifier({
    required int start,
    required int end,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..add(name);
    final row = children.finish(.declaredIdentifier);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = metadata.length;
    return row;
  }

  int putDoStatement({
    required int start,
    required int end,
    required int body,
    required int condition,
  }) {
    return _appendTwo(.doStatement, start, end, body, condition);
  }

  int putDotShorthandExpression({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.dotShorthandExpression, start, end, expression);
  }

  int putDotShorthandReferenceExpression({
    required int start,
    required int end,
    required int name,
  }) {
    return _appendOne(.dotShorthandReferenceExpression, start, end, name);
  }

  int putDottedName({
    required int start,
    required int end,
    required List<int> components,
  }) {
    return _appendList(.dottedName, start, end, components);
  }

  int putEmptyFunctionBody({required int start, required int end}) {
    return _leaf(.emptyFunctionBody, start, end);
  }

  int putEmptyStatement({required int start, required int end}) {
    return _leaf(.emptyStatement, start, end);
  }

  int putEnumConstantDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeArguments)
      ..add(constructorName)
      ..add(arguments);
    final row = children.finish(.enumConstantDeclaration);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = metadata.length;
    return row;
  }

  int putEnumDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeParameters,
    bool isConst = false,
    int? primaryConstructorName,
    int? primaryParameters,
    int? withClause,
    int? implementsClause,
    bool isSemicolonBody = false,
    bool hasMemberSeparator = false,
    List<int> constants = const [],
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(primaryConstructorName)
      ..add(primaryParameters)
      ..add(withClause)
      ..add(implementsClause)
      ..addAll(constants)
      ..addAll(members);
    final row = children.finish(.enumDeclaration);
    final fieldOffset = fields.reserve(12);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = isConst ? 1 : 0;
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(withClause);
    fields.cells[fieldOffset + 6] = rawRef(implementsClause);
    fields.cells[fieldOffset + 7] = isSemicolonBody ? 1 : 0;
    fields.cells[fieldOffset + 8] = hasMemberSeparator ? 1 : 0;
    fields.cells[fieldOffset + 9] = metadata.length;
    fields.cells[fieldOffset + 10] = constants.length;
    fields.cells[fieldOffset + 11] = members.length;
    return row;
  }

  int putExportDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    List<int> combinators = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(uri)
      ..addAll(configurations)
      ..addAll(combinators);
    final row = children.finish(.exportDirective);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = configurations.length;
    fields.cells[fieldOffset + 2] = combinators.length;
    fields.cells[fieldOffset + 3] = metadata.length;
    return row;
  }

  int putExpressionFunctionBody({
    required int start,
    required int end,
    bool isAsync = false,
    required int expression,
  }) {
    final row = _appendOne(.expressionFunctionBody, start, end, expression);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isAsync ? 1 : 0;
    return row;
  }

  int putExpressionStatement({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.expressionStatement, start, end, expression);
  }

  int putExtendsClause({
    required int start,
    required int end,
    required int superclass,
  }) {
    return _appendOne(.extendsClause, start, end, superclass);
  }

  int putExtensionDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
    int? typeParameters,
    required int onType,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(onType)
      ..addAll(members);
    final row = children.finish(.extensionDeclaration);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(onType);
    fields.cells[fieldOffset + 3] = isSemicolonBody ? 1 : 0;
    fields.cells[fieldOffset + 4] = metadata.length;
    fields.cells[fieldOffset + 5] = members.length;
    return row;
  }

  int putExtensionTypeDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isConst = false,
    required int name,
    int? typeParameters,
    int? primaryConstructorName,
    required int primaryParameters,
    int? implementsClause,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(primaryConstructorName)
      ..add(primaryParameters)
      ..add(implementsClause)
      ..addAll(members);
    final row = children.finish(.extensionTypeDeclaration);
    final fieldOffset = fields.reserve(9);
    fields.cells[fieldOffset + 0] = isConst ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(implementsClause);
    fields.cells[fieldOffset + 6] = isSemicolonBody ? 1 : 0;
    fields.cells[fieldOffset + 7] = metadata.length;
    fields.cells[fieldOffset + 8] = members.length;
    return row;
  }

  int putFactoryRedirectBody({
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
  }) {
    final children = _Children(this, start, end)
      ..addAll(name)
      ..add(typeArguments)
      ..add(constructorName);
    final row = children.finish(.factoryRedirectBody);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = name.length;
    return row;
  }

  int putFieldDeclaration({
    required int start,
    required int end,
    bool isStatic = false,
    bool isAbstract = false,
    bool isExternal = false,
    bool isCovariant = false,
    required int variables,
  }) {
    final row = _appendOne(.fieldDeclaration, start, end, variables);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = isStatic ? 1 : 0;
    fields.cells[fieldOffset + 1] = isAbstract ? 1 : 0;
    fields.cells[fieldOffset + 2] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 3] = isCovariant ? 1 : 0;
    return row;
  }

  int putFieldInitializer({
    required int start,
    required int end,
    bool hasThis = false,
    required int name,
    required int value,
  }) {
    final row = _appendTwo(.fieldInitializer, start, end, name, value);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = hasThis ? 1 : 0;
    return row;
  }

  int putForElement({
    required int start,
    required int end,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    final row = _appendTwo(.forElement, start, end, parts, body);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isAwait ? 1 : 0;
    return row;
  }

  int putForInParts({
    required int start,
    required int end,
    required int target,
    required int iterable,
  }) {
    return _appendTwo(.forInParts, start, end, target, iterable);
  }

  int putForParts({
    required int start,
    required int end,
    int? initializer,
    int? condition,
    List<int> updaters = const [],
  }) {
    final children = _Children(this, start, end)
      ..add(initializer)
      ..add(condition)
      ..addAll(updaters);
    final row = children.finish(.forParts);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(initializer);
    fields.cells[fieldOffset + 1] = rawRef(condition);
    fields.cells[fieldOffset + 2] = updaters.length;
    return row;
  }

  int putForStatement({
    required int start,
    required int end,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    final row = _appendTwo(.forStatement, start, end, parts, body);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isAwait ? 1 : 0;
    return row;
  }

  int putFormalParameter({
    required int start,
    required int end,
    List<int> metadata = const [],
    required FormalParameterKind kind,
    ParameterPrefix prefix = .none,
    VariableKeyword keyword = .none,
    bool isCovariant = false,
    int? type,
    required int name,
    int? functionSuffix,
    int? defaultClause,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..add(name)
      ..add(functionSuffix)
      ..add(defaultClause);
    final row = children.finish(.formalParameter);
    final at = fields.reserve(5);
    fields.cells[at] = kind.index;
    fields.cells[at + 1] = prefix.index;
    fields.cells[at + 2] = keyword.index;
    fields.cells[at + 3] =
        (type == null ? 0 : _formalType) |
        (functionSuffix == null ? 0 : _formalSuffix) |
        (defaultClause == null ? 0 : _formalDefault) |
        (isCovariant ? _formalCovariant : 0);
    fields.cells[at + 4] = metadata.length;
    return row;
  }

  int putFormalParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    return _appendList(.formalParameterList, start, end, parameters);
  }

  int putFunctionExpression({
    required int start,
    required int end,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    return _appendOptional(
      .functionExpression,
      start,
      end,
      typeParameters,
      parameters,
      body,
    );
  }

  int putFunctionParameterSuffix({
    required int start,
    required int end,
    int? typeParameters,
    required int parameters,
    int? questionOffset,
  }) {
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        ends[parameters],
        end - 1,
        "questionOffset",
      );
    }
    final row = _appendOptional(
      .functionParameterSuffix,
      start,
      end,
      typeParameters,
      parameters,
    );
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = questionOffset ?? _nil;
    return row;
  }

  int putFunctionTypeAliasDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(typeParameters)
      ..add(parameters);
    final row = children.finish(.functionTypeAliasDeclaration);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = metadata.length;
    return row;
  }

  int putFunctionTypeAnnotation({
    required int start,
    required int end,
    int? questionOffset,
    int? returnType,
    int? typeParameters,
    required int parameters,
  }) {
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final children = _Children(this, start, end)
      ..add(returnType)
      ..add(typeParameters)
      ..add(parameters);
    final row = children.finish(.functionTypeAnnotation);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(parameters);
    fields.cells[fieldOffset + 3] = questionOffset ?? _nil;
    return row;
  }

  int putFunctionTypeParameter({
    required int start,
    required int end,
    List<int> metadata = const [],
    required FunctionTypeParameterKind kind,
    bool isCovariant = false,
    required int type,
    int? name,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..add(name);
    final row = children.finish(.functionTypeParameter);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = isCovariant ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = metadata.length;
    return row;
  }

  int putFunctionTypeParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    return _appendList(.functionTypeParameterList, start, end, parameters);
  }

  int putGetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(body);
    final row = children.finish(.getterDeclaration);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = metadata.length;
    return row;
  }

  int putGuardedPattern({
    required int start,
    required int end,
    required int pattern,
    required int guard,
  }) {
    return _appendTwo(.guardedPattern, start, end, pattern, guard);
  }

  int putIdentifier({required int start, required int end}) {
    return _leaf(.identifier, start, end);
  }

  int putIdentifierExpression({
    required int start,
    required int end,
    required int identifier,
  }) {
    return _appendOne(.identifierExpression, start, end, identifier);
  }

  int putIdentifierPattern({
    required int start,
    required int end,
    required int name,
  }) {
    return _appendOne(.identifierPattern, start, end, name);
  }

  int putIfElement({
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenElement,
    int? elseElement,
  }) {
    final children = _Children(this, start, end)
      ..add(condition)
      ..add(casePattern)
      ..add(thenElement)
      ..add(elseElement);
    final row = children.finish(.ifElement);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(casePattern);
    fields.cells[fieldOffset + 2] = rawRef(thenElement);
    fields.cells[fieldOffset + 3] = rawRef(elseElement);
    return row;
  }

  int putIfStatement({
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenStatement,
    int? elseStatement,
  }) {
    final children = _Children(this, start, end)
      ..add(condition)
      ..add(casePattern)
      ..add(thenStatement)
      ..add(elseStatement);
    final row = children.finish(.ifStatement);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(casePattern);
    fields.cells[fieldOffset + 2] = rawRef(thenStatement);
    fields.cells[fieldOffset + 3] = rawRef(elseStatement);
    return row;
  }

  int putImportDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    bool isDeferred = false,
    int? prefix,
    List<int> combinators = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(uri)
      ..addAll(configurations)
      ..add(prefix)
      ..addAll(combinators);
    final row = children.finish(.importDirective);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = isDeferred ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(prefix);
    fields.cells[fieldOffset + 3] = configurations.length;
    fields.cells[fieldOffset + 4] = combinators.length;
    fields.cells[fieldOffset + 5] = metadata.length;
    return row;
  }

  int putIndexExpression({
    required int start,
    required int end,
    required int target,
    required int index,
    bool isNullAware = false,
  }) {
    final row = _appendTwo(.indexExpression, start, end, target, index);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isNullAware ? 1 : 0;
    return row;
  }

  int putInstanceCreationExpression({
    required int start,
    required int end,
    InstanceCreationKind kind = .implicit,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    required int arguments,
  }) {
    final children = _Children(this, start, end)
      ..addAll(name)
      ..add(typeArguments)
      ..add(constructorName)
      ..add(arguments);
    final row = children.finish(.instanceCreationExpression);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = name.length;
    return row;
  }

  int putInterpolatedStringExpression({
    required int start,
    required int end,
    required List<int> parts,
  }) {
    return _appendList(.interpolatedStringExpression, start, end, parts);
  }

  int putInvocationExpression({
    required int start,
    required int end,
    required int callee,
    int? typeArguments,
    required int arguments,
  }) {
    return _appendOptional(
      .invocationExpression,
      start,
      end,
      callee,
      typeArguments,
      arguments,
    );
  }

  int putLabel({required int start, required int end, required int name}) {
    return _appendOne(.label, start, end, name);
  }

  int putLabeledStatement({
    required int start,
    required int end,
    required List<int> labels,
    required int statement,
  }) {
    final children = _Children(this, start, end)
      ..addAll(labels)
      ..add(statement);
    final row = children.finish(.labeledStatement);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(statement);
    fields.cells[fieldOffset + 1] = labels.length;
    return row;
  }

  int putLibraryDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name);
    final row = children.finish(.libraryDirective);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = metadata.length;
    return row;
  }

  int putListPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end)
      ..add(typeArguments)
      ..addAll(elements);
    final row = children.finish(.listPattern);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = elements.length;
    return row;
  }

  int putLiteralExpression({
    required int start,
    required int end,
    required LiteralKind kind,
  }) {
    final row = _leaf(.literalExpression, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = kind.index;
    return row;
  }

  int putLocalFunctionDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(typeParameters)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.localFunctionDeclaration);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = metadata.length;
    return row;
  }

  int putLogicalPattern({
    required int start,
    required int end,
    required int left,
    required LogicalPatternOperator op,
    required int right,
  }) {
    final row = _appendTwo(.logicalPattern, start, end, left, right);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = op.index;
    return row;
  }

  int putMapEntryElement({
    required int start,
    required int end,
    required int key,
    required int value,
    bool isNullAwareKey = false,
    bool isNullAwareValue = false,
  }) {
    final row = _appendTwo(.mapEntryElement, start, end, key, value);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = isNullAwareKey ? 1 : 0;
    fields.cells[fieldOffset + 1] = isNullAwareValue ? 1 : 0;
    return row;
  }

  int putMapPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end)
      ..add(typeArguments)
      ..addAll(elements);
    final row = children.finish(.mapPattern);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = elements.length;
    return row;
  }

  int putMapPatternEntry({
    required int start,
    required int end,
    required int key,
    required int value,
  }) {
    return _appendTwo(.mapPatternEntry, start, end, key, value);
  }

  int putMethodDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(typeParameters)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.methodDeclaration);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = rawRef(typeParameters);
    fields.cells[fieldOffset + 5] = rawRef(parameters);
    fields.cells[fieldOffset + 6] = rawRef(body);
    fields.cells[fieldOffset + 7] = metadata.length;
    return row;
  }

  int putMissingClassMember({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingClassMember, start, end);
  }

  int putMissingExpression({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingExpression, start, end);
  }

  int putMissingFunctionBody({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingFunctionBody, start, end);
  }

  int putMissingPattern({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingPattern, start, end);
  }

  int putMissingStatement({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingStatement, start, end);
  }

  int putMissingStringExpression({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingStringExpression, start, end);
  }

  int putMissingTopLevelDeclaration({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingTopLevelDeclaration, start, end);
  }

  int putMissingTypeAnnotation({required int offset}) {
    final start = offset;
    final end = offset;
    const int? questionOffset = null;
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final row = _leaf(.missingTypeAnnotation, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = questionOffset ?? _nil;
    return row;
  }

  int putMixinDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isBase = false,
    required int name,
    int? typeParameters,
    int? onClause,
    int? implementsClause,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(onClause)
      ..add(implementsClause)
      ..addAll(members);
    final row = children.finish(.mixinDeclaration);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isBase ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(onClause);
    fields.cells[fieldOffset + 4] = rawRef(implementsClause);
    fields.cells[fieldOffset + 5] = isSemicolonBody ? 1 : 0;
    fields.cells[fieldOffset + 6] = metadata.length;
    fields.cells[fieldOffset + 7] = members.length;
    return row;
  }

  int putModifiedBlockFunctionBody({
    required int start,
    required int end,
    required FunctionBodyModifier modifier,
    required int block,
  }) {
    final row = _appendOne(.modifiedBlockFunctionBody, start, end, block);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = modifier.index;
    return row;
  }

  int putNamedPatternField({
    required int start,
    required int end,
    int? name,
    required int pattern,
  }) {
    return _appendOptional(.namedPatternField, start, end, name, pattern);
  }

  int putNamedRecordField({
    required int start,
    required int end,
    required int name,
    required int value,
  }) {
    return _appendTwo(.namedRecordField, start, end, name, value);
  }

  int putNamedRecordTypeField({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int type,
    required int name,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..add(name);
    final row = children.finish(.namedRecordTypeField);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = metadata.length;
    return row;
  }

  // The name follows the optional prefix, so bit zero is also its child index.
  static const _typePrefix = 1, _typeArguments = 2, _typeQuestion = 4;

  int? namedTypePrefix(int row) =>
      fields.cells[offsets[row]] & _typePrefix == 0 ? null : childIndex(row, 0);

  int? namedTypeQuestion(int row) {
    final field = offsets[row];
    return fields.cells[field] & _typeQuestion == 0
        ? null
        : fields.cells[field + 1];
  }

  int putNamedTypeAnnotation({
    required int start,
    required int end,
    int? questionOffset,
    int? prefix,
    required int name,
    int? typeArguments,
  }) {
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final row = _appendOptional(
      .namedTypeAnnotation,
      start,
      end,
      prefix,
      name,
      typeArguments,
    );
    final nullable = questionOffset != null;
    final field = fields.reserve(nullable ? 2 : 1);
    fields.cells[field] =
        (prefix == null ? 0 : _typePrefix) |
        (typeArguments == null ? 0 : _typeArguments) |
        (nullable ? _typeQuestion : 0);
    if (nullable) fields.cells[field + 1] = questionOffset;
    return row;
  }

  int putNamespaceCombinator({
    required int start,
    required int end,
    required NamespaceCombinatorKind kind,
    required List<int> names,
  }) {
    final row = _appendList(.namespaceCombinator, start, end, names);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = kind.index;
    return row;
  }

  int putNullAssertPattern({
    required int start,
    required int end,
    required int pattern,
  }) {
    return _appendOne(.nullAssertPattern, start, end, pattern);
  }

  int putNullAssertionExpression({
    required int start,
    required int end,
    required int operand,
  }) {
    return _appendOne(.nullAssertionExpression, start, end, operand);
  }

  int putNullAwareElement({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.nullAwareElement, start, end, expression);
  }

  int putNullCheckPattern({
    required int start,
    required int end,
    required int pattern,
  }) {
    return _appendOne(.nullCheckPattern, start, end, pattern);
  }

  int putObjectPattern({
    required int start,
    required int end,
    required int type,
    required List<int> fields,
  }) {
    final children = _Children(this, start, end)
      ..add(type)
      ..addAll(fields);
    final row = children.finish(.objectPattern);
    final fieldOffset = this.fields.reserve(2);
    this.fields.cells[fieldOffset + 0] = rawRef(type);
    this.fields.cells[fieldOffset + 1] = fields.length;
    return row;
  }

  int putOperatorDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    int? returnType,
    required DeclaredOperator op,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.operatorDeclaration);
    final fieldOffset = fields.reserve(7);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = op.index;
    fields.cells[fieldOffset + 4] = rawRef(parameters);
    fields.cells[fieldOffset + 5] = rawRef(body);
    fields.cells[fieldOffset + 6] = metadata.length;
    return row;
  }

  int putParameterDefault({
    required int start,
    required int end,
    ParameterDefaultSeparator separator = .equals,
    required int value,
  }) {
    final row = _appendOne(.parameterDefault, start, end, value);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = separator.index;
    return row;
  }

  int putParenthesizedExpression({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.parenthesizedExpression, start, end, expression);
  }

  int putParenthesizedPattern({
    required int start,
    required int end,
    required int pattern,
  }) {
    return _appendOne(.parenthesizedPattern, start, end, pattern);
  }

  int putPartDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(uri);
    final row = children.finish(.partDirective);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = metadata.length;
    return row;
  }

  int putPartOfDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int target,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(target);
    final row = children.finish(.partOfDirective);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = metadata.length;
    return row;
  }

  int putPatternAssignmentExpression({
    required int start,
    required int end,
    required int pattern,
    required int value,
  }) {
    return _appendTwo(.patternAssignmentExpression, start, end, pattern, value);
  }

  int putPatternForInBinding({
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(pattern);
    final row = children.finish(.patternForInBinding);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = isFinal ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(pattern);
    fields.cells[fieldOffset + 2] = metadata.length;
    return row;
  }

  int putPatternVariableDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
    required int initializer,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(pattern)
      ..add(initializer);
    final row = children.finish(.patternVariableDeclaration);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = isFinal ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(pattern);
    fields.cells[fieldOffset + 2] = rawRef(initializer);
    fields.cells[fieldOffset + 3] = metadata.length;
    return row;
  }

  int putPatternVariableDeclarationStatement({
    required int start,
    required int end,
    required int declaration,
  }) {
    return _appendOne(
      .patternVariableDeclarationStatement,
      start,
      end,
      declaration,
    );
  }

  int putPositionalRecordTypeField({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int type,
    int? name,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..add(name);
    final row = children.finish(.positionalRecordTypeField);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = metadata.length;
    return row;
  }

  int putPrimaryConstructorBody({
    required int start,
    required int end,
    List<int> metadata = const [],
    List<int> initializers = const [],
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..addAll(initializers)
      ..add(body);
    final row = children.finish(.primaryConstructorBody);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = metadata.length;
    fields.cells[fieldOffset + 2] = initializers.length;
    return row;
  }

  int putPropertyAccessExpression({
    required int start,
    required int end,
    required int target,
    required int property,
    bool isNullAware = false,
  }) {
    final row = _appendTwo(
      .propertyAccessExpression,
      start,
      end,
      target,
      property,
    );
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isNullAware ? 1 : 0;
    return row;
  }

  int putRecordExpression({
    required int start,
    required int end,
    bool hasConstKeyword = false,
    required List<int> fields,
  }) {
    final row = _appendList(.recordExpression, start, end, fields);
    final fieldOffset = this.fields.reserve(1);
    this.fields.cells[fieldOffset + 0] = hasConstKeyword ? 1 : 0;
    return row;
  }

  int putRecordPattern({
    required int start,
    required int end,
    required List<int> fields,
  }) {
    return _appendList(.recordPattern, start, end, fields);
  }

  int putRecordTypeAnnotation({
    required int start,
    required int end,
    int? questionOffset,
    List<int> positionalFields = const [],
    int? namedFields,
  }) {
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final children = _Children(this, start, end)
      ..addAll(positionalFields)
      ..add(namedFields);
    final row = children.finish(.recordTypeAnnotation);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(namedFields);
    fields.cells[fieldOffset + 1] = positionalFields.length;
    fields.cells[fieldOffset + 2] = questionOffset ?? _nil;
    return row;
  }

  int putRecordTypeNamedFields({
    required int start,
    required int end,
    required List<int> fields,
  }) {
    return _appendList(.recordTypeNamedFields, start, end, fields);
  }

  int putRedirectingConstructorInitializer({
    required int start,
    required int end,
    int? name,
    required int arguments,
  }) {
    return _appendOptional(
      .redirectingConstructorInitializer,
      start,
      end,
      name,
      arguments,
    );
  }

  int putRelationalPattern({
    required int start,
    required int end,
    required RelationalPatternOperator op,
    required int operand,
  }) {
    final row = _appendOne(.relationalPattern, start, end, operand);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = op.index;
    return row;
  }

  int putRestPatternElement({
    required int start,
    required int end,
    int? pattern,
  }) {
    return _appendOptional(.restPatternElement, start, end, pattern);
  }

  int putRethrowStatement({required int start, required int end}) {
    return _leaf(.rethrowStatement, start, end);
  }

  int putReturnStatement({
    required int start,
    required int end,
    int? expression,
  }) {
    return _appendOptional(.returnStatement, start, end, expression);
  }

  int putScriptTag({required int start, required int end}) {
    return _leaf(.scriptTag, start, end);
  }

  int putSetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    bool isCovariant = false,
    int? returnType,
    required int name,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.setterDeclaration);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    fields.cells[fieldOffset + 2] = isCovariant ? 1 : 0;
    fields.cells[fieldOffset + 3] = rawRef(returnType);
    fields.cells[fieldOffset + 4] = rawRef(name);
    fields.cells[fieldOffset + 5] = rawRef(parameters);
    fields.cells[fieldOffset + 6] = rawRef(body);
    fields.cells[fieldOffset + 7] = metadata.length;
    return row;
  }

  int putSpreadElement({
    required int start,
    required int end,
    required int expression,
    bool isNullAware = false,
  }) {
    final row = _appendOne(.spreadElement, start, end, expression);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isNullAware ? 1 : 0;
    return row;
  }

  int putStringInterpolation({
    required int start,
    required int end,
    required int expression,
    required bool isBraced,
  }) {
    final row = _appendOne(.stringInterpolation, start, end, expression);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isBraced ? 1 : 0;
    return row;
  }

  int putStringLiteralExpression({required int start, required int end}) {
    return _leaf(.stringLiteralExpression, start, end);
  }

  int putStringText({required int start, required int end}) {
    return _leaf(.stringText, start, end);
  }

  int putSuperConstructorInitializer({
    required int start,
    required int end,
    int? name,
    required int arguments,
  }) {
    return _appendOptional(
      .superConstructorInitializer,
      start,
      end,
      name,
      arguments,
    );
  }

  int putSuperExpression({required int start, required int end}) {
    return _leaf(.superExpression, start, end);
  }

  int putSwitchExpression({
    required int start,
    required int end,
    required int expression,
    required List<int> cases,
  }) {
    final children = _Children(this, start, end)
      ..add(expression)
      ..addAll(cases);
    final row = children.finish(.switchExpression);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = cases.length;
    return row;
  }

  int putSwitchExpressionCase({
    required int start,
    required int end,
    required int pattern,
    required int value,
  }) {
    return _appendTwo(.switchExpressionCase, start, end, pattern, value);
  }

  int putSwitchStatement({
    required int start,
    required int end,
    required int expression,
    required List<int> members,
  }) {
    final children = _Children(this, start, end)
      ..add(expression)
      ..addAll(members);
    final row = children.finish(.switchStatement);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = members.length;
    return row;
  }

  int putSwitchStatementMember({
    required int start,
    required int end,
    List<int> labels = const [],
    int? pattern,
    required List<int> statements,
  }) {
    final children = _Children(this, start, end)
      ..addAll(labels)
      ..add(pattern)
      ..addAll(statements);
    final row = children.finish(.switchStatementMember);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = labels.length;
    fields.cells[fieldOffset + 2] = statements.length;
    return row;
  }

  int putThisExpression({required int start, required int end}) {
    return _leaf(.thisExpression, start, end);
  }

  int putThrowExpression({
    required int start,
    required int end,
    required int expression,
  }) {
    return _appendOne(.throwExpression, start, end, expression);
  }

  int putTopLevelFunctionDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(typeParameters)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.topLevelFunctionDeclaration);
    final fieldOffset = fields.reserve(7);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(typeParameters);
    fields.cells[fieldOffset + 4] = rawRef(parameters);
    fields.cells[fieldOffset + 5] = rawRef(body);
    fields.cells[fieldOffset + 6] = metadata.length;
    return row;
  }

  int putTopLevelGetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(body);
    final row = children.finish(.topLevelGetterDeclaration);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(body);
    fields.cells[fieldOffset + 4] = metadata.length;
    return row;
  }

  int putTopLevelSetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(returnType)
      ..add(name)
      ..add(parameters)
      ..add(body);
    final row = children.finish(.topLevelSetterDeclaration);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = metadata.length;
    return row;
  }

  int putTopLevelVariableDeclaration({
    required int start,
    required int end,
    bool isExternal = false,
    required int variables,
  }) {
    final row = _appendOne(.topLevelVariableDeclaration, start, end, variables);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isExternal ? 1 : 0;
    return row;
  }

  int putTryStatement({
    required int start,
    required int end,
    required int body,
    List<int> catchClauses = const [],
    int? finallyBlock,
  }) {
    final children = _Children(this, start, end)
      ..add(body)
      ..addAll(catchClauses)
      ..add(finallyBlock);
    final row = children.finish(.tryStatement);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRef(finallyBlock);
    fields.cells[fieldOffset + 2] = catchClauses.length;
    return row;
  }

  int putTypeAliasDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeParameters,
    required int type,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(typeParameters)
      ..add(type);
    final row = children.finish(.typeAliasDeclaration);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = metadata.length;
    return row;
  }

  int putTypeArgumentList({
    required int start,
    required int end,
    required List<int> arguments,
  }) {
    return _appendList(.typeArgumentList, start, end, arguments);
  }

  int putTypeInstantiationExpression({
    required int start,
    required int end,
    required int expression,
    required int typeArguments,
  }) {
    return _appendTwo(
      .typeInstantiationExpression,
      start,
      end,
      expression,
      typeArguments,
    );
  }

  int putTypeListClause({
    required int start,
    required int end,
    required TypeListClauseKind kind,
    required List<int> types,
  }) {
    final row = _appendList(.typeListClause, start, end, types);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = kind.index;
    return row;
  }

  int putTypeParameter({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? bound,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(name)
      ..add(bound);
    final row = children.finish(.typeParameter);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(bound);
    fields.cells[fieldOffset + 2] = metadata.length;
    return row;
  }

  int putTypeParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    return _appendList(.typeParameterList, start, end, parameters);
  }

  int putTypeTestExpression({
    required int start,
    required int end,
    required int expression,
    required int type,
    bool isNegated = false,
  }) {
    final row = _appendTwo(.typeTestExpression, start, end, expression, type);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isNegated ? 1 : 0;
    return row;
  }

  int putUnaryExpression({
    required int start,
    required int end,
    required UnaryOperator op,
    required int operand,
  }) {
    final row = _appendOne(.unaryExpression, start, end, operand);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = op.index;
    return row;
  }

  int putUpdateExpression({
    required int start,
    required int end,
    required int operand,
    required UpdateOperator op,
    required bool isPrefix,
  }) {
    final row = _appendOne(.updateExpression, start, end, operand);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = op.index;
    fields.cells[fieldOffset + 1] = isPrefix ? 1 : 0;
    return row;
  }

  int putVariableDeclaration({
    required int start,
    required int end,
    required int name,
    int? initializer,
  }) {
    return _appendOptional(.variableDeclaration, start, end, name, initializer);
  }

  int putVariableDeclarationList({
    required int start,
    required int end,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    bool isLate = false,
    int? type,
    required List<int> declarations,
  }) {
    final children = _Children(this, start, end)
      ..addAll(metadata)
      ..add(type)
      ..addAll(declarations);
    final row = children.finish(.variableDeclarationList);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = isLate ? 1 : 0;
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = metadata.length;
    fields.cells[fieldOffset + 4] = declarations.length;
    return row;
  }

  int putVariableDeclarationStatement({
    required int start,
    required int end,
    required int variables,
  }) {
    return _appendOne(.variableDeclarationStatement, start, end, variables);
  }

  int putVariablePattern({
    required int start,
    required int end,
    PatternVariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    final row = _appendOptional(.variablePattern, start, end, type, name);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = keyword.index;
    return row;
  }

  int putWhileStatement({
    required int start,
    required int end,
    required int condition,
    required int body,
  }) {
    return _appendTwo(.whileStatement, start, end, condition, body);
  }

  int putWildcardPattern({
    required int start,
    required int end,
    PatternVariableKeyword keyword = .none,
    int? type,
  }) {
    final row = _appendOptional(.wildcardPattern, start, end, type);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = keyword.index;
    return row;
  }

  int putYieldStatement({
    required int start,
    required int end,
    bool isStar = false,
    required int expression,
  }) {
    final row = _appendOne(.yieldStatement, start, end, expression);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = isStar ? 1 : 0;
    return row;
  }

  int rawRef(int? id) {
    if (id == null) return _nil;
    if (id < 0 || id >= count) {
      RangeError.checkValidIndex(id, this, 'node', count);
    }
    return id;
  }

  int? nullable(int n) => n == _nil ? null : n;
  bool indexIsNullAware(int row) => fields.cells[offsets[row]] != 0;
  bool updateIsPrefix(int row) => fields.cells[offsets[row] + 1] != 0;
  Iterable<int> walkIds(int root) => _IndexWalk(this, root);

  SyntaxKind kindAt(int id) => SyntaxKind.values[tags[id]];

  AstNode at(int id) => switch (kindAt(id)) {
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
