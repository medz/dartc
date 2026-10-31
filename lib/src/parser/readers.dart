part of 'parser.dart';

abstract class _Reader<T> {
  late T result;

  Iterable<_Reader<Object?>> read();

  T finish() {
    final pending = [read().iterator];
    while (pending.isNotEmpty) {
      final iterator = pending.last;
      if (iterator.moveNext()) {
        pending.add(iterator.current.read().iterator);
      } else {
        pending.removeLast();
      }
    }
    return result;
  }
}

final class _ExpressionReader(
  final _Parser parser, {
  final _ParseBoundary boundary = .expression,
  _ExpressionStop? stop,
}) extends _Reader<Expression> {
  _ExpressionStop? stop = stop;

  bool start() {
    parser.beginExpression();
    stop = parser.run(trial: false, boundary: boundary);
    if (stop != .complete) return false;
    result = parser.finishExpression(0, 0);
    assert(parser.prefixes.isEmpty && parser.questions.isEmpty);
    return true;
  }

  @override
  Iterable<_Reader<Object?>> read() sync* {
    if (stop == null && start()) return;
    yield* parser.readExpressionSyntax(boundary: boundary, stop: stop);
    result = parser.finishExpression(0, 0);
    assert(parser.prefixes.isEmpty && parser.questions.isEmpty);
  }
}

final class _ConditionReader(
  final _Parser parser, {
  final bool allowCase = false,
}) extends _Reader<Expression> {
  CasePattern? casePattern;

  @override
  Iterable<_Reader<Object?>> read() sync* {
    parser.expect(.leftParen);
    final reader = _ExpressionReader(parser);
    if (!reader.start()) yield reader;
    result = reader.result;
    if (parser.current.kind == .keywordCase) {
      if (!allowCase) {
        parser.error(
          'unexpected_case',
          'This condition cannot contain a case pattern.',
          parser.current,
        );
      }
      parser.advance();
      final pattern = _CasePatternReader(parser, condition: true);
      yield pattern;
      casePattern = pattern.result;
    }
    parser.expect(.rightParen);
  }
}

final class _ArgumentsReader(final _Parser parser)
    extends _Reader<ArgumentList> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    final opening = parser.current;
    parser.expect(.leftParen);
    if (opening.kind != .leftParen) {
      result = ArgumentList(
        source: parser.source,
        start: opening.start,
        end: opening.start,
        arguments: const [],
      );
      return;
    }
    parser.beginExpression();
    final arguments = _ArgumentList(opening, 0, 0);
    parser.frames.add(arguments);
    yield* parser.readExpressionSyntax(boundary: .header);
    assert(
      parser.frames.isEmpty &&
          parser.values.isEmpty &&
          parser.operators.isEmpty,
    );
    result = arguments.result;
  }
}

final class _ForHeaderReader(final _Parser parser)
    extends _Reader<ForLoopParts> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    parser.beginExpression();
    final opening = parser.current;
    parser.expect(.leftParen);
    final header = _ForStatementHeader(opening, 0, 0, parser.current.start);
    parser.frames.add(header);
    parser.initializeForHeader(header);
    yield* parser.readExpressionSyntax(boundary: .header);
    assert(
      parser.frames.isEmpty &&
          parser.values.isEmpty &&
          parser.operators.isEmpty,
    );
    result = header.parts;
  }
}

extension on _Parser {
  void beginExpression() {
    assert(frames.isEmpty && values.isEmpty && operators.isEmpty);
    expectsOperand = true;
    hasSyntaxError = false;
    selectorTarget = null;
    postfixTarget = null;
    checkedNullAware = false;
  }

  Iterable<_Reader<Object?>> readExpressionSyntax({
    _ParseBoundary boundary = .input,
    _ExpressionStop? stop,
  }) sync* {
    while (true) {
      stop ??= pendingSyntax != null
          ? _ExpressionStop.syntax
          : nullableForInitializer == null
          ? run(trial: false, boundary: boundary)
          : _ExpressionStop.conditional;
      switch (stop) {
        case .complete:
          return;
        case .syntax:
          final syntax = pendingSyntax!;
          pendingSyntax = null;
          yield syntax;
        case .conditional:
          var branches = lookahead.conditionals[cursor];
          if (branches == null) {
            final reader = _ConditionalReader(this);
            yield reader;
            branches = reader.result;
          }
          acceptConditional(branches);
      }
      stop = null;
    }
  }

  void adopt(_Parser child) {
    cursor = child.cursor;
    current = child.current;
    diagnostics.addAll(child.diagnostics);
  }
}

final class _OperandReader(
  final _Parser parent,
  final _Parser child,
  final _Reader<Expression> expression,
) extends _Reader<void> {
  @override
  Iterable<_Reader<Object?>> read() sync* {
    yield expression;
    parent.adopt(child);
    parent.values.add(expression.result);
    parent.expectsOperand = false;
  }
}
