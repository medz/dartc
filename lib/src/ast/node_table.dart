part of 'nodes.dart';

// shortcut: rows use 32-bit indices, widen the columns for larger inputs.
const _nil = 0xffffffff;

final class _Words(int cap) {
  Uint32List cells = Uint32List(cap > _nil ? _nil : cap);
  int used = 0;
  int reserve(int n) {
    final start = used;
    final end = start + n;
    if (end > cells.length) _grow(end);
    used = end;
    return start;
  }

  void _grow(int end) {
    if (end > _nil) throw RangeError('Syntax payload exceeds 32-bit indices');
    final size = (cells.length * 2 + 16).clamp(end, _nil);
    cells = Uint32List(size)..setRange(0, used, cells);
  }

  void add(int value) {
    final p = reserve(1);
    cells[p] = value;
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
  final edges = _Words(capacity),
      fields = _Words(tokenCount),
      extra = _Words(tokenCount >> 3);
  void grow() {
    final n = count * 2 + 16;
    tags = Uint8List(n)..setRange(0, count, tags);
    starts = Uint32List(n)..setRange(0, count, starts);
    ends = Uint32List(n)..setRange(0, count, ends);
    offsets = Uint32List(n)..setRange(0, count, offsets);
    edgeOffsets = Uint32List(n + 1)..setRange(0, count + 1, edgeOffsets);
  }

  void _checkRange(int start, int end) {
    RangeError.checkValidRange(start, end, source.length);
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
    RangeError.checkValidIndex(id, this, 'child', count);
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

  int childIndex(int row, int index) => edges.cells[edgeOffsets[row] + index];
  int trailingChild(int row, int fromEnd) =>
      edges.cells[edgeOffsets[row + 1] - fromEnd];
  int? optionalChild(int row, int index, int fullCount) =>
      edgeOffsets[row + 1] - edgeOffsets[row] == fullCount
      ? childIndex(row, index)
      : null;

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

  int _appendEdges(
    SyntaxKind kind,
    int start,
    int end,
    int length,
    int Function(int) child,
  ) {
    _checkRange(start, end);
    final base = edges.used;
    try {
      edges.reserve(length);
      var previous = start;
      for (var i = 0; i < length; i++) {
        final id = child(i);
        previous = _checkEdge(id, previous, end);
        edges.cells[base + i] = id;
      }
    } catch (_) {
      edges.used = base;
      rethrow;
    }
    return _finishRow(kind, start, end);
  }

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
    final arity =
        name.length +
        (typeArguments == null ? 0 : 1) +
        (constructorName == null ? 0 : 1) +
        (arguments == null ? 0 : 1);
    int child(int ix) {
      if (ix < name.length) return name[ix];
      ix -= name.length;
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      if (constructorName != null) {
        if (ix == 0) return constructorName;
        ix--;
      }
      return arguments!;
    }

    final row = _appendEdges(.annotation, start, end, arity, child);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    fields.cells[fieldOffset + 3] = rawRefs(name);
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
    final arity = 1 + sections.length;
    int child(int ix) {
      return ix == 0 ? target : sections[ix - 1];
    }

    final row = _appendEdges(.cascadeExpression, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRefs(sections);
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
    final arity =
        (exceptionType == null ? 0 : 1) +
        (exceptionParameter == null ? 0 : 1) +
        (stackTraceParameter == null ? 0 : 1) +
        1;
    int child(int ix) {
      if (exceptionType != null) {
        if (ix == 0) return exceptionType;
        ix--;
      }
      if (exceptionParameter != null) {
        if (ix == 0) return exceptionParameter;
        ix--;
      }
      if (stackTraceParameter != null) {
        if (ix == 0) return stackTraceParameter;
        ix--;
      }
      return body;
    }

    final row = _appendEdges(.catchClause, start, end, arity, child);
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
    final arity =
        metadata.length +
        1 +
        (typeParameters == null ? 0 : 1) +
        (primaryConstructorName == null ? 0 : 1) +
        (primaryParameters == null ? 0 : 1) +
        (extendsClause == null ? 0 : 1) +
        (withClause == null ? 0 : 1) +
        (implementsClause == null ? 0 : 1) +
        members.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      if (primaryConstructorName != null) {
        if (ix == 0) return primaryConstructorName;
        ix--;
      }
      if (primaryParameters != null) {
        if (ix == 0) return primaryParameters;
        ix--;
      }
      if (extendsClause != null) {
        if (ix == 0) return extendsClause;
        ix--;
      }
      if (withClause != null) {
        if (ix == 0) return withClause;
        ix--;
      }
      if (implementsClause != null) {
        if (ix == 0) return implementsClause;
        ix--;
      }
      return members[ix];
    }

    final row = _appendEdges(.classDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(12);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = isConst == true
        ? 1
        : isConst == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(extendsClause);
    fields.cells[fieldOffset + 6] = rawRef(withClause);
    fields.cells[fieldOffset + 7] = rawRef(implementsClause);
    fields.cells[fieldOffset + 8] = isSemicolonBody == true
        ? 1
        : isSemicolonBody == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 9] = rawRefs(metadata);
    fields.cells[fieldOffset + 10] = rawRefs(modifiers);
    fields.cells[fieldOffset + 11] = rawRefs(members);
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
    final arity =
        metadata.length +
        3 +
        (typeParameters == null ? 0 : 1) +
        (implementsClause == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      if (ix == 0) return superclass;
      return ix == 1 ? withClause : implementsClause!;
    }

    final row = _appendEdges(
      .classTypeAliasDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(7);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(superclass);
    fields.cells[fieldOffset + 3] = rawRef(withClause);
    fields.cells[fieldOffset + 4] = rawRef(implementsClause);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
    fields.cells[fieldOffset + 6] = rawRefs(modifiers);
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
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    final row = _appendEdges(.collectionExpression, start, end, arity, child);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = hasConstKeyword == true
        ? 1
        : hasConstKeyword == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(typeArguments);
    fields.cells[fieldOffset + 3] = rawRefs(elements);
    return row;
  }

  int putCompilationUnit({int? scriptTag, required List<int> members}) {
    final start = 0;
    final end = source.length;
    final arity = (scriptTag == null ? 0 : 1) + members.length;
    int child(int ix) {
      if (scriptTag != null) {
        if (ix == 0) return scriptTag;
        ix--;
      }
      return members[ix];
    }

    final row = _appendEdges(.compilationUnit, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(scriptTag);
    fields.cells[fieldOffset + 1] = rawRefs(members);
    return row;
  }

  int putConditionalExpression({
    required int start,
    required int end,
    required int condition,
    required int thenExpression,
    required int elseExpression,
  }) {
    final arity = 3;
    int child(int ix) => switch (ix) {
      0 => condition,
      1 => thenExpression,
      2 => elseExpression,
      _ => (throw RangeError.value(ix)),
    };
    return _appendEdges(.conditionalExpression, start, end, arity, child);
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
    final arity =
        1 + (typeArguments == null ? 0 : 1) + (arguments == null ? 0 : 1);
    int child(int ix) => switch (ix) {
      0 => name,
      1 when typeArguments != null || arguments != null =>
        typeArguments ?? arguments!,
      2 when typeArguments != null && arguments != null => arguments,
      _ => (throw RangeError.value(ix)),
    };
    final row = _appendEdges(
      .constDotShorthandExpression,
      start,
      end,
      arity,
      child,
    );
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
    fields.cells[fieldOffset + 0] = hasConstKeyword == true
        ? 1
        : hasConstKeyword == false
        ? 0
        : _nil;
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
    final arity = metadata.length + name.length + initializers.length + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix < name.length) return name[ix];
      ix -= name.length;
      if (ix == 0) return parameters;
      ix--;
      return ix < initializers.length ? initializers[ix] : body;
    }

    final row = _appendEdges(.constructorDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isConst == true
        ? 1
        : isConst == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = keyword.index;
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
    fields.cells[fieldOffset + 6] = rawRefs(name);
    fields.cells[fieldOffset + 7] = rawRefs(initializers);
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
    final arity = metadata.length + (type == null ? 0 : 1) + 1;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      return type != null && ix == 0 ? type : name;
    }

    final row = _appendEdges(.declaredIdentifier, start, end, arity, child);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
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
    final arity =
        metadata.length +
        1 +
        (typeArguments == null ? 0 : 1) +
        (constructorName == null ? 0 : 1) +
        (arguments == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      if (constructorName != null) {
        if (ix == 0) return constructorName;
        ix--;
      }
      return arguments!;
    }

    final row = _appendEdges(
      .enumConstantDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
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
    final arity =
        metadata.length +
        1 +
        (typeParameters == null ? 0 : 1) +
        (primaryConstructorName == null ? 0 : 1) +
        (primaryParameters == null ? 0 : 1) +
        (withClause == null ? 0 : 1) +
        (implementsClause == null ? 0 : 1) +
        constants.length +
        members.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      if (primaryConstructorName != null) {
        if (ix == 0) return primaryConstructorName;
        ix--;
      }
      if (primaryParameters != null) {
        if (ix == 0) return primaryParameters;
        ix--;
      }
      if (withClause != null) {
        if (ix == 0) return withClause;
        ix--;
      }
      if (implementsClause != null) {
        if (ix == 0) return implementsClause;
        ix--;
      }
      if (ix < constants.length) return constants[ix];
      return members[ix - constants.length];
    }

    final row = _appendEdges(.enumDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(12);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = isConst == true
        ? 1
        : isConst == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(withClause);
    fields.cells[fieldOffset + 6] = rawRef(implementsClause);
    fields.cells[fieldOffset + 7] = isSemicolonBody == true
        ? 1
        : isSemicolonBody == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 8] = hasMemberSeparator == true
        ? 1
        : hasMemberSeparator == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 9] = rawRefs(metadata);
    fields.cells[fieldOffset + 10] = rawRefs(constants);
    fields.cells[fieldOffset + 11] = rawRefs(members);
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
    final arity =
        metadata.length + 1 + configurations.length + combinators.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return uri;
      ix--;
      if (ix < configurations.length) return configurations[ix];
      return combinators[ix - configurations.length];
    }

    final row = _appendEdges(.exportDirective, start, end, arity, child);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = rawRefs(configurations);
    fields.cells[fieldOffset + 2] = rawRefs(combinators);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isAsync == true
        ? 1
        : isAsync == false
        ? 0
        : _nil;
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
    final arity =
        metadata.length +
        (name == null ? 0 : 1) +
        (typeParameters == null ? 0 : 1) +
        1 +
        members.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (name != null) {
        if (ix == 0) return name;
        ix--;
      }
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return ix == 0 ? onType : members[ix - 1];
    }

    final row = _appendEdges(.extensionDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(onType);
    fields.cells[fieldOffset + 3] = isSemicolonBody == true
        ? 1
        : isSemicolonBody == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
    fields.cells[fieldOffset + 5] = rawRefs(members);
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
    final arity =
        metadata.length +
        2 +
        (typeParameters == null ? 0 : 1) +
        (primaryConstructorName == null ? 0 : 1) +
        (implementsClause == null ? 0 : 1) +
        members.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      if (primaryConstructorName != null) {
        if (ix == 0) return primaryConstructorName;
        ix--;
      }
      if (ix == 0) return primaryParameters;
      ix--;
      if (implementsClause != null) {
        if (ix == 0) return implementsClause;
        ix--;
      }
      return members[ix];
    }

    final row = _appendEdges(
      .extensionTypeDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(9);
    fields.cells[fieldOffset + 0] = isConst == true
        ? 1
        : isConst == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(primaryConstructorName);
    fields.cells[fieldOffset + 4] = rawRef(primaryParameters);
    fields.cells[fieldOffset + 5] = rawRef(implementsClause);
    fields.cells[fieldOffset + 6] = isSemicolonBody == true
        ? 1
        : isSemicolonBody == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 7] = rawRefs(metadata);
    fields.cells[fieldOffset + 8] = rawRefs(members);
    return row;
  }

  int putFactoryRedirectBody({
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
  }) {
    final arity =
        name.length +
        (typeArguments == null ? 0 : 1) +
        (constructorName == null ? 0 : 1);
    int child(int ix) {
      if (ix < name.length) return name[ix];
      ix -= name.length;
      return typeArguments != null && ix == 0
          ? typeArguments
          : constructorName!;
    }

    final row = _appendEdges(.factoryRedirectBody, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = rawRefs(name);
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
    fields.cells[fieldOffset + 0] = isStatic == true
        ? 1
        : isStatic == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isAbstract == true
        ? 1
        : isAbstract == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 3] = isCovariant == true
        ? 1
        : isCovariant == false
        ? 0
        : _nil;
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
    fields.cells[fieldOffset + 0] = hasThis == true
        ? 1
        : hasThis == false
        ? 0
        : _nil;
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
    fields.cells[fieldOffset + 0] = isAwait == true
        ? 1
        : isAwait == false
        ? 0
        : _nil;
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
    final arity =
        (initializer == null ? 0 : 1) +
        (condition == null ? 0 : 1) +
        updaters.length;
    int child(int ix) {
      if (initializer != null) {
        if (ix == 0) return initializer;
        ix--;
      }
      if (condition != null) {
        if (ix == 0) return condition;
        ix--;
      }
      return updaters[ix];
    }

    final row = _appendEdges(.forParts, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(initializer);
    fields.cells[fieldOffset + 1] = rawRef(condition);
    fields.cells[fieldOffset + 2] = rawRefs(updaters);
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
    fields.cells[fieldOffset + 0] = isAwait == true
        ? 1
        : isAwait == false
        ? 0
        : _nil;
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
    final arity =
        metadata.length +
        (type == null ? 0 : 1) +
        1 +
        (functionSuffix == null ? 0 : 1) +
        (defaultClause == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (type != null) {
        if (ix == 0) return type;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      if (functionSuffix != null) {
        if (ix == 0) return functionSuffix;
        ix--;
      }
      return defaultClause!;
    }

    final row = _appendEdges(.formalParameter, start, end, arity, child);
    final fieldOffset = fields.reserve(9);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = prefix.index;
    fields.cells[fieldOffset + 2] = keyword.index;
    fields.cells[fieldOffset + 3] = isCovariant == true
        ? 1
        : isCovariant == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 4] = rawRef(type);
    fields.cells[fieldOffset + 5] = rawRef(name);
    fields.cells[fieldOffset + 6] = rawRef(functionSuffix);
    fields.cells[fieldOffset + 7] = rawRef(defaultClause);
    fields.cells[fieldOffset + 8] = rawRefs(metadata);
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
    final arity =
        metadata.length +
        (returnType == null ? 0 : 1) +
        (typeParameters == null ? 0 : 1) +
        2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      return typeParameters != null && ix == 0 ? typeParameters : parameters;
    }

    final row = _appendEdges(
      .functionTypeAliasDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
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
    final arity =
        (returnType == null ? 0 : 1) + (typeParameters == null ? 0 : 1) + 1;
    int child(int ix) {
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return parameters;
    }

    final row = _appendEdges(.functionTypeAnnotation, start, end, arity, child);
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
    final arity = metadata.length + 1 + (name == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name!;
    }

    final row = _appendEdges(.functionTypeParameter, start, end, arity, child);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = isCovariant == true
        ? 1
        : isCovariant == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
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
    final arity = metadata.length + (returnType == null ? 0 : 1) + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      return body;
    }

    final row = _appendEdges(.getterDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isStatic == true
        ? 1
        : isStatic == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
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
    final arity =
        2 + (casePattern == null ? 0 : 1) + (elseElement == null ? 0 : 1);
    int child(int ix) {
      if (ix == 0) return condition;
      ix--;
      if (casePattern != null) {
        if (ix == 0) return casePattern;
        ix--;
      }
      return ix == 0 ? thenElement : elseElement!;
    }

    final row = _appendEdges(.ifElement, start, end, arity, child);
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
    final arity =
        2 + (casePattern == null ? 0 : 1) + (elseStatement == null ? 0 : 1);
    int child(int ix) {
      if (ix == 0) return condition;
      ix--;
      if (casePattern != null) {
        if (ix == 0) return casePattern;
        ix--;
      }
      return ix == 0 ? thenStatement : elseStatement!;
    }

    final row = _appendEdges(.ifStatement, start, end, arity, child);
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
    final arity =
        metadata.length +
        1 +
        configurations.length +
        (prefix == null ? 0 : 1) +
        combinators.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return uri;
      ix--;
      if (ix < configurations.length) return configurations[ix];
      ix -= configurations.length;
      if (prefix != null) {
        if (ix == 0) return prefix;
        ix--;
      }
      return combinators[ix];
    }

    final row = _appendEdges(.importDirective, start, end, arity, child);
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = isDeferred == true
        ? 1
        : isDeferred == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(prefix);
    fields.cells[fieldOffset + 3] = rawRefs(configurations);
    fields.cells[fieldOffset + 4] = rawRefs(combinators);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
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
    final arity =
        name.length +
        (typeArguments == null ? 0 : 1) +
        (constructorName == null ? 0 : 1) +
        1;
    int child(int ix) {
      if (ix < name.length) return name[ix];
      ix -= name.length;
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      if (constructorName != null && ix == 0) return constructorName;
      return arguments;
    }

    final row = _appendEdges(
      .instanceCreationExpression,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = rawRefs(name);
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
    final arity = labels.length + 1;
    int child(int ix) {
      return ix < labels.length ? labels[ix] : statement;
    }

    final row = _appendEdges(.labeledStatement, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(statement);
    fields.cells[fieldOffset + 1] = rawRefs(labels);
    return row;
  }

  int putLibraryDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
  }) {
    final arity = metadata.length + (name == null ? 0 : 1);
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : name!;
    }

    final row = _appendEdges(.libraryDirective, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    return row;
  }

  int putListPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    final row = _appendEdges(.listPattern, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRefs(elements);
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
    final arity =
        metadata.length +
        (returnType == null ? 0 : 1) +
        (typeParameters == null ? 0 : 1) +
        3;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(
      .localFunctionDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isNullAwareKey == true
        ? 1
        : isNullAwareKey == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isNullAwareValue == true
        ? 1
        : isNullAwareValue == false
        ? 0
        : _nil;
    return row;
  }

  int putMapPattern({
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    final row = _appendEdges(.mapPattern, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRefs(elements);
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
    final arity =
        metadata.length +
        (returnType == null ? 0 : 1) +
        (typeParameters == null ? 0 : 1) +
        3;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(.methodDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isStatic == true
        ? 1
        : isStatic == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = rawRef(name);
    fields.cells[fieldOffset + 4] = rawRef(typeParameters);
    fields.cells[fieldOffset + 5] = rawRef(parameters);
    fields.cells[fieldOffset + 6] = rawRef(body);
    fields.cells[fieldOffset + 7] = rawRefs(metadata);
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
    final arity =
        metadata.length +
        1 +
        (typeParameters == null ? 0 : 1) +
        (onClause == null ? 0 : 1) +
        (implementsClause == null ? 0 : 1) +
        members.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      if (onClause != null) {
        if (ix == 0) return onClause;
        ix--;
      }
      if (implementsClause != null) {
        if (ix == 0) return implementsClause;
        ix--;
      }
      return members[ix];
    }

    final row = _appendEdges(.mixinDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isBase == true
        ? 1
        : isBase == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(onClause);
    fields.cells[fieldOffset + 4] = rawRef(implementsClause);
    fields.cells[fieldOffset + 5] = isSemicolonBody == true
        ? 1
        : isSemicolonBody == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 6] = rawRefs(metadata);
    fields.cells[fieldOffset + 7] = rawRefs(members);
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
    final arity = metadata.length + 1 + (1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name;
    }

    final row = _appendEdges(.namedRecordTypeField, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
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
    final arity = 1 + fields.length;
    int child(int ix) {
      return ix == 0 ? type : fields[ix - 1];
    }

    final row = _appendEdges(.objectPattern, start, end, arity, child);
    final fieldOffset = this.fields.reserve(2);
    this.fields.cells[fieldOffset + 0] = rawRef(type);
    this.fields.cells[fieldOffset + 1] = rawRefs(fields);
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
    final arity = metadata.length + (returnType == null ? 0 : 1) + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(.operatorDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(7);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isStatic == true
        ? 1
        : isStatic == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(returnType);
    fields.cells[fieldOffset + 3] = op.index;
    fields.cells[fieldOffset + 4] = rawRef(parameters);
    fields.cells[fieldOffset + 5] = rawRef(body);
    fields.cells[fieldOffset + 6] = rawRefs(metadata);
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
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : uri;
    }

    final row = _appendEdges(.partDirective, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    return row;
  }

  int putPartOfDirective({
    required int start,
    required int end,
    List<int> metadata = const [],
    required int target,
  }) {
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : target;
    }

    final row = _appendEdges(.partOfDirective, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
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
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : pattern;
    }

    final row = _appendEdges(.patternForInBinding, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = isFinal == true
        ? 1
        : isFinal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(pattern);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
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
    final arity = metadata.length + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? pattern : initializer;
    }

    final row = _appendEdges(
      .patternVariableDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = isFinal == true
        ? 1
        : isFinal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(pattern);
    fields.cells[fieldOffset + 2] = rawRef(initializer);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
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
    final arity = metadata.length + 1 + (name == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name!;
    }

    final row = _appendEdges(
      .positionalRecordTypeField,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
    return row;
  }

  int putPrimaryConstructorBody({
    required int start,
    required int end,
    List<int> metadata = const [],
    List<int> initializers = const [],
    required int body,
  }) {
    final arity = metadata.length + initializers.length + 1;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      return ix < initializers.length ? initializers[ix] : body;
    }

    final row = _appendEdges(.primaryConstructorBody, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    fields.cells[fieldOffset + 2] = rawRefs(initializers);
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
    fields.cells[fieldOffset + 0] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
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
    this.fields.cells[fieldOffset + 0] = hasConstKeyword == true
        ? 1
        : hasConstKeyword == false
        ? 0
        : _nil;
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
    final arity = positionalFields.length + (namedFields == null ? 0 : 1);
    int child(int ix) {
      return ix < positionalFields.length ? positionalFields[ix] : namedFields!;
    }

    final row = _appendEdges(.recordTypeAnnotation, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(namedFields);
    fields.cells[fieldOffset + 1] = rawRefs(positionalFields);
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
    final arity = metadata.length + (returnType == null ? 0 : 1) + 3;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(.setterDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(8);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = isStatic == true
        ? 1
        : isStatic == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = isCovariant == true
        ? 1
        : isCovariant == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 3] = rawRef(returnType);
    fields.cells[fieldOffset + 4] = rawRef(name);
    fields.cells[fieldOffset + 5] = rawRef(parameters);
    fields.cells[fieldOffset + 6] = rawRef(body);
    fields.cells[fieldOffset + 7] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
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
    fields.cells[fieldOffset + 0] = isBraced == true
        ? 1
        : isBraced == false
        ? 0
        : _nil;
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
    final arity = 1 + cases.length;
    int child(int ix) {
      return ix == 0 ? expression : cases[ix - 1];
    }

    final row = _appendEdges(.switchExpression, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRefs(cases);
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
    final arity = 1 + members.length;
    int child(int ix) {
      return ix == 0 ? expression : members[ix - 1];
    }

    final row = _appendEdges(.switchStatement, start, end, arity, child);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRefs(members);
    return row;
  }

  int putSwitchStatementMember({
    required int start,
    required int end,
    List<int> labels = const [],
    int? pattern,
    required List<int> statements,
  }) {
    final arity = labels.length + (pattern == null ? 0 : 1) + statements.length;
    int child(int ix) {
      if (ix < labels.length) return labels[ix];
      ix -= labels.length;
      if (pattern != null) {
        if (ix == 0) return pattern;
        ix--;
      }
      return statements[ix];
    }

    final row = _appendEdges(.switchStatementMember, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRefs(labels);
    fields.cells[fieldOffset + 2] = rawRefs(statements);
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
    final arity =
        metadata.length +
        (returnType == null ? 0 : 1) +
        (typeParameters == null ? 0 : 1) +
        3;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(
      .topLevelFunctionDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(7);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(typeParameters);
    fields.cells[fieldOffset + 4] = rawRef(parameters);
    fields.cells[fieldOffset + 5] = rawRef(body);
    fields.cells[fieldOffset + 6] = rawRefs(metadata);
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
    final arity = metadata.length + (returnType == null ? 0 : 1) + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      return body;
    }

    final row = _appendEdges(
      .topLevelGetterDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(body);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
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
    final arity = metadata.length + (returnType == null ? 0 : 1) + 3;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (returnType != null) {
        if (ix == 0) return returnType;
        ix--;
      }
      if (ix == 0) return name;
      ix--;
      return ix == 0 ? parameters : body;
    }

    final row = _appendEdges(
      .topLevelSetterDeclaration,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(6);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(returnType);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRef(body);
    fields.cells[fieldOffset + 5] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    return row;
  }

  int putTryStatement({
    required int start,
    required int end,
    required int body,
    List<int> catchClauses = const [],
    int? finallyBlock,
  }) {
    final arity = 1 + catchClauses.length + (finallyBlock == null ? 0 : 1);
    int child(int ix) {
      if (ix == 0) return body;
      ix--;
      return ix < catchClauses.length ? catchClauses[ix] : finallyBlock!;
    }

    final row = _appendEdges(.tryStatement, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRef(finallyBlock);
    fields.cells[fieldOffset + 2] = rawRefs(catchClauses);
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
    final arity = metadata.length + 2 + (typeParameters == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      return typeParameters != null && ix == 0 ? typeParameters : type;
    }

    final row = _appendEdges(.typeAliasDeclaration, start, end, arity, child);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
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
    final arity = metadata.length + 1 + (bound == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? name : bound!;
    }

    final row = _appendEdges(.typeParameter, start, end, arity, child);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(bound);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
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
    fields.cells[fieldOffset + 0] = isNegated == true
        ? 1
        : isNegated == false
        ? 0
        : _nil;
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
    fields.cells[fieldOffset + 1] = isPrefix == true
        ? 1
        : isPrefix == false
        ? 0
        : _nil;
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
    final arity =
        metadata.length + (type == null ? 0 : 1) + declarations.length;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (type != null) {
        if (ix == 0) return type;
        ix--;
      }
      return declarations[ix];
    }

    final row = _appendEdges(
      .variableDeclarationList,
      start,
      end,
      arity,
      child,
    );
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = isLate == true
        ? 1
        : isLate == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
    fields.cells[fieldOffset + 4] = rawRefs(declarations);
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
    fields.cells[fieldOffset + 0] = isStar == true
        ? 1
        : isStar == false
        ? 0
        : _nil;
    return row;
  }

  int rawRef(int? id) {
    if (id == null) return _nil;
    RangeError.checkValidIndex(id, this, 'node', count);
    return id;
  }

  int rawRefs(List<Object?> list) {
    if (list.isEmpty) return _nil;
    final p = extra.reserve(list.length + 1);
    extra.cells[p] = list.length;
    for (var i = 0; i < list.length; i++) {
      final v = list[i];
      extra.cells[p + 1 + i] = v is Enum ? v.index : rawRef(v as int);
    }
    return p;
  }

  List<int> refList(int off) {
    if (off == _nil) return const [];
    return Uint32List.sublistView(
      extra.cells,
      off + 1,
      off + 1 + extra.cells[off],
    );
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
