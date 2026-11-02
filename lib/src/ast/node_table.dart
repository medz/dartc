part of 'nodes.dart';

// shortcut: rows use 32-bit indices, widen the columns for larger inputs.
const _nil = 0xffffffff;

final class _Words(int cap) {
  Uint32List cells = Uint32List(cap);
  int used = 0;
  int reserve(int n) {
    final p = used;
    if (n > _nil - p) throw RangeError('Syntax payload exceeds 32-bit indices');
    used += n;
    if (used > cells.length) {
      var size = cells.length * 2 + 16;
      if (size < used) size = used;
      cells = Uint32List(size)..setRange(0, p, cells);
    }
    return p;
  }

  void add(int value) {
    final p = reserve(1);
    cells[p] = value;
  }
}

final class AstArena(final SourceFile source, int capacity) {
  static (AstArena, int) locate(AstNode node) {
    final row = node as _Row;
    return (row._owner, row._row);
  }

  SyntaxTree finish(int root) => SyntaxTree._(this, rawRef(root));

  int count = 0;
  Uint8List tags = Uint8List(capacity);
  Uint32List starts = Uint32List(capacity),
      ends = Uint32List(capacity),
      edgeOffsets = Uint32List(capacity + 1),
      offsets = Uint32List(capacity);
  final edges = _Words(capacity),
      fields = _Words(capacity * 2),
      extra = _Words(capacity);
  void grow() {
    final n = count * 2 + 16;
    tags = Uint8List(n)..setRange(0, count, tags);
    starts = Uint32List(n)..setRange(0, count, starts);
    ends = Uint32List(n)..setRange(0, count, ends);
    offsets = Uint32List(n)..setRange(0, count, offsets);
    edgeOffsets = Uint32List(n + 1)..setRange(0, count + 1, edgeOffsets);
  }

  int ref(AstNode? n) {
    if (n == null) return _nil;
    if (n is! _Row || !identical(n._owner, this)) {
      throw StateError('Foreign or unrecorded ${n.runtimeType}');
    }
    return n._row;
  }

  int refs(List<Object?> values) {
    if (values.isEmpty) return _nil;
    final off = extra.reserve(values.length + 1);
    extra.cells[off] = values.length;
    for (var i = 0; i < values.length; i++) {
      final x = values[i];
      extra.cells[off + 1 + i] = x is Enum ? x.index : ref(x as AstNode);
    }
    return off;
  }

  int _appendRow(int tag, int start, int end) {
    if (end >= _nil || count == _nil) {
      throw RangeError('Syntax range or node index exceeds 32 bits');
    }
    if (count == tags.length) grow();
    final row = count++;
    tags[row] = tag;
    starts[row] = start;
    ends[row] = end;
    edgeOffsets[row + 1] = edges.used;
    offsets[row] = fields.used;
    return row;
  }

  void _appendEdges(int start, int end, int length, int Function(int) child) {
    final base = edges.used;
    try {
      edges.reserve(length);
      var previous = start;
      for (var i = 0; i < length; i++) {
        final id = child(i);
        RangeError.checkValidIndex(id, this, 'child', count);
        if (starts[id] < previous || ends[id] > end) {
          throw ArgumentError('Child outside range');
        }
        previous = ends[id];
        edges.cells[base + i] = id;
      }
    } catch (_) {
      edges.used = base;
      rethrow;
    }
  }

  int putAdjacentStringsExpression({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> strings,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = strings.length;
    int child(int ix) => strings[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(0, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(strings);
    return row;
  }

  int putAnnotation({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(1, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    fields.cells[fieldOffset + 3] = rawRefs(name);
    return row;
  }

  int putArgument({
    required SourceFile source,
    required int start,
    required int end,
    int? name,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = name == null ? 1 : 2;
    int child(int ix) {
      return name != null && ix == 0 ? name : value;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(2, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putArgumentList({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = arguments.length;
    int child(int ix) => arguments[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(3, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(arguments);
    return row;
  }

  int putAssertInitializer({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    int? message,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = message == null ? 1 : 2;
    int child(int ix) => switch (ix) {
      0 => condition,
      1 when message != null => message,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(4, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(message);
    return row;
  }

  int putAssertStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    int? message,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = message == null ? 1 : 2;
    int child(int ix) => switch (ix) {
      0 => condition,
      1 when message != null => message,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(5, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(message);
    return row;
  }

  int putAssignmentExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int left,
    required AssignmentOperator op,
    required int right,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => left,
      1 => right,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(6, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(left);
    fields.cells[fieldOffset + 1] = op.index;
    fields.cells[fieldOffset + 2] = rawRef(right);
    return row;
  }

  int putAwaitExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(7, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putBinaryExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int left,
    required BinaryOperator op,
    required int right,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => left,
      1 => right,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(8, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(left);
    fields.cells[fieldOffset + 1] = op.index;
    fields.cells[fieldOffset + 2] = rawRef(right);
    return row;
  }

  int putBlockStatement({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> statements,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = statements.length;
    int child(int ix) => statements[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(9, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(statements);
    return row;
  }

  int putBreakStatement({
    required SourceFile source,
    required int start,
    required int end,
    int? label,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = label == null ? 0 : 1;
    int child(int ix) => switch (ix) {
      0 when label != null => label,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(10, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(label);
    return row;
  }

  int putCascadeExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int target,
    bool isNullAware = false,
    required List<int> sections,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1 + sections.length;
    int child(int ix) {
      return ix == 0 ? target : sections[ix - 1];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(11, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int index,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => index,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(12, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(index);
    return row;
  }

  int putCascadePropertyExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int property,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => property,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(13, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(property);
    return row;
  }

  int putCastExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required int type,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => expression,
      1 => type,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(14, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRef(type);
    return row;
  }

  int putCastPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
    required int type,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => pattern,
      1 => type,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(15, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRef(type);
    return row;
  }

  int putCatchClause({
    required SourceFile source,
    required int start,
    required int end,
    int? exceptionType,
    int? exceptionParameter,
    int? stackTraceParameter,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(16, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(exceptionType);
    fields.cells[fieldOffset + 1] = rawRef(exceptionParameter);
    fields.cells[fieldOffset + 2] = rawRef(stackTraceParameter);
    fields.cells[fieldOffset + 3] = rawRef(body);
    return row;
  }

  int putClassDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(17, start, end);
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
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(18, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required CollectionLiteralKind kind,
    bool hasConstKeyword = false,
    int? typeArguments,
    required List<int> elements,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(19, start, end);
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

  int putCompilationUnit({
    required SourceFile source,
    int? scriptTag,
    required List<int> members,
  }) {
    final start = 0;
    final end = source.length;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = (scriptTag == null ? 0 : 1) + members.length;
    int child(int ix) {
      if (scriptTag != null) {
        if (ix == 0) return scriptTag;
        ix--;
      }
      return members[ix];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(20, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(scriptTag);
    fields.cells[fieldOffset + 1] = rawRefs(members);
    return row;
  }

  int putConditionalExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    required int thenExpression,
    required int elseExpression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 3;
    int child(int ix) => switch (ix) {
      0 => condition,
      1 => thenExpression,
      2 => elseExpression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(21, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(thenExpression);
    fields.cells[fieldOffset + 2] = rawRef(elseExpression);
    return row;
  }

  int putConditionalUri({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
    int? value,
    required int uri,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = value == null ? 2 : 3;
    int child(int ix) {
      if (ix == 0) return name;
      return value != null && ix == 1 ? value : uri;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(22, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(value);
    fields.cells[fieldOffset + 2] = rawRef(uri);
    return row;
  }

  int putConstDotShorthandExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
    int? typeArguments,
    int? arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity =
        1 + (typeArguments == null ? 0 : 1) + (arguments == null ? 0 : 1);
    int child(int ix) => switch (ix) {
      0 => name,
      1 when typeArguments != null || arguments != null =>
        typeArguments ?? arguments!,
      2 when typeArguments != null && arguments != null => arguments,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(23, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    return row;
  }

  int putConstantPattern({
    required SourceFile source,
    required int start,
    required int end,
    bool hasConstKeyword = false,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(24, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = hasConstKeyword == true
        ? 1
        : hasConstKeyword == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(expression);
    return row;
  }

  int putConstructorDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(25, start, end);
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

  int putContinueStatement({
    required SourceFile source,
    required int start,
    required int end,
    int? label,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = label == null ? 0 : 1;
    int child(int ix) => switch (ix) {
      0 when label != null => label,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(26, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(label);
    return row;
  }

  int putDeclaredIdentifier({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + (type == null ? 0 : 1) + 1;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      return type != null && ix == 0 ? type : name;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(27, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRef(name);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
    return row;
  }

  int putDoStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int body,
    required int condition,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => body,
      1 => condition,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(28, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRef(condition);
    return row;
  }

  int putDotShorthandExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(29, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putDotShorthandReferenceExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => name,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(30, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(name);
    return row;
  }

  int putDottedName({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> components,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = components.length;
    int child(int ix) => components[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(31, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(components);
    return row;
  }

  int putEmptyFunctionBody({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(32, start, end);
    return row;
  }

  int putEmptyStatement({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(33, start, end);
    return row;
  }

  int putEnumConstantDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeArguments,
    int? constructorName,
    int? arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(34, start, end);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
    return row;
  }

  int putEnumDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(35, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    List<int> combinators = const [],
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(36, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = rawRefs(configurations);
    fields.cells[fieldOffset + 2] = rawRefs(combinators);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
    return row;
  }

  int putExpressionFunctionBody({
    required SourceFile source,
    required int start,
    required int end,
    bool isAsync = false,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(37, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = isAsync == true
        ? 1
        : isAsync == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(expression);
    return row;
  }

  int putExpressionStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(38, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putExtendsClause({
    required SourceFile source,
    required int start,
    required int end,
    required int superclass,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => superclass,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(39, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(superclass);
    return row;
  }

  int putExtensionDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
    int? typeParameters,
    required int onType,
    bool isSemicolonBody = false,
    List<int> members = const [],
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(40, start, end);
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
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(41, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(42, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRef(constructorName);
    fields.cells[fieldOffset + 2] = rawRefs(name);
    return row;
  }

  int putFieldDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    bool isStatic = false,
    bool isAbstract = false,
    bool isExternal = false,
    bool isCovariant = false,
    required int variables,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => variables,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(43, start, end);
    final fieldOffset = fields.reserve(5);
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
    fields.cells[fieldOffset + 4] = rawRef(variables);
    return row;
  }

  int putFieldInitializer({
    required SourceFile source,
    required int start,
    required int end,
    bool hasThis = false,
    required int name,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => name,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(44, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = hasThis == true
        ? 1
        : hasThis == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(value);
    return row;
  }

  int putForElement({
    required SourceFile source,
    required int start,
    required int end,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => parts,
      1 => body,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(45, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = isAwait == true
        ? 1
        : isAwait == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(parts);
    fields.cells[fieldOffset + 2] = rawRef(body);
    return row;
  }

  int putForInParts({
    required SourceFile source,
    required int start,
    required int end,
    required int target,
    required int iterable,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => target,
      1 => iterable,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(46, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = rawRef(iterable);
    return row;
  }

  int putForParts({
    required SourceFile source,
    required int start,
    required int end,
    int? initializer,
    int? condition,
    List<int> updaters = const [],
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(47, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(initializer);
    fields.cells[fieldOffset + 1] = rawRef(condition);
    fields.cells[fieldOffset + 2] = rawRefs(updaters);
    return row;
  }

  int putForStatement({
    required SourceFile source,
    required int start,
    required int end,
    bool isAwait = false,
    required int parts,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => parts,
      1 => body,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(48, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = isAwait == true
        ? 1
        : isAwait == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(parts);
    fields.cells[fieldOffset + 2] = rawRef(body);
    return row;
  }

  int putFormalParameter({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(49, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = parameters.length;
    int child(int ix) => parameters[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(50, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(parameters);
    return row;
  }

  int putFunctionExpression({
    required SourceFile source,
    required int start,
    required int end,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = typeParameters == null ? 2 : 3;
    int child(int ix) {
      if (typeParameters != null) {
        if (ix == 0) return typeParameters;
        ix--;
      }
      return ix == 0 ? parameters : body;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(51, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(typeParameters);
    fields.cells[fieldOffset + 1] = rawRef(parameters);
    fields.cells[fieldOffset + 2] = rawRef(body);
    return row;
  }

  int putFunctionParameterSuffix({
    required SourceFile source,
    required int start,
    required int end,
    int? typeParameters,
    required int parameters,
    int? questionOffset,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        ends[parameters],
        end - 1,
        "questionOffset",
      );
    }
    final arity = typeParameters == null ? 1 : 2;
    int child(int ix) {
      return typeParameters != null && ix == 0 ? typeParameters : parameters;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(52, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(typeParameters);
    fields.cells[fieldOffset + 1] = rawRef(parameters);
    fields.cells[fieldOffset + 2] = questionOffset ?? _nil;
    return row;
  }

  int putFunctionTypeAliasDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(53, start, end);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeParameters);
    fields.cells[fieldOffset + 3] = rawRef(parameters);
    fields.cells[fieldOffset + 4] = rawRefs(metadata);
    return row;
  }

  int putFunctionTypeAnnotation({
    required SourceFile source,
    required int start,
    required int end,
    int? questionOffset,
    int? returnType,
    int? typeParameters,
    required int parameters,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(54, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(returnType);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(parameters);
    fields.cells[fieldOffset + 3] = questionOffset ?? _nil;
    return row;
  }

  int putFunctionTypeParameter({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required FunctionTypeParameterKind kind,
    bool isCovariant = false,
    required int type,
    int? name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1 + (name == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(55, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = parameters.length;
    int child(int ix) => parameters[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(56, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(parameters);
    return row;
  }

  int putGetterDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    bool isStatic = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(57, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
    required int guard,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => pattern,
      1 => guard,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(58, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRef(guard);
    return row;
  }

  int putIdentifier({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(59, start, end);
    return row;
  }

  int putIdentifierExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int identifier,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => identifier,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(60, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(identifier);
    return row;
  }

  int putIdentifierPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => name,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(61, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(name);
    return row;
  }

  int putIfElement({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenElement,
    int? elseElement,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(62, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(casePattern);
    fields.cells[fieldOffset + 2] = rawRef(thenElement);
    fields.cells[fieldOffset + 3] = rawRef(elseElement);
    return row;
  }

  int putIfStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    int? casePattern,
    required int thenStatement,
    int? elseStatement,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(63, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(casePattern);
    fields.cells[fieldOffset + 2] = rawRef(thenStatement);
    fields.cells[fieldOffset + 3] = rawRef(elseStatement);
    return row;
  }

  int putImportDirective({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
    List<int> configurations = const [],
    bool isDeferred = false,
    int? prefix,
    List<int> combinators = const [],
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(64, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int target,
    required int index,
    bool isNullAware = false,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => target,
      1 => index,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(65, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = rawRef(index);
    fields.cells[fieldOffset + 2] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
    return row;
  }

  int putInstanceCreationExpression({
    required SourceFile source,
    required int start,
    required int end,
    InstanceCreationKind kind = .implicit,
    required List<int> name,
    int? typeArguments,
    int? constructorName,
    required int arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(66, start, end);
    final fieldOffset = fields.reserve(5);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(constructorName);
    fields.cells[fieldOffset + 3] = rawRef(arguments);
    fields.cells[fieldOffset + 4] = rawRefs(name);
    return row;
  }

  int putInterpolatedStringExpression({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> parts,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = parts.length;
    int child(int ix) => parts[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(67, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(parts);
    return row;
  }

  int putInvocationExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int callee,
    int? typeArguments,
    required int arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = typeArguments == null ? 2 : 3;
    int child(int ix) {
      if (ix == 0) return callee;
      return typeArguments != null && ix == 1 ? typeArguments : arguments;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(68, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(callee);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    fields.cells[fieldOffset + 2] = rawRef(arguments);
    return row;
  }

  int putLabel({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => name,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(69, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(name);
    return row;
  }

  int putLabeledStatement({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> labels,
    required int statement,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = labels.length + 1;
    int child(int ix) {
      return ix < labels.length ? labels[ix] : statement;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(70, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(statement);
    fields.cells[fieldOffset + 1] = rawRefs(labels);
    return row;
  }

  int putLibraryDirective({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    int? name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + (name == null ? 0 : 1);
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : name!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(71, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    return row;
  }

  int putListPattern({
    required SourceFile source,
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(72, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRefs(elements);
    return row;
  }

  int putLiteralExpression({
    required SourceFile source,
    required int start,
    required int end,
    required LiteralKind kind,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(73, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = kind.index;
    return row;
  }

  int putLocalFunctionDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    int? returnType,
    required int name,
    int? typeParameters,
    required int parameters,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(74, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int left,
    required LogicalPatternOperator op,
    required int right,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => left,
      1 => right,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(75, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(left);
    fields.cells[fieldOffset + 1] = op.index;
    fields.cells[fieldOffset + 2] = rawRef(right);
    return row;
  }

  int putMapEntryElement({
    required SourceFile source,
    required int start,
    required int end,
    required int key,
    required int value,
    bool isNullAwareKey = false,
    bool isNullAwareValue = false,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => key,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(76, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(key);
    fields.cells[fieldOffset + 1] = rawRef(value);
    fields.cells[fieldOffset + 2] = isNullAwareKey == true
        ? 1
        : isNullAwareKey == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 3] = isNullAwareValue == true
        ? 1
        : isNullAwareValue == false
        ? 0
        : _nil;
    return row;
  }

  int putMapPattern({
    required SourceFile source,
    required int start,
    required int end,
    int? typeArguments,
    required List<int> elements,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = elements.length + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (typeArguments != null) {
        if (ix == 0) return typeArguments;
        ix--;
      }
      return elements[ix];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(77, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(typeArguments);
    fields.cells[fieldOffset + 1] = rawRefs(elements);
    return row;
  }

  int putMapPatternEntry({
    required SourceFile source,
    required int start,
    required int end,
    required int key,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => key,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(78, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(key);
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putMethodDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(79, start, end);
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

  int putMissingClassMember({required SourceFile source, required int offset}) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(80, start, end);
    return row;
  }

  int putMissingExpression({required SourceFile source, required int offset}) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(81, start, end);
    return row;
  }

  int putMissingFunctionBody({
    required SourceFile source,
    required int offset,
  }) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(82, start, end);
    return row;
  }

  int putMissingPattern({required SourceFile source, required int offset}) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(83, start, end);
    return row;
  }

  int putMissingStatement({required SourceFile source, required int offset}) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(84, start, end);
    return row;
  }

  int putMissingStringExpression({
    required SourceFile source,
    required int offset,
  }) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(85, start, end);
    return row;
  }

  int putMissingTopLevelDeclaration({
    required SourceFile source,
    required int offset,
  }) {
    final start = offset;
    final end = offset;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(86, start, end);
    return row;
  }

  int putMissingTypeAnnotation({
    required SourceFile source,
    required int offset,
  }) {
    final start = offset;
    final end = offset;
    const int? questionOffset = null;
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final row = _appendRow(87, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = questionOffset ?? _nil;
    return row;
  }

  int putMixinDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(88, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required FunctionBodyModifier modifier,
    required int block,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => block,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(89, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = modifier.index;
    fields.cells[fieldOffset + 1] = rawRef(block);
    return row;
  }

  int putNamedPatternField({
    required SourceFile source,
    required int start,
    required int end,
    int? name,
    required int pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = name == null ? 1 : 2;
    int child(int ix) {
      return name != null && ix == 0 ? name : pattern;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(90, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(pattern);
    return row;
  }

  int putNamedRecordField({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => name,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(91, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putNamedRecordTypeField({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int type,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1 + (1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(92, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
    return row;
  }

  int putNamedTypeAnnotation({
    required SourceFile source,
    required int start,
    required int end,
    int? questionOffset,
    int? prefix,
    required int name,
    int? typeArguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    if (questionOffset != null) {
      RangeError.checkValueInInterval(
        questionOffset,
        start,
        end - 1,
        "questionOffset",
      );
    }
    final arity =
        (prefix == null ? 0 : 1) + 1 + (typeArguments == null ? 0 : 1);
    int child(int ix) {
      if (prefix != null) {
        if (ix == 0) return prefix;
        ix--;
      }
      return ix == 0 ? name : typeArguments!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(93, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(prefix);
    fields.cells[fieldOffset + 1] = rawRef(name);
    fields.cells[fieldOffset + 2] = rawRef(typeArguments);
    fields.cells[fieldOffset + 3] = questionOffset ?? _nil;
    return row;
  }

  int putNamespaceCombinator({
    required SourceFile source,
    required int start,
    required int end,
    required NamespaceCombinatorKind kind,
    required List<int> names,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = names.length;
    int child(int ix) => names[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(94, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = rawRefs(names);
    return row;
  }

  int putNullAssertPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => pattern,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(95, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    return row;
  }

  int putNullAssertionExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int operand,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => operand,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(96, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(operand);
    return row;
  }

  int putNullAwareElement({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(97, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putNullCheckPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => pattern,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(98, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    return row;
  }

  int putObjectPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int type,
    required List<int> fields,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1 + fields.length;
    int child(int ix) {
      return ix == 0 ? type : fields[ix - 1];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(99, start, end);
    final fieldOffset = this.fields.reserve(2);
    this.fields.cells[fieldOffset + 0] = rawRef(type);
    this.fields.cells[fieldOffset + 1] = rawRefs(fields);
    return row;
  }

  int putOperatorDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(100, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    ParameterDefaultSeparator separator = .equals,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(101, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = separator.index;
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putParenthesizedExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(102, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putParenthesizedPattern({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => pattern,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(103, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    return row;
  }

  int putPartDirective({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int uri,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : uri;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(104, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(uri);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    return row;
  }

  int putPartOfDirective({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int target,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : target;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(105, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    return row;
  }

  int putPatternAssignmentExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => pattern,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(106, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putPatternForInBinding({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1;
    int child(int ix) {
      return ix < metadata.length ? metadata[ix] : pattern;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(107, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required bool isFinal,
    required int pattern,
    required int initializer,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 2;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? pattern : initializer;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(108, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int declaration,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => declaration,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(109, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(declaration);
    return row;
  }

  int putPositionalRecordTypeField({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int type,
    int? name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1 + (name == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? type : name!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(110, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
    return row;
  }

  int putPrimaryConstructorBody({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    List<int> initializers = const [],
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + initializers.length + 1;
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      return ix < initializers.length ? initializers[ix] : body;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(111, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRefs(metadata);
    fields.cells[fieldOffset + 2] = rawRefs(initializers);
    return row;
  }

  int putPropertyAccessExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int target,
    required int property,
    bool isNullAware = false,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => target,
      1 => property,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(112, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(target);
    fields.cells[fieldOffset + 1] = rawRef(property);
    fields.cells[fieldOffset + 2] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
    return row;
  }

  int putRecordExpression({
    required SourceFile source,
    required int start,
    required int end,
    bool hasConstKeyword = false,
    required List<int> fields,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = fields.length;
    int child(int ix) => fields[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(113, start, end);
    final fieldOffset = this.fields.reserve(2);
    this.fields.cells[fieldOffset + 0] = hasConstKeyword == true
        ? 1
        : hasConstKeyword == false
        ? 0
        : _nil;
    this.fields.cells[fieldOffset + 1] = rawRefs(fields);
    return row;
  }

  int putRecordPattern({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> fields,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = fields.length;
    int child(int ix) => fields[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(114, start, end);
    final fieldOffset = this.fields.reserve(1);
    this.fields.cells[fieldOffset + 0] = rawRefs(fields);
    return row;
  }

  int putRecordTypeAnnotation({
    required SourceFile source,
    required int start,
    required int end,
    int? questionOffset,
    List<int> positionalFields = const [],
    int? namedFields,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(115, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(namedFields);
    fields.cells[fieldOffset + 1] = rawRefs(positionalFields);
    fields.cells[fieldOffset + 2] = questionOffset ?? _nil;
    return row;
  }

  int putRecordTypeNamedFields({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> fields,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = fields.length;
    int child(int ix) => fields[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(116, start, end);
    final fieldOffset = this.fields.reserve(1);
    this.fields.cells[fieldOffset + 0] = rawRefs(fields);
    return row;
  }

  int putRedirectingConstructorInitializer({
    required SourceFile source,
    required int start,
    required int end,
    int? name,
    required int arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = name == null ? 1 : 2;
    int child(int ix) {
      return name != null && ix == 0 ? name : arguments;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(117, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(arguments);
    return row;
  }

  int putRelationalPattern({
    required SourceFile source,
    required int start,
    required int end,
    required RelationalPatternOperator op,
    required int operand,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => operand,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(118, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = op.index;
    fields.cells[fieldOffset + 1] = rawRef(operand);
    return row;
  }

  int putRestPatternElement({
    required SourceFile source,
    required int start,
    required int end,
    int? pattern,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = pattern == null ? 0 : 1;
    int child(int ix) => switch (ix) {
      0 when pattern != null => pattern,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(119, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    return row;
  }

  int putRethrowStatement({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(120, start, end);
    return row;
  }

  int putReturnStatement({
    required SourceFile source,
    required int start,
    required int end,
    int? expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = expression == null ? 0 : 1;
    int child(int ix) => switch (ix) {
      0 when expression != null => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(121, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putScriptTag({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(122, start, end);
    return row;
  }

  int putSetterDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(123, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    bool isNullAware = false,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(124, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = isNullAware == true
        ? 1
        : isNullAware == false
        ? 0
        : _nil;
    return row;
  }

  int putStringInterpolation({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required bool isBraced,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(125, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = isBraced == true
        ? 1
        : isBraced == false
        ? 0
        : _nil;
    return row;
  }

  int putStringLiteralExpression({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(126, start, end);
    return row;
  }

  int putStringText({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(127, start, end);
    return row;
  }

  int putSuperConstructorInitializer({
    required SourceFile source,
    required int start,
    required int end,
    int? name,
    required int arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = name == null ? 1 : 2;
    int child(int ix) {
      return name != null && ix == 0 ? name : arguments;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(128, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(arguments);
    return row;
  }

  int putSuperExpression({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(129, start, end);
    return row;
  }

  int putSwitchExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required List<int> cases,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1 + cases.length;
    int child(int ix) {
      return ix == 0 ? expression : cases[ix - 1];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(130, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRefs(cases);
    return row;
  }

  int putSwitchExpressionCase({
    required SourceFile source,
    required int start,
    required int end,
    required int pattern,
    required int value,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => pattern,
      1 => value,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(131, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRef(value);
    return row;
  }

  int putSwitchStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required List<int> members,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1 + members.length;
    int child(int ix) {
      return ix == 0 ? expression : members[ix - 1];
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(132, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRefs(members);
    return row;
  }

  int putSwitchStatementMember({
    required SourceFile source,
    required int start,
    required int end,
    List<int> labels = const [],
    int? pattern,
    required List<int> statements,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(133, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(pattern);
    fields.cells[fieldOffset + 1] = rawRefs(labels);
    fields.cells[fieldOffset + 2] = rawRefs(statements);
    return row;
  }

  int putThisExpression({
    required SourceFile source,
    required int start,
    required int end,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final row = _appendRow(134, start, end);
    return row;
  }

  int putThrowExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(135, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    return row;
  }

  int putTopLevelFunctionDeclaration({
    required SourceFile source,
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
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(136, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(137, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    bool isExternal = false,
    int? returnType,
    required int name,
    required int parameters,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(138, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    bool isExternal = false,
    required int variables,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => variables,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(139, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = isExternal == true
        ? 1
        : isExternal == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(variables);
    return row;
  }

  int putTryStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int body,
    List<int> catchClauses = const [],
    int? finallyBlock,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1 + catchClauses.length + (finallyBlock == null ? 0 : 1);
    int child(int ix) {
      if (ix == 0) return body;
      ix--;
      return ix < catchClauses.length ? catchClauses[ix] : finallyBlock!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(140, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(body);
    fields.cells[fieldOffset + 1] = rawRef(finallyBlock);
    fields.cells[fieldOffset + 2] = rawRefs(catchClauses);
    return row;
  }

  int putTypeAliasDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? typeParameters,
    required int type,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 2 + (typeParameters == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      ix -= metadata.length;
      if (ix == 0) return name;
      ix--;
      return typeParameters != null && ix == 0 ? typeParameters : type;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(141, start, end);
    final fieldOffset = fields.reserve(4);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(typeParameters);
    fields.cells[fieldOffset + 2] = rawRef(type);
    fields.cells[fieldOffset + 3] = rawRefs(metadata);
    return row;
  }

  int putTypeArgumentList({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> arguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = arguments.length;
    int child(int ix) => arguments[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(142, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(arguments);
    return row;
  }

  int putTypeInstantiationExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required int typeArguments,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => expression,
      1 => typeArguments,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(143, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRef(typeArguments);
    return row;
  }

  int putTypeListClause({
    required SourceFile source,
    required int start,
    required int end,
    required TypeListClauseKind kind,
    required List<int> types,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = types.length;
    int child(int ix) => types[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(144, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = kind.index;
    fields.cells[fieldOffset + 1] = rawRefs(types);
    return row;
  }

  int putTypeParameter({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    required int name,
    int? bound,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = metadata.length + 1 + (bound == null ? 0 : 1);
    int child(int ix) {
      if (ix < metadata.length) return metadata[ix];
      return ix == metadata.length ? name : bound!;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(145, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(bound);
    fields.cells[fieldOffset + 2] = rawRefs(metadata);
    return row;
  }

  int putTypeParameterList({
    required SourceFile source,
    required int start,
    required int end,
    required List<int> parameters,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = parameters.length;
    int child(int ix) => parameters[ix];
    _appendEdges(start, end, arity, child);
    final row = _appendRow(146, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRefs(parameters);
    return row;
  }

  int putTypeTestExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int expression,
    required int type,
    bool isNegated = false,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => expression,
      1 => type,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(147, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(expression);
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = isNegated == true
        ? 1
        : isNegated == false
        ? 0
        : _nil;
    return row;
  }

  int putUnaryExpression({
    required SourceFile source,
    required int start,
    required int end,
    required UnaryOperator op,
    required int operand,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => operand,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(148, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = op.index;
    fields.cells[fieldOffset + 1] = rawRef(operand);
    return row;
  }

  int putUpdateExpression({
    required SourceFile source,
    required int start,
    required int end,
    required int operand,
    required UpdateOperator op,
    required bool isPrefix,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => operand,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(149, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = rawRef(operand);
    fields.cells[fieldOffset + 1] = op.index;
    fields.cells[fieldOffset + 2] = isPrefix == true
        ? 1
        : isPrefix == false
        ? 0
        : _nil;
    return row;
  }

  int putVariableDeclaration({
    required SourceFile source,
    required int start,
    required int end,
    required int name,
    int? initializer,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = initializer == null ? 1 : 2;
    int child(int ix) => switch (ix) {
      0 => name,
      1 when initializer != null => initializer,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(150, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(name);
    fields.cells[fieldOffset + 1] = rawRef(initializer);
    return row;
  }

  int putVariableDeclarationList({
    required SourceFile source,
    required int start,
    required int end,
    List<int> metadata = const [],
    VariableKeyword keyword = .none,
    bool isLate = false,
    int? type,
    required List<int> declarations,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
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

    _appendEdges(start, end, arity, child);
    final row = _appendRow(151, start, end);
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
    required SourceFile source,
    required int start,
    required int end,
    required int variables,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => variables,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(152, start, end);
    final fieldOffset = fields.reserve(1);
    fields.cells[fieldOffset + 0] = rawRef(variables);
    return row;
  }

  int putVariablePattern({
    required SourceFile source,
    required int start,
    required int end,
    PatternVariableKeyword keyword = .none,
    int? type,
    required int name,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = type == null ? 1 : 2;
    int child(int ix) {
      return type != null && ix == 0 ? type : name;
    }

    _appendEdges(start, end, arity, child);
    final row = _appendRow(153, start, end);
    final fieldOffset = fields.reserve(3);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = rawRef(type);
    fields.cells[fieldOffset + 2] = rawRef(name);
    return row;
  }

  int putWhileStatement({
    required SourceFile source,
    required int start,
    required int end,
    required int condition,
    required int body,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 2;
    int child(int ix) => switch (ix) {
      0 => condition,
      1 => body,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(154, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = rawRef(condition);
    fields.cells[fieldOffset + 1] = rawRef(body);
    return row;
  }

  int putWildcardPattern({
    required SourceFile source,
    required int start,
    required int end,
    PatternVariableKeyword keyword = .none,
    int? type,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = type == null ? 0 : 1;
    int child(int ix) => switch (ix) {
      0 when type != null => type,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(155, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = keyword.index;
    fields.cells[fieldOffset + 1] = rawRef(type);
    return row;
  }

  int putYieldStatement({
    required SourceFile source,
    required int start,
    required int end,
    bool isStar = false,
    required int expression,
  }) {
    if (!identical(source, this.source)) throw ArgumentError("source");
    RangeError.checkValidRange(start, end, source.length);
    final arity = 1;
    int child(int ix) => switch (ix) {
      0 => expression,
      _ => (throw RangeError.value(ix)),
    };
    _appendEdges(start, end, arity, child);
    final row = _appendRow(156, start, end);
    final fieldOffset = fields.reserve(2);
    fields.cells[fieldOffset + 0] = isStar == true
        ? 1
        : isStar == false
        ? 0
        : _nil;
    fields.cells[fieldOffset + 1] = rawRef(expression);
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
  AstNode? maybe(int? id) => id == null ? null : at(id);
  Iterable<int> walkIds(int root) => _IndexWalk(SyntaxTree._(this, root));

  AstNode at(int id) => switch (tags[id]) {
    0 => _RowAdjacentStringsExpression(this, id),
    1 => _RowAnnotation(this, id),
    2 => _RowArgument(this, id),
    3 => _RowArgumentList(this, id),
    4 => _RowAssertInitializer(this, id),
    5 => _RowAssertStatement(this, id),
    6 => _RowAssignmentExpression(this, id),
    7 => _RowAwaitExpression(this, id),
    8 => _RowBinaryExpression(this, id),
    9 => _RowBlockStatement(this, id),
    10 => _RowBreakStatement(this, id),
    11 => _RowCascadeExpression(this, id),
    12 => _RowCascadeIndexExpression(this, id),
    13 => _RowCascadePropertyExpression(this, id),
    14 => _RowCastExpression(this, id),
    15 => _RowCastPattern(this, id),
    16 => _RowCatchClause(this, id),
    17 => _RowClassDeclaration(this, id),
    18 => _RowClassTypeAliasDeclaration(this, id),
    19 => _RowCollectionExpression(this, id),
    20 => _RowCompilationUnit(this, id),
    21 => _RowConditionalExpression(this, id),
    22 => _RowConditionalUri(this, id),
    23 => _RowConstDotShorthandExpression(this, id),
    24 => _RowConstantPattern(this, id),
    25 => _RowConstructorDeclaration(this, id),
    26 => _RowContinueStatement(this, id),
    27 => _RowDeclaredIdentifier(this, id),
    28 => _RowDoStatement(this, id),
    29 => _RowDotShorthandExpression(this, id),
    30 => _RowDotShorthandReferenceExpression(this, id),
    31 => _RowDottedName(this, id),
    32 => _RowEmptyFunctionBody(this, id),
    33 => _RowEmptyStatement(this, id),
    34 => _RowEnumConstantDeclaration(this, id),
    35 => _RowEnumDeclaration(this, id),
    36 => _RowExportDirective(this, id),
    37 => _RowExpressionFunctionBody(this, id),
    38 => _RowExpressionStatement(this, id),
    39 => _RowExtendsClause(this, id),
    40 => _RowExtensionDeclaration(this, id),
    41 => _RowExtensionTypeDeclaration(this, id),
    42 => _RowFactoryRedirectBody(this, id),
    43 => _RowFieldDeclaration(this, id),
    44 => _RowFieldInitializer(this, id),
    45 => _RowForElement(this, id),
    46 => _RowForInParts(this, id),
    47 => _RowForParts(this, id),
    48 => _RowForStatement(this, id),
    49 => _RowFormalParameter(this, id),
    50 => _RowFormalParameterList(this, id),
    51 => _RowFunctionExpression(this, id),
    52 => _RowFunctionParameterSuffix(this, id),
    53 => _RowFunctionTypeAliasDeclaration(this, id),
    54 => _RowFunctionTypeAnnotation(this, id),
    55 => _RowFunctionTypeParameter(this, id),
    56 => _RowFunctionTypeParameterList(this, id),
    57 => _RowGetterDeclaration(this, id),
    58 => _RowGuardedPattern(this, id),
    59 => _RowIdentifier(this, id),
    60 => _RowIdentifierExpression(this, id),
    61 => _RowIdentifierPattern(this, id),
    62 => _RowIfElement(this, id),
    63 => _RowIfStatement(this, id),
    64 => _RowImportDirective(this, id),
    65 => _RowIndexExpression(this, id),
    66 => _RowInstanceCreationExpression(this, id),
    67 => _RowInterpolatedStringExpression(this, id),
    68 => _RowInvocationExpression(this, id),
    69 => _RowLabel(this, id),
    70 => _RowLabeledStatement(this, id),
    71 => _RowLibraryDirective(this, id),
    72 => _RowListPattern(this, id),
    73 => _RowLiteralExpression(this, id),
    74 => _RowLocalFunctionDeclaration(this, id),
    75 => _RowLogicalPattern(this, id),
    76 => _RowMapEntryElement(this, id),
    77 => _RowMapPattern(this, id),
    78 => _RowMapPatternEntry(this, id),
    79 => _RowMethodDeclaration(this, id),
    80 => _RowMissingClassMember(this, id),
    81 => _RowMissingExpression(this, id),
    82 => _RowMissingFunctionBody(this, id),
    83 => _RowMissingPattern(this, id),
    84 => _RowMissingStatement(this, id),
    85 => _RowMissingStringExpression(this, id),
    86 => _RowMissingTopLevelDeclaration(this, id),
    87 => _RowMissingTypeAnnotation(this, id),
    88 => _RowMixinDeclaration(this, id),
    89 => _RowModifiedBlockFunctionBody(this, id),
    90 => _RowNamedPatternField(this, id),
    91 => _RowNamedRecordField(this, id),
    92 => _RowNamedRecordTypeField(this, id),
    93 => _RowNamedTypeAnnotation(this, id),
    94 => _RowNamespaceCombinator(this, id),
    95 => _RowNullAssertPattern(this, id),
    96 => _RowNullAssertionExpression(this, id),
    97 => _RowNullAwareElement(this, id),
    98 => _RowNullCheckPattern(this, id),
    99 => _RowObjectPattern(this, id),
    100 => _RowOperatorDeclaration(this, id),
    101 => _RowParameterDefault(this, id),
    102 => _RowParenthesizedExpression(this, id),
    103 => _RowParenthesizedPattern(this, id),
    104 => _RowPartDirective(this, id),
    105 => _RowPartOfDirective(this, id),
    106 => _RowPatternAssignmentExpression(this, id),
    107 => _RowPatternForInBinding(this, id),
    108 => _RowPatternVariableDeclaration(this, id),
    109 => _RowPatternVariableDeclarationStatement(this, id),
    110 => _RowPositionalRecordTypeField(this, id),
    111 => _RowPrimaryConstructorBody(this, id),
    112 => _RowPropertyAccessExpression(this, id),
    113 => _RowRecordExpression(this, id),
    114 => _RowRecordPattern(this, id),
    115 => _RowRecordTypeAnnotation(this, id),
    116 => _RowRecordTypeNamedFields(this, id),
    117 => _RowRedirectingConstructorInitializer(this, id),
    118 => _RowRelationalPattern(this, id),
    119 => _RowRestPatternElement(this, id),
    120 => _RowRethrowStatement(this, id),
    121 => _RowReturnStatement(this, id),
    122 => _RowScriptTag(this, id),
    123 => _RowSetterDeclaration(this, id),
    124 => _RowSpreadElement(this, id),
    125 => _RowStringInterpolation(this, id),
    126 => _RowStringLiteralExpression(this, id),
    127 => _RowStringText(this, id),
    128 => _RowSuperConstructorInitializer(this, id),
    129 => _RowSuperExpression(this, id),
    130 => _RowSwitchExpression(this, id),
    131 => _RowSwitchExpressionCase(this, id),
    132 => _RowSwitchStatement(this, id),
    133 => _RowSwitchStatementMember(this, id),
    134 => _RowThisExpression(this, id),
    135 => _RowThrowExpression(this, id),
    136 => _RowTopLevelFunctionDeclaration(this, id),
    137 => _RowTopLevelGetterDeclaration(this, id),
    138 => _RowTopLevelSetterDeclaration(this, id),
    139 => _RowTopLevelVariableDeclaration(this, id),
    140 => _RowTryStatement(this, id),
    141 => _RowTypeAliasDeclaration(this, id),
    142 => _RowTypeArgumentList(this, id),
    143 => _RowTypeInstantiationExpression(this, id),
    144 => _RowTypeListClause(this, id),
    145 => _RowTypeParameter(this, id),
    146 => _RowTypeParameterList(this, id),
    147 => _RowTypeTestExpression(this, id),
    148 => _RowUnaryExpression(this, id),
    149 => _RowUpdateExpression(this, id),
    150 => _RowVariableDeclaration(this, id),
    151 => _RowVariableDeclarationList(this, id),
    152 => _RowVariableDeclarationStatement(this, id),
    153 => _RowVariablePattern(this, id),
    154 => _RowWhileStatement(this, id),
    155 => _RowWildcardPattern(this, id),
    156 => _RowYieldStatement(this, id),
    _ => throw StateError('invalid tag'),
  };
}
