part of 'parser.dart';

final class _ForElement(super.token, {required final bool isAwait})
    extends _ElementControl {
  late int parts;
}

enum _ForPhase { initializer, condition, updaters, iterable }

final class _NullableForInitializer(
  final _ForHeader frame,
  final int start,
  final int declarationEnd,
  final Token remainder,
);

sealed class _ForHeader(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final int start,
) extends _Delimiter {
  _ForPhase phase = .initializer;
  _VariableDeclarations? declarations;
  List<int> metadata = const [];
  int? initializer;
  int? condition;
  int? target;
  final List<int> updaters = [];
  int end = start;

  @override
  TokenKind get closing => .rightParen;
}

final class _ForElementHeader(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final _ForElement element,
  super.start,
) extends _ForHeader;

final class _ForStatementHeader(
  super.opening,
  super.valueBase,
  super.operatorBase,
  super.start,
) extends _ForHeader {
  late int parts;
}

extension on _Parser {
  void openForElement(_Collection collection) {
    final token = current;
    final isAwait = token.kind == .keywordAwait;
    if (isAwait) {
      if (!inAsync) {
        error(
          'await_in_sync',
          'An await-for requires an asynchronous context.',
          token,
        );
      }
      advance();
    }
    advance();
    final opening = current;
    if (opening.kind == .leftParen) {
      advance();
    } else {
      error('expected_opener', "Expected '(' after 'for'.", opening);
    }
    final control = _ForElement(token, isAwait: isAwait);
    collection.controls.add(control);
    final frame = _ForElementHeader(
      opening,
      values.length,
      operators.length,
      control,
      current.start,
    );
    frames.add(frame);
    initializeForHeader(frame);
  }

  void initializeForHeader(_ForHeader frame) {
    if (current.kind == .at || isPatternDeclaration) {
      pendingSyntax = _ForDeclarationReader(this, frame);
      return;
    }
    if (canStartVariableDeclaration) {
      pendingSyntax = _SyntaxTask(readForVariables(frame));
    }
  }

  Iterable<_Reader<Object?>> readForVariables(_ForHeader frame) sync* {
    final start = cursor;
    final reader = _VariableReader(this, forLoop: true);
    yield reader;
    frame.declarations = reader.result;
    if (frame.declarations
        case _VariableDeclarations(
          keyword: .none,
          isLate: false,
          type: final int t,
        )
        when current.kind == .assign &&
            cursor < lookahead.lastColon &&
            switch (arena.view(t)) {
              NamedTypeAnnotation(isNullable: true) ||
              RecordTypeAnnotation(isNullable: true) => true,
              _ => false,
            }) {
      nullableForInitializer = _NullableForInitializer(
        frame,
        start,
        cursor,
        current,
      );
      cursor -= 2;
      current = tokens[cursor];
      assert(current.kind == .question);
    }
  }

  bool hasForExpression(_ForHeader frame) =>
      values.length > frame.valueBase || operators.length > frame.operatorBase;

  void finishVariable(_ForHeader frame) {
    final declarations = frame.declarations!;
    int? initializer;
    if (declarations.initializing || hasForExpression(frame)) {
      if (!declarations.initializing) {
        error(
          'expected_assignment',
          "Expected '=' before the initializer.",
          current,
        );
      }
      initializer = finishExpression(frame.valueBase, frame.operatorBase);
    }
    declarations.variables.add(
      arena.variableDeclaration(
        name: declarations.name,
        initializer: initializer,
      ),
    );
    declarations.initializing = false;
    expectsOperand = true;
  }

  void finishForInitializer(_ForHeader frame) {
    if (frame.declarations case final declarations?) {
      finishVariable(frame);
      frame.initializer = arena.variableDeclarationList(
        start: arena.startOf(frame.metadata.firstOrNull) ?? declarations.start,
        metadata: frame.metadata,
        end: arena.end(declarations.variables.last),
        keyword: declarations.keyword,
        isLate: declarations.isLate,
        type: declarations.type,
        declarations: declarations.variables,
      );
    } else if (hasForExpression(frame)) {
      frame.initializer = finishExpression(frame.valueBase, frame.operatorBase);
    }
    expectsOperand = true;
  }

  bool parseForSeparator(_ForHeader frame) {
    final token = current;
    if (frame.declarations case final declarations?
        when frame.phase == .initializer &&
            token.kind == .assign &&
            !declarations.initializing &&
            !hasForExpression(frame)) {
      declarations.initializing = true;
      advance();
      return true;
    }
    if (token.kind == .keywordIn && frame.phase == .initializer) {
      if (frame.declarations case final declarations?) {
        finishVariable(frame);
        if (declarations.variables.length != 1 ||
            arena
                    .view<VariableDeclaration>(declarations.variables.single)
                    .initializer !=
                null ||
            declarations.isLate) {
          error(
            'invalid_for_in_declaration',
            'Expected one variable without an initializer.',
            token,
          );
        }
        frame.target = arena.declaredIdentifier(
          start:
              arena.startOf(frame.metadata.firstOrNull) ?? declarations.start,
          metadata: frame.metadata,

          keyword: declarations.keyword,
          type: declarations.type,
          name: declarations.name,
        );
      } else {
        final expression = finishExpression(
          frame.valueBase,
          frame.operatorBase,
        );
        if (arena.kind(expression) == .identifierExpression) {
          frame.target = arena.childAt(expression, 0);
        } else {
          error(
            'invalid_for_in_target',
            'Expected an identifier before in.',
            token,
          );
          frame.target = arena.identifier(
            start: arena.start(expression),
            end: arena.start(expression),
          );
        }
      }
      frame.phase = .iterable;
      advance();
      expectsOperand = true;
      return true;
    }
    if (token.kind == .semicolon) {
      switch (frame.phase) {
        case .initializer:
          finishForInitializer(frame);
          frame.phase = .condition;
        case .condition:
          if (hasForExpression(frame)) {
            frame.condition = finishExpression(
              frame.valueBase,
              frame.operatorBase,
            );
          }
          frame.phase = .updaters;
        case .updaters || .iterable:
          unexpected();
          return true;
      }
      frame.end = token.end;
      advance();
      expectsOperand = true;
      return true;
    }
    if (token.kind == .comma) {
      if (frame.phase == .initializer && frame.declarations != null) {
        finishVariable(frame);
        advance();
        frame.declarations!.name = readVariableName();
      } else if (frame.phase == .updaters) {
        frame.updaters.add(
          finishExpression(frame.valueBase, frame.operatorBase),
        );
        frame.end = arena.end(frame.updaters.last);
        advance();
        expectsOperand = true;
      } else {
        unexpected();
      }
      return true;
    }
    return false;
  }

  int closeForHeader(_ForHeader frame) {
    if (frame.phase == .iterable) {
      final iterable = finishExpression(frame.valueBase, frame.operatorBase);
      return arena.forInParts(
        start: frame.start,

        target: frame.target!,
        iterable: iterable,
      );
    }
    if (frame.phase != .updaters) {
      error(
        'expected_semicolon',
        "Expected two semicolons in a for header.",
        current,
      );
      if (frame.phase == .initializer) {
        finishForInitializer(frame);
      } else if (hasForExpression(frame)) {
        frame.condition = finishExpression(frame.valueBase, frame.operatorBase);
      }
      frame.end = current.start;
    } else if (hasForExpression(frame)) {
      frame.updaters.add(finishExpression(frame.valueBase, frame.operatorBase));
      frame.end = arena.end(frame.updaters.last);
    }
    return arena.forParts(
      start: frame.start,
      end: frame.end,
      initializer: frame.initializer,
      condition: frame.condition,
      updaters: frame.updaters,
    );
  }
}
