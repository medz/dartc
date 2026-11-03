part of 'nodes.dart';

// shortcut: rows use 32-bit indices, widen the columns for larger inputs.
const _nil = 0xffffffff;
const _formalType = 1,
    _formalSuffix = 2,
    _formalDefault = 4,
    _formalCovariant = 8;

int _nextCapacity(int size) => size + (size < 2048 ? size : size >> 2) + 16;

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
    final size = _nextCapacity(cells.length).clamp(end, _nil);
    cells = Uint32List(size)..setRange(0, keep, cells);
  }

  void addPair(int first, int second) {
    final p = reserve(2);
    cells[p] = first;
    cells[p + 1] = second;
  }

  void addTriple(int first, int second, int third) {
    final p = reserve(3);
    cells[p] = first;
    cells[p + 1] = second;
    cells[p + 2] = third;
  }

  void add(int value) {
    final p = reserve(1);
    cells[p] = value;
  }
}

// Edges become visible together after every child has passed its range check.
final class _Children(
  final SyntaxTreeBuilder arena,
  final int start,
  final int end,
) {
  int _next = arena._edges.used;
  int _previous = start;
  this {
    arena._checkRange(start, end);
  }
  void add(int? child, _ChildType expected) {
    if (child == null) return;
    _previous = arena._checkEdge(child, _previous, end, expected);
    final edges = arena._edges;
    if (_next == edges.cells.length) edges._grow(_next + 1, _next);
    edges.cells[_next++] = child;
  }

  int addAll(List<int> children, _ChildType expected) {
    arena._writable = false;
    try {
      final length = RangeError.checkNotNegative(children.length, 'length');
      final edges = arena._edges;
      final limit = _next + length;
      if (limit > edges.cells.length) edges._grow(limit, _next);
      for (var i = 0; i < length; i++) {
        final child = children[i];
        _previous = arena._checkEdge(child, _previous, end, expected);
        edges.cells[_next++] = child;
      }
      return length;
    } finally {
      arena._writable = true;
    }
  }

  int finish(SyntaxKind kind) {
    arena._edges.used = _next;
    return arena._finishRow(kind, start, end);
  }
}

/// Builds an indexed syntax tree for one source snapshot.
///
/// Each node method returns a local index. Supply children before their parent,
/// in source order. Their kinds and ranges are checked on insertion.
/// Method names match the typed node classes. Child indices must belong to this
/// builder. An integer from another builder denotes the local row with that
/// number. Use [indexOf] to check the owner of a typed node.
/// [finish] seals the builder and publishes an immutable tree.
///
/// {@example /example/indexed_syntax.dart#build}
final class SyntaxTreeBuilder._(
  final SourceFile source,
  int capacity,
  int tokenCount,
) with _SyntaxAccess {
  @override
  SyntaxTreeBuilder get _data => this;
  bool _writable = true;
  (SyntaxTree, int, int, int)? _replacement;

  /// Creates a builder for [source]. [expectedTokens] is an optional capacity hint.
  factory SyntaxTreeBuilder(SourceFile source, {int expectedTokens = 0}) {
    RangeError.checkNotNegative(expectedTokens, 'expectedTokens');
    expectedTokens = expectedTokens.clamp(0, source.length + 1);
    return SyntaxTreeBuilder._(
      source,
      expectedTokens + expectedTokens ~/ 8,
      expectedTokens - expectedTokens ~/ 4,
    );
  }

  static SyntaxTreeBuilder _copy(
    SyntaxTreeBuilder old,
    SourceFile source,
    int rows,
    int edges,
    int fields,
    int rowCapacity,
    int fieldCapacity,
  ) {
    final arena = SyntaxTreeBuilder._(source, rowCapacity, fieldCapacity);
    arena._tags.setRange(0, rows, old._tags);
    if (old._rangeShift == arena._rangeShift) {
      arena._ranges.setRange(0, rows << arena._rangeShift, old._ranges);
    } else {
      for (var i = 0; i < rows; i++) {
        arena._setRange(i, old._start(i), old._end(i));
      }
    }
    arena._offsets.setRange(0, rows, old._offsets);
    arena._edgeOffsets.setRange(0, rows + 1, old._edgeOffsets);
    arena._edges.reserve(edges);
    arena._edges.cells.setRange(0, edges, old._edges.cells);
    arena._fields.reserve(fields);
    arena._fields.cells.setRange(0, fields, old._fields.cells);
    arena._count = rows;
    return arena;
  }

  /// Restores the rest of the tree if [replacement] preserves its referenced rows.
  ///
  /// Seals the builder on success. Returns null when a different layout
  /// requires rebuilding the parent.
  SyntaxTree? finishReplacement(int replacement) {
    final edit = _replacement;
    _checkWritable();
    if (edit == null) throw StateError('No pending replacement.');
    final (tree, node, first, change) = edit;
    final old = tree._data;
    if (replacement != node ||
        _count != node + 1 ||
        node + 1 >= old._count ||
        old._edgeOffsets[node + 1] != _edges.used ||
        old._offsets[node + 1] != _fields.used) {
      return null;
    }
    final delta = source.length - tree.source.length;
    int move(int offset) {
      if (offset <= change || delta == 0) return offset;
      final shifted = offset + delta;
      return shifted < change ? change : shifted;
    }

    // Other rows may reference any of these indices, including shared children.
    for (var i = first; i <= node; i++) {
      if (_tags[i] != old._tags[i] ||
          _start(i) != move(old._start(i)) ||
          _end(i) != move(old._end(i))) {
        return null;
      }
    }
    if (delta != 0) {
      for (var i = node + 1; i < old._count; i++) {
        final oldStart = old._start(i), oldEnd = old._end(i);
        if (oldStart > change && oldStart + delta >= change) {
          _setRange(i, oldStart + delta, oldEnd + delta);
          continue;
        }
        final kind = old._kindAt(i);
        final start = move(oldStart);
        final end = kind == .compilationUnit ? source.length : move(oldEnd);
        if (end - start != oldEnd - oldStart &&
            (kind == .functionParameterSuffix ||
                kind == .functionTypeAnnotation ||
                kind == .namedTypeAnnotation ||
                kind == .recordTypeAnnotation)) {
          return null;
        }
        _setRange(i, start, end);
      }
    }
    _count = old._count;
    _edges.used = old._edges.used;
    _fields.used = old._fields.used;
    _replacement = null;
    return finish(tree.root);
  }

  /// Visits a subtree in depth-first source order.
  Iterable<int> walk(int node) => _IndexWalk(this, _check(node));

  /// The source text covered by [node].
  String text(int node) {
    _check(node);
    return source.text.substring(_start(node), _end(node));
  }

  /// Publishes the tree rooted at [root] and closes this builder to writes.
  SyntaxTree finish(int root) {
    if (!_writable || _replacement != null) {
      throw StateError('The builder cannot finish.');
    }
    final node = _check(root);
    _writable = false;
    return SyntaxTree._(this, node);
  }

  int _count = 0;
  Uint8List _tags = Uint8List(capacity);
  // A short snapshot fits both UTF-16 offsets in one 32-bit word.
  final int _rangeShift = source.length <= 0xffff ? 0 : 1;
  Uint32List _ranges = Uint32List(
    capacity << (source.length <= 0xffff ? 0 : 1),
  );
  Uint32List _edgeOffsets = Uint32List(capacity + 1),
      _offsets = Uint32List(capacity);
  int _start(int row) =>
      _rangeShift == 0 ? _ranges[row] >>> 16 : _ranges[row * 2];
  int _end(int row) =>
      _rangeShift == 0 ? _ranges[row] & 0xffff : _ranges[row * 2 + 1];
  void _setRange(int row, int start, int end) {
    if (_rangeShift == 0) {
      _ranges[row] = start << 16 | end;
    } else {
      _ranges[row * 2] = start;
      _ranges[row * 2 + 1] = end;
    }
  }

  final _edges = _Words(capacity), _fields = _Words(tokenCount);
  void _grow() {
    if (_count == _nil) {
      throw RangeError('Syntax tree exceeds 32-bit node indices');
    }
    final n = _nextCapacity(_count).clamp(0, _nil);
    _tags = Uint8List(n)..setRange(0, _count, _tags);
    _ranges = Uint32List(n << _rangeShift)
      ..setRange(0, _count << _rangeShift, _ranges);
    _offsets = Uint32List(n)..setRange(0, _count, _offsets);
    _edgeOffsets = Uint32List(n + 1)..setRange(0, _count + 1, _edgeOffsets);
  }

  void _checkWritable() {
    if (!_writable) throw StateError('The syntax builder is closed to writes.');
  }

  void _checkRange(int start, int end) {
    _checkWritable();
    if (start < 0 || start > end || end > source.length) {
      RangeError.checkValidRange(start, end, source.length);
    }
    if (end >= _nil) {
      throw RangeError('Syntax range or node index exceeds 32 bits');
    }
  }

  int _finishRow(SyntaxKind kind, int start, int end) {
    if (_count == _tags.length) _grow();
    final row = _count++;
    _tags[row] = kind.index;
    _setRange(row, start, end);
    _edgeOffsets[row + 1] = _edges.used;
    _offsets[row] = _fields.used;
    return row;
  }

  int _leaf(SyntaxKind kind, int start, int end) {
    _checkRange(start, end);
    return _finishRow(kind, start, end);
  }

  void _checkKind(int id, _ChildType expected) {
    if (id < 0 || id >= _count) {
      RangeError.checkValidIndex(id, this, 'child', _count);
    }
    final tag = _tags[id];
    if (!expected.accepts(tag)) {
      throw ArgumentError.value(
        id,
        'child',
        'Expected ${expected.name}, found ${SyntaxKind.values[tag].name}.',
      );
    }
  }

  int _checkEdge(int id, int start, int end, _ChildType expected) {
    _checkKind(id, expected);
    final childEnd = _end(id);
    if (_start(id) < start || childEnd > end) {
      throw ArgumentError('Child outside range');
    }
    return childEnd;
  }

  int _cover(
    SyntaxKind kind,
    int first,
    _ChildType firstKind, [
    int? last,
    _ChildType? lastKind,
  ]) {
    _checkWritable();
    _checkKind(first, firstKind);
    var end = _end(first);
    if (last == null) {
      _edges.add(first);
    } else {
      _checkKind(last, lastKind!);
      if (_start(last) < end) throw ArgumentError('Child ranges overlap.');
      end = _end(last);
      final slot = _edges.reserve(2);
      _edges.cells[slot] = first;
      _edges.cells[slot + 1] = last;
    }
    return _finishRow(kind, _start(first), end);
  }

  int _appendOne(
    SyntaxKind kind,
    int start,
    int end,
    int id,
    _ChildType expected,
  ) {
    _checkRange(start, end);
    _checkEdge(id, start, end, expected);
    _edges.add(id);
    return _finishRow(kind, start, end);
  }

  int _appendTwo(
    SyntaxKind kind,
    int start,
    int end,
    int first,
    _ChildType firstKind,
    int second,
    _ChildType secondKind,
  ) {
    _checkRange(start, end);
    final next = _checkEdge(first, start, end, firstKind);
    _checkEdge(second, next, end, secondKind);
    final base = _edges.reserve(2);
    _edges.cells[base] = first;
    _edges.cells[base + 1] = second;
    return _finishRow(kind, start, end);
  }

  int _childCount(int row) => _edgeOffsets[row + 1] - _edgeOffsets[row];
  int _childIndex(int row, int index) =>
      _edges.cells[_edgeOffsets[row] + index];
  int _trailingChild(int row, int fromEnd) =>
      _edges.cells[_edgeOffsets[row + 1] - fromEnd];
  int? _optionalChild(int row, int index, int fullCount) =>
      _childCount(row) == fullCount ? _childIndex(row, index) : null;

  int _appendOptional(
    SyntaxKind kind,
    int start,
    int end,
    int? a,
    _ChildType aKind, [
    int? b,
    _ChildType? bKind,
    int? c,
    _ChildType? cKind,
  ]) {
    _checkRange(start, end);
    var next = start;
    if (a != null) next = _checkEdge(a, next, end, aKind);
    if (b != null) next = _checkEdge(b, next, end, bKind!);
    if (c != null) _checkEdge(c, next, end, cKind!);
    final length =
        (a == null ? 0 : 1) + (b == null ? 0 : 1) + (c == null ? 0 : 1);
    var slot = _edges.reserve(length);
    if (a != null) _edges.cells[slot++] = a;
    if (b != null) _edges.cells[slot++] = b;
    if (c != null) _edges.cells[slot] = c;
    return _finishRow(kind, start, end);
  }

  int _appendList(
    SyntaxKind kind,
    int start,
    int end,
    List<int> items,
    _ChildType expected,
  ) {
    final children = _Children(this, start, end)..addAll(items, expected);
    return children.finish(kind);
  }

  int adjacentStringsExpression({
    required int start,
    required int end,
    required List<int> strings,
  }) => _appendList(
    .adjacentStringsExpression,
    start,
    end,
    strings,
    .stringExpression,
  );

  int annotation({
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    final children = _Children(this, start, end);
    final nameCount = children.addAll(name, .identifier);
    children.add(typeArguments, .typeArgumentList);
    children.add(constructorName, .identifier);
    children.add(arguments, .argumentList);
    final row = children.finish(.annotation);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = typeArguments ?? _nil;
    _fields.cells[fieldOffset + 1] = constructorName ?? _nil;
    _fields.cells[fieldOffset + 2] = arguments ?? _nil;
    _fields.cells[fieldOffset + 3] = nameCount;
    return row;
  }

  /// Adds an argument spanning its optional name and its value.
  int argument({int? name, required int value}) => name == null
      ? _cover(.argument, value, .expression)
      : _cover(.argument, name, .identifier, value, .expression);

  int argumentList({
    required int start,
    required int end,
    required List<int> arguments,
  }) => _appendList(.argumentList, start, end, arguments, .argument);

  int assertInitializer({
    required int start,
    required int end,
    required int condition,
    int? message,
  }) => _appendOptional(
    .assertInitializer,
    start,
    end,
    condition,
    .expression,
    message,
    .expression,
  );

  int assertStatement({
    required int start,
    required int end,
    required int condition,
    int? message,
  }) => _appendOptional(
    .assertStatement,
    start,
    end,
    condition,
    .expression,
    message,
    .expression,
  );

  int assignmentExpression({
    required int left,
    required AssignmentOperator op,
    required int right,
  }) {
    final row = _cover(
      .assignmentExpression,
      left,
      .expression,
      right,
      .expression,
    );
    _fields.add(op.index);
    return row;
  }

  int awaitExpression({required int start, required int expression}) {
    final end = this.end(expression);
    return _appendOne(.awaitExpression, start, end, expression, .expression);
  }

  int binaryExpression({
    required int left,
    required BinaryOperator op,
    required int right,
  }) {
    final row = _cover(
      .binaryExpression,
      left,
      .expression,
      right,
      .expression,
    );
    _fields.add(op.index);
    return row;
  }

  int blockStatement({
    required int start,
    required int end,
    required List<int> statements,
  }) => _appendList(.blockStatement, start, end, statements, .statement);

  int breakStatement({required int start, required int end, int? label}) =>
      _appendOptional(.breakStatement, start, end, label, .identifier);

  int cascadeExpression({
    required int end,
    required int target,
    bool isNullAware = false,
    required List<int> sections,
  }) {
    final start = this.start(target);
    final children = _Children(this, start, end);
    children.add(target, .expression);
    final sectionsCount = children.addAll(sections, .expression);
    final row = children.finish(.cascadeExpression);
    _fields.addTriple(target, isNullAware ? 1 : 0, sectionsCount);
    return row;
  }

  int cascadeIndexExpression({
    required int start,
    required int end,
    required int index,
  }) => _appendOne(.cascadeIndexExpression, start, end, index, .expression);

  int cascadePropertyExpression({
    required int start,
    required int end,
    required int property,
  }) =>
      _appendOne(.cascadePropertyExpression, start, end, property, .identifier);

  int castExpression({required int expression, required int type}) =>
      _cover(.castExpression, expression, .expression, type, .typeAnnotation);

  int castPattern({required int pattern, required int type}) =>
      _cover(.castPattern, pattern, .dartPattern, type, .typeAnnotation);

  int catchClause({
    required int start,
    int? exceptionType,
    int? exceptionParameter,
    int? stackTraceParameter,
    required int body,
  }) {
    final end = this.end(body);
    final children = _Children(this, start, end);
    children.add(exceptionType, .typeAnnotation);
    children.add(exceptionParameter, .identifier);
    children.add(stackTraceParameter, .identifier);
    children.add(body, .blockStatement);
    final row = children.finish(.catchClause);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = exceptionType ?? _nil;
    _fields.cells[fieldOffset + 1] = exceptionParameter ?? _nil;
    _fields.cells[fieldOffset + 2] = stackTraceParameter ?? _nil;
    _fields.cells[fieldOffset + 3] = body;
    return row;
  }

  int classDeclaration({
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
    final copiedModifiers = _freeze(modifiers);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(primaryConstructorName, .identifier);
    children.add(primaryParameters, .formalParameterList);
    children.add(extendsClause, .extendsClause);
    children.add(withClause, .typeListClause);
    children.add(implementsClause, .typeListClause);
    final membersCount = children.addAll(members, .classMember);
    final row = children.finish(.classDeclaration);
    final fieldOffset = _fields.reserve(12 + copiedModifiers.length);
    _fields.cells[fieldOffset] = name;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = isConst ? 1 : 0;
    _fields.cells[fieldOffset + 3] = primaryConstructorName ?? _nil;
    _fields.cells[fieldOffset + 4] = primaryParameters ?? _nil;
    _fields.cells[fieldOffset + 5] = extendsClause ?? _nil;
    _fields.cells[fieldOffset + 6] = withClause ?? _nil;
    _fields.cells[fieldOffset + 7] = implementsClause ?? _nil;
    _fields.cells[fieldOffset + 8] = isSemicolonBody ? 1 : 0;
    _fields.cells[fieldOffset + 9] = metadataCount;
    _fields.cells[fieldOffset + 10] = copiedModifiers.length;
    _fields.cells[fieldOffset + 11] = membersCount;
    for (var i = 0; i < copiedModifiers.length; i++) {
      _fields.cells[fieldOffset + 12 + i] = copiedModifiers[i].index;
    }
    return row;
  }

  int classTypeAliasDeclaration({
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
    final copiedModifiers = _freeze(modifiers);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(superclass, .typeAnnotation);
    children.add(withClause, .typeListClause);
    children.add(implementsClause, .typeListClause);
    final row = children.finish(.classTypeAliasDeclaration);
    final fieldOffset = _fields.reserve(7 + copiedModifiers.length);
    _fields.cells[fieldOffset] = name;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = superclass;
    _fields.cells[fieldOffset + 3] = withClause;
    _fields.cells[fieldOffset + 4] = implementsClause ?? _nil;
    _fields.cells[fieldOffset + 5] = metadataCount;
    _fields.cells[fieldOffset + 6] = copiedModifiers.length;
    for (var i = 0; i < copiedModifiers.length; i++) {
      _fields.cells[fieldOffset + 7 + i] = copiedModifiers[i].index;
    }
    return row;
  }

  int collectionExpression({
    required int start,
    required int end,
    required CollectionLiteralKind kind,
    bool hasConstKeyword = false,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end);
    children.add(typeArguments, .typeArgumentList);
    final elementsCount = children.addAll(elements, .collectionElement);
    final row = children.finish(.collectionExpression);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = kind.index;
    _fields.cells[fieldOffset + 1] = hasConstKeyword ? 1 : 0;
    _fields.cells[fieldOffset + 2] = typeArguments ?? _nil;
    _fields.cells[fieldOffset + 3] = elementsCount;
    return row;
  }

  int compilationUnit({int? scriptTag, required List<int> members}) {
    final start = 0;
    final end = source.length;
    final children = _Children(this, start, end);
    children.add(scriptTag, .scriptTag);
    final membersCount = children.addAll(members, .compilationUnitMember);
    final row = children.finish(.compilationUnit);
    _fields.addPair(scriptTag ?? _nil, membersCount);
    return row;
  }

  int conditionalExpression({
    required int condition,
    required int thenExpression,
    required int elseExpression,
  }) {
    final end = this.end(elseExpression);
    final start = this.start(condition);
    final children = _Children(this, start, end);
    children.add(condition, .expression);
    children.add(thenExpression, .expression);
    children.add(elseExpression, .expression);
    return children.finish(.conditionalExpression);
  }

  int conditionalUri({
    required int start,
    required int name,
    int? value,
    required int uri,
  }) {
    final end = this.end(uri);
    return _appendOptional(
      .conditionalUri,
      start,
      end,
      name,
      .dottedName,
      value,
      .stringExpression,
      uri,
      .stringExpression,
    );
  }

  int constDotShorthandExpression({
    required int start,
    required int end,
    required int name,
    int? typeArguments,
    int? arguments,
  }) {
    final children = _Children(this, start, end);
    children.add(name, .identifier);
    children.add(typeArguments, .typeArgumentList);
    children.add(arguments, .argumentList);
    final row = children.finish(.constDotShorthandExpression);
    _fields.addTriple(name, typeArguments ?? _nil, arguments ?? _nil);
    return row;
  }

  int constantPattern({
    required int start,
    bool hasConstKeyword = false,
    required int expression,
  }) {
    final end = this.end(expression);
    final row = _appendOne(
      .constantPattern,
      start,
      end,
      expression,
      .expression,
    );
    _fields.add(hasConstKeyword ? 1 : 0);
    return row;
  }

  int constructorDeclaration({
    required int start,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isConst = false,
    ConstructorKeyword keyword = .none,
    List<int> name = const [],
    required int parameters,
    List<int> initializers = const [],
    required int body,
  }) {
    final end = this.end(body);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    final nameCount = children.addAll(name, .identifier);
    children.add(parameters, .formalParameterList);
    final initializersCount = children.addAll(
      initializers,
      .constructorInitializer,
    );
    children.add(body, .constructorBody);
    final row = children.finish(.constructorDeclaration);
    final fieldOffset = _fields.reserve(8);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isConst ? 1 : 0;
    _fields.cells[fieldOffset + 2] = keyword.index;
    _fields.cells[fieldOffset + 3] = parameters;
    _fields.cells[fieldOffset + 4] = body;
    _fields.cells[fieldOffset + 5] = metadataCount;
    _fields.cells[fieldOffset + 6] = nameCount;
    _fields.cells[fieldOffset + 7] = initializersCount;
    return row;
  }

  int continueStatement({required int start, required int end, int? label}) =>
      _appendOptional(.continueStatement, start, end, label, .identifier);

  int declaredIdentifier({
    required int start,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    final end = this.end(name);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    children.add(name, .identifier);
    final row = children.finish(.declaredIdentifier);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = keyword.index;
    _fields.cells[fieldOffset + 1] = type ?? _nil;
    _fields.cells[fieldOffset + 2] = name;
    _fields.cells[fieldOffset + 3] = metadataCount;
    return row;
  }

  int doStatement({
    required int start,
    required int end,
    required int body,
    required int condition,
  }) => _appendTwo(
    .doStatement,
    start,
    end,
    body,
    .statement,
    condition,
    .expression,
  );

  int dotShorthandExpression({required int expression}) =>
      _cover(.dotShorthandExpression, expression, .expression);

  int dotShorthandReferenceExpression({required int start, required int name}) {
    final end = this.end(name);
    return _appendOne(
      .dotShorthandReferenceExpression,
      start,
      end,
      name,
      .identifier,
    );
  }

  int dottedName({
    required int start,
    required int end,
    required List<int> components,
  }) => _appendList(.dottedName, start, end, components, .identifier);

  int emptyFunctionBody({required int start, required int end}) =>
      _leaf(.emptyFunctionBody, start, end);

  int emptyStatement({required int start, required int end}) =>
      _leaf(.emptyStatement, start, end);

  int enumConstantDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeArguments, .typeArgumentList);
    children.add(constructorName, .identifier);
    children.add(arguments, .argumentList);
    final row = children.finish(.enumConstantDeclaration);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = name;
    _fields.cells[fieldOffset + 1] = typeArguments ?? _nil;
    _fields.cells[fieldOffset + 2] = constructorName ?? _nil;
    _fields.cells[fieldOffset + 3] = arguments ?? _nil;
    _fields.cells[fieldOffset + 4] = metadataCount;
    return row;
  }

  int enumDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(primaryConstructorName, .identifier);
    children.add(primaryParameters, .formalParameterList);
    children.add(withClause, .typeListClause);
    children.add(implementsClause, .typeListClause);
    final constantsCount = children.addAll(constants, .enumConstantDeclaration);
    final membersCount = children.addAll(members, .classMember);
    final row = children.finish(.enumDeclaration);
    final fieldOffset = _fields.reserve(12);
    _fields.cells[fieldOffset] = name;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = isConst ? 1 : 0;
    _fields.cells[fieldOffset + 3] = primaryConstructorName ?? _nil;
    _fields.cells[fieldOffset + 4] = primaryParameters ?? _nil;
    _fields.cells[fieldOffset + 5] = withClause ?? _nil;
    _fields.cells[fieldOffset + 6] = implementsClause ?? _nil;
    _fields.cells[fieldOffset + 7] = isSemicolonBody ? 1 : 0;
    _fields.cells[fieldOffset + 8] = hasMemberSeparator ? 1 : 0;
    _fields.cells[fieldOffset + 9] = metadataCount;
    _fields.cells[fieldOffset + 10] = constantsCount;
    _fields.cells[fieldOffset + 11] = membersCount;
    return row;
  }

  int exportDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    List<int> combinators = const [],
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(uri, .stringExpression);
    final configurationsCount = children.addAll(
      configurations,
      .conditionalUri,
    );
    final combinatorsCount = children.addAll(combinators, .namespaceCombinator);
    final row = children.finish(.exportDirective);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = uri;
    _fields.cells[fieldOffset + 1] = configurationsCount;
    _fields.cells[fieldOffset + 2] = combinatorsCount;
    _fields.cells[fieldOffset + 3] = metadataCount;
    return row;
  }

  int expressionFunctionBody({
    required int start,
    required int end,
    bool isAsync = false,
    required int expression,
  }) {
    final row = _appendOne(
      .expressionFunctionBody,
      start,
      end,
      expression,
      .expression,
    );
    _fields.add(isAsync ? 1 : 0);
    return row;
  }

  int expressionStatement({required int end, required int expression}) {
    final start = this.start(expression);
    return _appendOne(
      .expressionStatement,
      start,
      end,
      expression,
      .expression,
    );
  }

  int extendsClause({required int start, required int superclass}) {
    final end = this.end(superclass);
    return _appendOne(.extendsClause, start, end, superclass, .typeAnnotation);
  }

  int extensionDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
    int? typeParameters,
    required int onType,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(onType, .typeAnnotation);
    final membersCount = children.addAll(members, .classMember);
    final row = children.finish(.extensionDeclaration);
    final fieldOffset = _fields.reserve(6);
    _fields.cells[fieldOffset] = name ?? _nil;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = onType;
    _fields.cells[fieldOffset + 3] = isSemicolonBody ? 1 : 0;
    _fields.cells[fieldOffset + 4] = metadataCount;
    _fields.cells[fieldOffset + 5] = membersCount;
    return row;
  }

  int extensionTypeDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(primaryConstructorName, .identifier);
    children.add(primaryParameters, .formalParameterList);
    children.add(implementsClause, .typeListClause);
    final membersCount = children.addAll(members, .classMember);
    final row = children.finish(.extensionTypeDeclaration);
    final fieldOffset = _fields.reserve(9);
    _fields.cells[fieldOffset] = isConst ? 1 : 0;
    _fields.cells[fieldOffset + 1] = name;
    _fields.cells[fieldOffset + 2] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 3] = primaryConstructorName ?? _nil;
    _fields.cells[fieldOffset + 4] = primaryParameters;
    _fields.cells[fieldOffset + 5] = implementsClause ?? _nil;
    _fields.cells[fieldOffset + 6] = isSemicolonBody ? 1 : 0;
    _fields.cells[fieldOffset + 7] = metadataCount;
    _fields.cells[fieldOffset + 8] = membersCount;
    return row;
  }

  int factoryRedirectBody({
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
  }) {
    final children = _Children(this, start, end);
    final nameCount = children.addAll(name, .identifier);
    children.add(typeArguments, .typeArgumentList);
    children.add(constructorName, .identifier);
    final row = children.finish(.factoryRedirectBody);
    _fields.addTriple(
      typeArguments ?? _nil,
      constructorName ?? _nil,
      nameCount,
    );
    return row;
  }

  int fieldDeclaration({
    required int start,
    required int end,
    bool isStatic = false,
    bool isAbstract = false,
    bool isExternal = false,
    bool isCovariant = false,
    required int variables,
  }) {
    final row = _appendOne(
      .fieldDeclaration,
      start,
      end,
      variables,
      .variableDeclarationList,
    );
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = isStatic ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isAbstract ? 1 : 0;
    _fields.cells[fieldOffset + 2] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 3] = isCovariant ? 1 : 0;
    return row;
  }

  int fieldInitializer({
    required int start,
    bool hasThis = false,
    required int name,
    required int value,
  }) {
    final end = this.end(value);
    final row = _appendTwo(
      .fieldInitializer,
      start,
      end,
      name,
      .identifier,
      value,
      .expression,
    );
    _fields.add(hasThis ? 1 : 0);
    return row;
  }

  int forElement({
    required int start,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    final end = this.end(body);
    final row = _appendTwo(
      .forElement,
      start,
      end,
      parts,
      .forLoopParts,
      body,
      .collectionElement,
    );
    _fields.add(isAwait ? 1 : 0);
    return row;
  }

  int forInParts({
    required int start,
    required int target,
    required int iterable,
  }) {
    final end = this.end(iterable);
    return _appendTwo(
      .forInParts,
      start,
      end,
      target,
      .forInTarget,
      iterable,
      .expression,
    );
  }

  int forParts({
    required int start,
    required int end,
    int? initializer,
    int? condition,
    List<int> updaters = const [],
  }) {
    final children = _Children(this, start, end);
    children.add(initializer, .forInitializer);
    children.add(condition, .expression);
    final updatersCount = children.addAll(updaters, .expression);
    final row = children.finish(.forParts);
    _fields.addTriple(initializer ?? _nil, condition ?? _nil, updatersCount);
    return row;
  }

  int forStatement({
    required int start,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    final end = this.end(body);
    final row = _appendTwo(
      .forStatement,
      start,
      end,
      parts,
      .forLoopParts,
      body,
      .statement,
    );
    _fields.add(isAwait ? 1 : 0);
    return row;
  }

  int formalParameter({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    children.add(name, .identifier);
    children.add(functionSuffix, .functionParameterSuffix);
    children.add(defaultClause, .parameterDefault);
    final row = children.finish(.formalParameter);
    final at = _fields.reserve(5);
    _fields.cells[at] = kind.index;
    _fields.cells[at + 1] = prefix.index;
    _fields.cells[at + 2] = keyword.index;
    _fields.cells[at + 3] =
        (type == null ? 0 : _formalType) |
        (functionSuffix == null ? 0 : _formalSuffix) |
        (defaultClause == null ? 0 : _formalDefault) |
        (isCovariant ? _formalCovariant : 0);
    _fields.cells[at + 4] = metadataCount;
    return row;
  }

  int formalParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) => _appendList(
    .formalParameterList,
    start,
    end,
    parameters,
    .formalParameter,
  );

  int functionExpression({
    required int start,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    final end = this.end(body);
    return _appendOptional(
      .functionExpression,
      start,
      end,
      typeParameters,
      .typeParameterList,
      parameters,
      .formalParameterList,
      body,
      .functionBody,
    );
  }

  int functionParameterSuffix({
    required int start,
    required int end,
    int? typeParameters,
    required int parameters,
    int? questionOffset,
  }) {
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        _end(parameters),
        end - 1,
        "questionOffset",
      );
    }
    final row = _appendOptional(
      .functionParameterSuffix,
      start,
      end,
      typeParameters,
      .typeParameterList,
      parameters,
      .formalParameterList,
    );
    _fields.add(questionOffset == null ? _nil : end - questionOffset);
    return row;
  }

  int functionTypeAliasDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(parameters, .formalParameterList);
    final row = children.finish(.functionTypeAliasDeclaration);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = returnType ?? _nil;
    _fields.cells[fieldOffset + 1] = name;
    _fields.cells[fieldOffset + 2] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 3] = parameters;
    _fields.cells[fieldOffset + 4] = metadataCount;
    return row;
  }

  int functionTypeAnnotation({
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
    final children = _Children(this, start, end);
    children.add(returnType, .typeAnnotation);
    children.add(typeParameters, .typeParameterList);
    children.add(parameters, .functionTypeParameterList);
    final row = children.finish(.functionTypeAnnotation);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = returnType ?? _nil;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = parameters;
    _fields.cells[fieldOffset + 3] = questionOffset == null
        ? _nil
        : end - questionOffset;
    return row;
  }

  int functionTypeParameter({
    required int start,
    required int end,
    List<int> metadata = const [],
    required FunctionTypeParameterKind kind,
    bool isCovariant = false,
    required int type,
    int? name,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    children.add(name, .identifier);
    final row = children.finish(.functionTypeParameter);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = kind.index;
    _fields.cells[fieldOffset + 1] = isCovariant ? 1 : 0;
    _fields.cells[fieldOffset + 2] = type;
    _fields.cells[fieldOffset + 3] = name ?? _nil;
    _fields.cells[fieldOffset + 4] = metadataCount;
    return row;
  }

  int functionTypeParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) => _appendList(
    .functionTypeParameterList,
    start,
    end,
    parameters,
    .functionTypeParameter,
  );

  int getterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(body, .functionBody);
    final row = children.finish(.getterDeclaration);
    final fieldOffset = _fields.reserve(6);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    _fields.cells[fieldOffset + 2] = returnType ?? _nil;
    _fields.cells[fieldOffset + 3] = name;
    _fields.cells[fieldOffset + 4] = body;
    _fields.cells[fieldOffset + 5] = metadataCount;
    return row;
  }

  int guardedPattern({required int pattern, required int guard}) =>
      _cover(.guardedPattern, pattern, .dartPattern, guard, .expression);

  int identifier({required int start, required int end}) =>
      _leaf(.identifier, start, end);

  /// Wraps an identifier using its existing source range.
  int identifierExpression(int identifier) =>
      _cover(.identifierExpression, identifier, .identifier);

  int identifierPattern({required int start, required int name}) {
    final end = this.end(name);
    return _appendOne(.identifierPattern, start, end, name, .identifier);
  }

  int ifElement({
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenElement,
    int? elseElement,
  }) {
    final children = _Children(this, start, end);
    children.add(condition, .expression);
    children.add(casePattern, .casePattern);
    children.add(thenElement, .collectionElement);
    children.add(elseElement, .collectionElement);
    final row = children.finish(.ifElement);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = condition;
    _fields.cells[fieldOffset + 1] = casePattern ?? _nil;
    _fields.cells[fieldOffset + 2] = thenElement;
    _fields.cells[fieldOffset + 3] = elseElement ?? _nil;
    return row;
  }

  int ifStatement({
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenStatement,
    int? elseStatement,
  }) {
    final children = _Children(this, start, end);
    children.add(condition, .expression);
    children.add(casePattern, .casePattern);
    children.add(thenStatement, .statement);
    children.add(elseStatement, .statement);
    final row = children.finish(.ifStatement);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = condition;
    _fields.cells[fieldOffset + 1] = casePattern ?? _nil;
    _fields.cells[fieldOffset + 2] = thenStatement;
    _fields.cells[fieldOffset + 3] = elseStatement ?? _nil;
    return row;
  }

  int importDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    bool isDeferred = false,
    int? prefix,
    List<int> combinators = const [],
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(uri, .stringExpression);
    final configurationsCount = children.addAll(
      configurations,
      .conditionalUri,
    );
    children.add(prefix, .identifier);
    final combinatorsCount = children.addAll(combinators, .namespaceCombinator);
    final row = children.finish(.importDirective);
    final fieldOffset = _fields.reserve(6);
    _fields.cells[fieldOffset] = uri;
    _fields.cells[fieldOffset + 1] = isDeferred ? 1 : 0;
    _fields.cells[fieldOffset + 2] = prefix ?? _nil;
    _fields.cells[fieldOffset + 3] = configurationsCount;
    _fields.cells[fieldOffset + 4] = combinatorsCount;
    _fields.cells[fieldOffset + 5] = metadataCount;
    return row;
  }

  int indexExpression({
    required int end,
    required int target,
    required int index,
    bool isNullAware = false,
  }) {
    final start = this.start(target);
    final row = _appendTwo(
      .indexExpression,
      start,
      end,
      target,
      .expression,
      index,
      .expression,
    );
    _fields.add(isNullAware ? 1 : 0);
    return row;
  }

  int instanceCreationExpression({
    required int start,
    required int end,
    InstanceCreationKind kind = .implicit,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    required int arguments,
  }) {
    final children = _Children(this, start, end);
    final nameCount = children.addAll(name, .identifier);
    children.add(typeArguments, .typeArgumentList);
    children.add(constructorName, .identifier);
    children.add(arguments, .argumentList);
    final row = children.finish(.instanceCreationExpression);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = kind.index;
    _fields.cells[fieldOffset + 1] = typeArguments ?? _nil;
    _fields.cells[fieldOffset + 2] = constructorName ?? _nil;
    _fields.cells[fieldOffset + 3] = arguments;
    _fields.cells[fieldOffset + 4] = nameCount;
    return row;
  }

  int interpolatedStringExpression({
    required int start,
    required int end,
    required List<int> parts,
  }) => _appendList(
    .interpolatedStringExpression,
    start,
    end,
    parts,
    .stringPart,
  );

  int invocationExpression({
    required int end,
    required int callee,
    int? typeArguments,
    required int arguments,
  }) {
    final start = this.start(callee);
    return _appendOptional(
      .invocationExpression,
      start,
      end,
      callee,
      .expression,
      typeArguments,
      .typeArgumentList,
      arguments,
      .argumentList,
    );
  }

  int label({required int end, required int name}) {
    final start = this.start(name);
    return _appendOne(.label, start, end, name, .identifier);
  }

  int labeledStatement({
    required int start,
    required List<int> labels,
    required int statement,
  }) {
    final end = this.end(statement);
    final children = _Children(this, start, end);
    final labelsCount = children.addAll(labels, .label);
    children.add(statement, .statement);
    final row = children.finish(.labeledStatement);
    _fields.addPair(statement, labelsCount);
    return row;
  }

  int libraryDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .dottedName);
    final row = children.finish(.libraryDirective);
    _fields.addPair(name ?? _nil, metadataCount);
    return row;
  }

  int listPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end);
    children.add(typeArguments, .typeArgumentList);
    final elementsCount = children.addAll(elements, .listPatternElement);
    final row = children.finish(.listPattern);
    _fields.addPair(typeArguments ?? _nil, elementsCount);
    return row;
  }

  int literalExpression({
    required int start,
    required int end,
    required LiteralKind kind,
  }) {
    final row = _leaf(.literalExpression, start, end);
    _fields.add(kind.index);
    return row;
  }

  int localFunctionDeclaration({
    required int start,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    final end = this.end(body);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.localFunctionDeclaration);
    final fieldOffset = _fields.reserve(6);
    _fields.cells[fieldOffset] = returnType ?? _nil;
    _fields.cells[fieldOffset + 1] = name;
    _fields.cells[fieldOffset + 2] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 3] = parameters;
    _fields.cells[fieldOffset + 4] = body;
    _fields.cells[fieldOffset + 5] = metadataCount;
    return row;
  }

  int logicalPattern({
    required int left,
    required LogicalPatternOperator op,
    required int right,
  }) {
    final row = _cover(
      .logicalPattern,
      left,
      .dartPattern,
      right,
      .dartPattern,
    );
    _fields.add(op.index);
    return row;
  }

  int mapEntryElement({
    required int start,
    required int key,
    required int value,
    bool isNullAwareKey = false,
    bool isNullAwareValue = false,
  }) {
    final end = this.end(value);
    final row = _appendTwo(
      .mapEntryElement,
      start,
      end,
      key,
      .expression,
      value,
      .expression,
    );
    _fields.addPair(isNullAwareKey ? 1 : 0, isNullAwareValue ? 1 : 0);
    return row;
  }

  int mapPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final children = _Children(this, start, end);
    children.add(typeArguments, .typeArgumentList);
    final elementsCount = children.addAll(elements, .mapPatternElement);
    final row = children.finish(.mapPattern);
    _fields.addPair(typeArguments ?? _nil, elementsCount);
    return row;
  }

  int mapPatternEntry({required int key, required int value}) =>
      _cover(.mapPatternEntry, key, .expression, value, .dartPattern);

  int methodDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.methodDeclaration);
    final fieldOffset = _fields.reserve(8);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    _fields.cells[fieldOffset + 2] = returnType ?? _nil;
    _fields.cells[fieldOffset + 3] = name;
    _fields.cells[fieldOffset + 4] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 5] = parameters;
    _fields.cells[fieldOffset + 6] = body;
    _fields.cells[fieldOffset + 7] = metadataCount;
    return row;
  }

  int missingClassMember({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingClassMember, start, end);
  }

  int missingExpression({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingExpression, start, end);
  }

  int missingFunctionBody({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingFunctionBody, start, end);
  }

  int missingPattern({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingPattern, start, end);
  }

  int missingStatement({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingStatement, start, end);
  }

  int missingStringExpression({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingStringExpression, start, end);
  }

  int missingTopLevelDeclaration({required int offset}) {
    final start = offset;
    final end = offset;
    return _leaf(.missingTopLevelDeclaration, start, end);
  }

  int missingTypeAnnotation({required int offset}) =>
      _leaf(.missingTypeAnnotation, offset, offset);

  int mixinDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(onClause, .typeListClause);
    children.add(implementsClause, .typeListClause);
    final membersCount = children.addAll(members, .classMember);
    final row = children.finish(.mixinDeclaration);
    final fieldOffset = _fields.reserve(8);
    _fields.cells[fieldOffset] = isBase ? 1 : 0;
    _fields.cells[fieldOffset + 1] = name;
    _fields.cells[fieldOffset + 2] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 3] = onClause ?? _nil;
    _fields.cells[fieldOffset + 4] = implementsClause ?? _nil;
    _fields.cells[fieldOffset + 5] = isSemicolonBody ? 1 : 0;
    _fields.cells[fieldOffset + 6] = metadataCount;
    _fields.cells[fieldOffset + 7] = membersCount;
    return row;
  }

  int modifiedBlockFunctionBody({
    required int start,
    required FunctionBodyModifier modifier,
    required int block,
  }) {
    final end = this.end(block);
    final row = _appendOne(
      .modifiedBlockFunctionBody,
      start,
      end,
      block,
      .blockStatement,
    );
    _fields.add(modifier.index);
    return row;
  }

  int namedPatternField({required int start, int? name, required int pattern}) {
    final end = this.end(pattern);
    return _appendOptional(
      .namedPatternField,
      start,
      end,
      name,
      .identifier,
      pattern,
      .dartPattern,
    );
  }

  int namedRecordField({required int name, required int value}) =>
      _cover(.namedRecordField, name, .identifier, value, .expression);

  int namedRecordTypeField({
    required int start,
    List<int> metadata = const [],
    required int type,
    required int name,
  }) {
    final end = this.end(name);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    children.add(name, .identifier);
    final row = children.finish(.namedRecordTypeField);
    _fields.addTriple(name, type, metadataCount);
    return row;
  }

  // The name follows the optional prefix, so bit zero is also its child index.
  static const _typePrefix = 1, _typeArguments = 2, _typeQuestion = 4;

  int? _namedTypePrefix(int row) =>
      _fields.cells[_offsets[row]] & _typePrefix == 0
      ? null
      : _childIndex(row, 0);

  int? _namedTypeQuestion(int row) {
    final field = _offsets[row];
    return _fields.cells[field] & _typeQuestion == 0
        ? null
        : _end(row) - _fields.cells[field + 1];
  }

  int namedTypeAnnotation({
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
      .identifier,
      name,
      .identifier,
      typeArguments,
      .typeArgumentList,
    );
    final nullable = questionOffset != null;
    final field = _fields.reserve(nullable ? 2 : 1);
    _fields.cells[field] =
        (prefix == null ? 0 : _typePrefix) |
        (typeArguments == null ? 0 : _typeArguments) |
        (nullable ? _typeQuestion : 0);
    if (nullable) _fields.cells[field + 1] = end - questionOffset;
    return row;
  }

  int namespaceCombinator({
    required int start,
    required int end,
    required NamespaceCombinatorKind kind,
    required List<int> names,
  }) {
    final row = _appendList(
      .namespaceCombinator,
      start,
      end,
      names,
      .identifier,
    );
    _fields.add(kind.index);
    return row;
  }

  int nullAssertPattern({required int end, required int pattern}) {
    final start = this.start(pattern);
    return _appendOne(.nullAssertPattern, start, end, pattern, .dartPattern);
  }

  int nullAssertionExpression({required int end, required int operand}) {
    final start = this.start(operand);
    return _appendOne(
      .nullAssertionExpression,
      start,
      end,
      operand,
      .expression,
    );
  }

  int nullAwareElement({required int start, required int expression}) {
    final end = this.end(expression);
    return _appendOne(.nullAwareElement, start, end, expression, .expression);
  }

  int nullCheckPattern({required int end, required int pattern}) {
    final start = this.start(pattern);
    return _appendOne(.nullCheckPattern, start, end, pattern, .dartPattern);
  }

  int objectPattern({
    required int start,
    required int end,
    required int type,
    required List<int> fields,
  }) {
    final children = _Children(this, start, end);
    children.add(type, .namedTypeAnnotation);
    final fieldsCount = children.addAll(fields, .patternField);
    final row = children.finish(.objectPattern);
    _fields.addPair(type, fieldsCount);
    return row;
  }

  int operatorDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.operatorDeclaration);
    final fieldOffset = _fields.reserve(7);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    _fields.cells[fieldOffset + 2] = returnType ?? _nil;
    _fields.cells[fieldOffset + 3] = op.index;
    _fields.cells[fieldOffset + 4] = parameters;
    _fields.cells[fieldOffset + 5] = body;
    _fields.cells[fieldOffset + 6] = metadataCount;
    return row;
  }

  int parameterDefault({
    required int start,
    ParameterDefaultSeparator separator = .equals,
    required int value,
  }) {
    final end = this.end(value);
    final row = _appendOne(.parameterDefault, start, end, value, .expression);
    _fields.add(separator.index);
    return row;
  }

  int parenthesizedExpression({
    required int start,
    required int end,
    required int expression,
  }) =>
      _appendOne(.parenthesizedExpression, start, end, expression, .expression);

  int parenthesizedPattern({
    required int start,
    required int end,
    required int pattern,
  }) => _appendOne(.parenthesizedPattern, start, end, pattern, .dartPattern);

  int partDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(uri, .stringExpression);
    final row = children.finish(.partDirective);
    _fields.addPair(uri, metadataCount);
    return row;
  }

  int partOfDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int target,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(target, .partOfTarget);
    final row = children.finish(.partOfDirective);
    _fields.addPair(target, metadataCount);
    return row;
  }

  int patternAssignmentExpression({required int pattern, required int value}) =>
      _cover(
        .patternAssignmentExpression,
        pattern,
        .dartPattern,
        value,
        .expression,
      );

  int patternForInBinding({
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(pattern, .dartPattern);
    final row = children.finish(.patternForInBinding);
    _fields.addTriple(isFinal ? 1 : 0, pattern, metadataCount);
    return row;
  }

  int patternVariableDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
    required int initializer,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(pattern, .dartPattern);
    children.add(initializer, .expression);
    final row = children.finish(.patternVariableDeclaration);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = isFinal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = pattern;
    _fields.cells[fieldOffset + 2] = initializer;
    _fields.cells[fieldOffset + 3] = metadataCount;
    return row;
  }

  int patternVariableDeclarationStatement({
    required int start,
    required int end,
    required int declaration,
  }) => _appendOne(
    .patternVariableDeclarationStatement,
    start,
    end,
    declaration,
    .patternVariableDeclaration,
  );

  int positionalRecordTypeField({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int type,
    int? name,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    children.add(name, .identifier);
    final row = children.finish(.positionalRecordTypeField);
    _fields.addTriple(name ?? _nil, type, metadataCount);
    return row;
  }

  int primaryConstructorBody({
    required int start,
    List<int> metadata = const [],
    List<int> initializers = const [],
    required int body,
  }) {
    final end = this.end(body);
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    final initializersCount = children.addAll(
      initializers,
      .constructorInitializer,
    );
    children.add(body, .functionBody);
    final row = children.finish(.primaryConstructorBody);
    _fields.addTriple(body, metadataCount, initializersCount);
    return row;
  }

  int propertyAccessExpression({
    required int target,
    required int property,
    bool isNullAware = false,
  }) {
    final row = _cover(
      .propertyAccessExpression,
      target,
      .expression,
      property,
      .identifier,
    );
    _fields.add(isNullAware ? 1 : 0);
    return row;
  }

  int recordExpression({
    required int start,
    required int end,
    bool hasConstKeyword = false,
    required List<int> fields,
  }) {
    final row = _appendList(
      .recordExpression,
      start,
      end,
      fields,
      .recordField,
    );
    _fields.add(hasConstKeyword ? 1 : 0);
    return row;
  }

  int recordPattern({
    required int start,
    required int end,
    required List<int> fields,
  }) => _appendList(.recordPattern, start, end, fields, .patternField);

  int recordTypeAnnotation({
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
    final children = _Children(this, start, end);
    final positionalFieldsCount = children.addAll(
      positionalFields,
      .positionalRecordTypeField,
    );
    children.add(namedFields, .recordTypeNamedFields);
    final row = children.finish(.recordTypeAnnotation);
    _fields.addTriple(
      namedFields ?? _nil,
      positionalFieldsCount,
      questionOffset == null ? _nil : end - questionOffset,
    );
    return row;
  }

  int recordTypeNamedFields({
    required int start,
    required int end,
    required List<int> fields,
  }) => _appendList(
    .recordTypeNamedFields,
    start,
    end,
    fields,
    .namedRecordTypeField,
  );

  int redirectingConstructorInitializer({
    required int start,
    int? name,
    required int arguments,
  }) {
    final end = this.end(arguments);
    return _appendOptional(
      .redirectingConstructorInitializer,
      start,
      end,
      name,
      .identifier,
      arguments,
      .argumentList,
    );
  }

  int relationalPattern({
    required int start,
    required RelationalPatternOperator op,
    required int operand,
  }) {
    final end = this.end(operand);
    final row = _appendOne(
      .relationalPattern,
      start,
      end,
      operand,
      .expression,
    );
    _fields.add(op.index);
    return row;
  }

  int restPatternElement({
    required int start,
    required int end,
    int? pattern,
  }) => _appendOptional(.restPatternElement, start, end, pattern, .dartPattern);

  int rethrowStatement({required int start, required int end}) =>
      _leaf(.rethrowStatement, start, end);

  int returnStatement({
    required int start,
    required int end,
    int? expression,
  }) => _appendOptional(.returnStatement, start, end, expression, .expression);

  int scriptTag({required int start, required int end}) =>
      _leaf(.scriptTag, start, end);

  int setterDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.setterDeclaration);
    final fieldOffset = _fields.reserve(8);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = isStatic ? 1 : 0;
    _fields.cells[fieldOffset + 2] = isCovariant ? 1 : 0;
    _fields.cells[fieldOffset + 3] = returnType ?? _nil;
    _fields.cells[fieldOffset + 4] = name;
    _fields.cells[fieldOffset + 5] = parameters;
    _fields.cells[fieldOffset + 6] = body;
    _fields.cells[fieldOffset + 7] = metadataCount;
    return row;
  }

  int spreadElement({
    required int start,
    required int expression,
    bool isNullAware = false,
  }) {
    final end = this.end(expression);
    final row = _appendOne(.spreadElement, start, end, expression, .expression);
    _fields.add(isNullAware ? 1 : 0);
    return row;
  }

  int stringInterpolation({
    required int start,
    required int end,
    required int expression,
    required bool isBraced,
  }) {
    final row = _appendOne(
      .stringInterpolation,
      start,
      end,
      expression,
      .expression,
    );
    _fields.add(isBraced ? 1 : 0);
    return row;
  }

  int stringLiteralExpression({required int start, required int end}) =>
      _leaf(.stringLiteralExpression, start, end);

  int stringText({required int start, required int end}) =>
      _leaf(.stringText, start, end);

  int superConstructorInitializer({
    required int start,
    int? name,
    required int arguments,
  }) {
    final end = this.end(arguments);
    return _appendOptional(
      .superConstructorInitializer,
      start,
      end,
      name,
      .identifier,
      arguments,
      .argumentList,
    );
  }

  int superExpression({required int start, required int end}) =>
      _leaf(.superExpression, start, end);

  int switchExpression({
    required int start,
    required int end,
    required int expression,
    required List<int> cases,
  }) {
    final children = _Children(this, start, end);
    children.add(expression, .expression);
    final casesCount = children.addAll(cases, .switchExpressionCase);
    final row = children.finish(.switchExpression);
    _fields.addPair(expression, casesCount);
    return row;
  }

  int switchExpressionCase({
    required int start,
    required int pattern,
    required int value,
  }) {
    final end = this.end(value);
    return _appendTwo(
      .switchExpressionCase,
      start,
      end,
      pattern,
      .casePattern,
      value,
      .expression,
    );
  }

  int switchStatement({
    required int start,
    required int end,
    required int expression,
    required List<int> members,
  }) {
    final children = _Children(this, start, end);
    children.add(expression, .expression);
    final membersCount = children.addAll(members, .switchStatementMember);
    final row = children.finish(.switchStatement);
    _fields.addPair(expression, membersCount);
    return row;
  }

  int switchStatementMember({
    required int start,
    required int end,
    List<int> labels = const [],
    int? pattern,
    required List<int> statements,
  }) {
    final children = _Children(this, start, end);
    final labelsCount = children.addAll(labels, .label);
    children.add(pattern, .casePattern);
    final statementsCount = children.addAll(statements, .statement);
    final row = children.finish(.switchStatementMember);
    _fields.addTriple(pattern ?? _nil, labelsCount, statementsCount);
    return row;
  }

  int thisExpression({required int start, required int end}) =>
      _leaf(.thisExpression, start, end);

  int throwExpression({required int start, required int expression}) {
    final end = this.end(expression);
    return _appendOne(.throwExpression, start, end, expression, .expression);
  }

  int topLevelFunctionDeclaration({
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
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.topLevelFunctionDeclaration);
    final fieldOffset = _fields.reserve(7);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = returnType ?? _nil;
    _fields.cells[fieldOffset + 2] = name;
    _fields.cells[fieldOffset + 3] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 4] = parameters;
    _fields.cells[fieldOffset + 5] = body;
    _fields.cells[fieldOffset + 6] = metadataCount;
    return row;
  }

  int topLevelGetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(body, .functionBody);
    final row = children.finish(.topLevelGetterDeclaration);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = returnType ?? _nil;
    _fields.cells[fieldOffset + 2] = name;
    _fields.cells[fieldOffset + 3] = body;
    _fields.cells[fieldOffset + 4] = metadataCount;
    return row;
  }

  int topLevelSetterDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int parameters,
    required int body,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(returnType, .typeAnnotation);
    children.add(name, .identifier);
    children.add(parameters, .formalParameterList);
    children.add(body, .functionBody);
    final row = children.finish(.topLevelSetterDeclaration);
    final fieldOffset = _fields.reserve(6);
    _fields.cells[fieldOffset] = isExternal ? 1 : 0;
    _fields.cells[fieldOffset + 1] = returnType ?? _nil;
    _fields.cells[fieldOffset + 2] = name;
    _fields.cells[fieldOffset + 3] = parameters;
    _fields.cells[fieldOffset + 4] = body;
    _fields.cells[fieldOffset + 5] = metadataCount;
    return row;
  }

  int topLevelVariableDeclaration({
    required int start,
    required int end,
    bool isExternal = false,
    required int variables,
  }) {
    final row = _appendOne(
      .topLevelVariableDeclaration,
      start,
      end,
      variables,
      .variableDeclarationList,
    );
    _fields.add(isExternal ? 1 : 0);
    return row;
  }

  int tryStatement({
    required int start,
    required int end,
    required int body,
    List<int> catchClauses = const [],
    int? finallyBlock,
  }) {
    final children = _Children(this, start, end);
    children.add(body, .blockStatement);
    final catchClausesCount = children.addAll(catchClauses, .catchClause);
    children.add(finallyBlock, .blockStatement);
    final row = children.finish(.tryStatement);
    _fields.addTriple(body, finallyBlock ?? _nil, catchClausesCount);
    return row;
  }

  int typeAliasDeclaration({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeParameters,
    required int type,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(typeParameters, .typeParameterList);
    children.add(type, .typeAnnotation);
    final row = children.finish(.typeAliasDeclaration);
    final fieldOffset = _fields.reserve(4);
    _fields.cells[fieldOffset] = name;
    _fields.cells[fieldOffset + 1] = typeParameters ?? _nil;
    _fields.cells[fieldOffset + 2] = type;
    _fields.cells[fieldOffset + 3] = metadataCount;
    return row;
  }

  int typeArgumentList({
    required int start,
    required int end,
    required List<int> arguments,
  }) => _appendList(.typeArgumentList, start, end, arguments, .typeAnnotation);

  int typeInstantiationExpression({
    required int expression,
    required int typeArguments,
  }) => _cover(
    .typeInstantiationExpression,
    expression,
    .expression,
    typeArguments,
    .typeArgumentList,
  );

  int typeListClause({
    required int start,
    required int end,
    required TypeListClauseKind kind,
    required List<int> types,
  }) {
    final row = _appendList(
      .typeListClause,
      start,
      end,
      types,
      .typeAnnotation,
    );
    _fields.add(kind.index);
    return row;
  }

  int typeParameter({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? bound,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(name, .identifier);
    children.add(bound, .typeAnnotation);
    final row = children.finish(.typeParameter);
    _fields.addTriple(name, bound ?? _nil, metadataCount);
    return row;
  }

  int typeParameterList({
    required int start,
    required int end,
    required List<int> parameters,
  }) => _appendList(.typeParameterList, start, end, parameters, .typeParameter);

  int typeTestExpression({
    required int expression,
    required int type,
    bool isNegated = false,
  }) {
    final row = _cover(
      .typeTestExpression,
      expression,
      .expression,
      type,
      .typeAnnotation,
    );
    _fields.add(isNegated ? 1 : 0);
    return row;
  }

  int unaryExpression({
    required int start,
    required UnaryOperator op,
    required int operand,
  }) {
    final end = this.end(operand);
    final row = _appendOne(.unaryExpression, start, end, operand, .expression);
    _fields.add(op.index);
    return row;
  }

  int updateExpression({
    required int start,
    required int end,
    required int operand,
    required UpdateOperator op,
    required bool isPrefix,
  }) {
    final row = _appendOne(.updateExpression, start, end, operand, .expression);
    _fields.addPair(op.index, isPrefix ? 1 : 0);
    return row;
  }

  int variableDeclaration({required int name, int? initializer}) =>
      _cover(.variableDeclaration, name, .identifier, initializer, .expression);

  int variableDeclarationList({
    required int start,
    required int end,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    bool isLate = false,
    int? type,
    required List<int> declarations,
  }) {
    final children = _Children(this, start, end);
    final metadataCount = children.addAll(metadata, .annotation);
    children.add(type, .typeAnnotation);
    final declarationsCount = children.addAll(
      declarations,
      .variableDeclaration,
    );
    final row = children.finish(.variableDeclarationList);
    final fieldOffset = _fields.reserve(5);
    _fields.cells[fieldOffset] = keyword.index;
    _fields.cells[fieldOffset + 1] = isLate ? 1 : 0;
    _fields.cells[fieldOffset + 2] = type ?? _nil;
    _fields.cells[fieldOffset + 3] = metadataCount;
    _fields.cells[fieldOffset + 4] = declarationsCount;
    return row;
  }

  int variableDeclarationStatement({required int end, required int variables}) {
    final start = this.start(variables);
    return _appendOne(
      .variableDeclarationStatement,
      start,
      end,
      variables,
      .variableDeclarationList,
    );
  }

  int variablePattern({
    required int start,
    PatternVariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    final end = this.end(name);
    final row = _appendOptional(
      .variablePattern,
      start,
      end,
      type,
      .typeAnnotation,
      name,
      .identifier,
    );
    _fields.add(keyword.index);
    return row;
  }

  int whileStatement({
    required int start,
    required int condition,
    required int body,
  }) {
    final end = this.end(body);
    return _appendTwo(
      .whileStatement,
      start,
      end,
      condition,
      .expression,
      body,
      .statement,
    );
  }

  int wildcardPattern({
    required int start,
    required int end,
    PatternVariableKeyword keyword = .none,
    int? type,
  }) {
    final row = _appendOptional(
      .wildcardPattern,
      start,
      end,
      type,
      .typeAnnotation,
    );
    _fields.add(keyword.index);
    return row;
  }

  int yieldStatement({
    required int start,
    required int end,
    bool isStar = false,
    required int expression,
  }) {
    final row = _appendOne(
      .yieldStatement,
      start,
      end,
      expression,
      .expression,
    );
    _fields.add(isStar ? 1 : 0);
    return row;
  }

  SyntaxKind _kindAt(int id) => SyntaxKind.values[_tags[id]];
}

enum _ChildType {
  annotation.exact(SyntaxKind.annotation),
  argument.exact(SyntaxKind.argument),
  argumentList.exact(SyntaxKind.argumentList),
  blockStatement.exact(SyntaxKind.blockStatement),
  casePattern.family(_isCasePattern),
  catchClause.exact(SyntaxKind.catchClause),
  classMember.family(_isClassMember),
  collectionElement.family(_isCollectionElement),
  compilationUnitMember.family(_isCompilationUnitMember),
  conditionalUri.exact(SyntaxKind.conditionalUri),
  constructorBody.family(_isConstructorBody),
  constructorInitializer.family(_isConstructorInitializer),
  dartPattern.family(_isDartPattern),
  dottedName.exact(SyntaxKind.dottedName),
  enumConstantDeclaration.exact(SyntaxKind.enumConstantDeclaration),
  expression.family(_isExpression),
  extendsClause.exact(SyntaxKind.extendsClause),
  forInTarget.family(_isForInTarget),
  forInitializer.family(_isForInitializer),
  forLoopParts.family(_isForLoopParts),
  formalParameter.exact(SyntaxKind.formalParameter),
  formalParameterList.exact(SyntaxKind.formalParameterList),
  functionBody.family(_isFunctionBody),
  functionParameterSuffix.exact(SyntaxKind.functionParameterSuffix),
  functionTypeParameter.exact(SyntaxKind.functionTypeParameter),
  functionTypeParameterList.exact(SyntaxKind.functionTypeParameterList),
  identifier.exact(SyntaxKind.identifier),
  label.exact(SyntaxKind.label),
  listPatternElement.family(_isListPatternElement),
  mapPatternElement.family(_isMapPatternElement),
  namedRecordTypeField.exact(SyntaxKind.namedRecordTypeField),
  namedTypeAnnotation.exact(SyntaxKind.namedTypeAnnotation),
  namespaceCombinator.exact(SyntaxKind.namespaceCombinator),
  parameterDefault.exact(SyntaxKind.parameterDefault),
  partOfTarget.family(_isPartOfTarget),
  patternField.family(_isPatternField),
  patternVariableDeclaration.exact(SyntaxKind.patternVariableDeclaration),
  positionalRecordTypeField.exact(SyntaxKind.positionalRecordTypeField),
  recordField.family(_isRecordField),
  recordTypeNamedFields.exact(SyntaxKind.recordTypeNamedFields),
  scriptTag.exact(SyntaxKind.scriptTag),
  statement.family(_isStatement),
  stringExpression.family(_isStringExpression),
  stringPart.family(_isStringPart),
  switchExpressionCase.exact(SyntaxKind.switchExpressionCase),
  switchStatementMember.exact(SyntaxKind.switchStatementMember),
  typeAnnotation.family(_isTypeAnnotation),
  typeArgumentList.exact(SyntaxKind.typeArgumentList),
  typeListClause.exact(SyntaxKind.typeListClause),
  typeParameter.exact(SyntaxKind.typeParameter),
  typeParameterList.exact(SyntaxKind.typeParameterList),
  variableDeclaration.exact(SyntaxKind.variableDeclaration),
  variableDeclarationList.exact(SyntaxKind.variableDeclarationList);

  const _ChildType.exact(this.kind) : roles = 0;
  const _ChildType.family(this.roles) : kind = null;
  final SyntaxKind? kind;
  final int roles;

  bool accepts(int tag) {
    final exact = kind;
    return exact == null
        ? SyntaxKind.values[tag]._roles & roles != 0
        : tag == exact.index;
  }
}
