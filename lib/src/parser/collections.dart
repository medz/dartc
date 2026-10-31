part of 'parser.dart';

final class _Collection(
  super.opening,
  super.valueBase,
  super.operatorBase, {
  required final int start,
  required final bool hasConstKeyword,
  required final TypeArgumentList? typeArguments,
}) extends _Delimiter {
  final List<CollectionElement> elements = [];
  final List<_ElementControl> controls = [];
  Token? prefix;
  Expression? key;
  Token? keyPrefix;

  @override
  TokenKind get closing =>
      opening.kind == .leftBrace ? .rightBrace : .rightBracket;
}

sealed class _ElementControl(final Token token);

final class _IfElement(super.token) extends _ElementControl {
  late Expression condition;
  CollectionElement? thenElement;
}

final class _IfHeader(
  super.opening,
  super.valueBase,
  super.operatorBase,
  final _IfElement element,
) extends _Delimiter {
  @override
  TokenKind get closing => .rightParen;
}

extension on _Parser {
  void parseCollectionPrefix() {
    final first = current;
    final hasConst = first.kind == .keywordConst;
    if (hasConst) advance();
    TypeArgumentList? arguments;
    if (current.kind == .less) {
      final reader = _TypeReader(this);
      arguments = reader.read(arguments: true) as TypeArgumentList?;
      if (reader.failure case final failure?) {
        error(failure.$1, failure.$2, failure.$3);
      }
    }
    if (current.kind == .leftBracket ||
        current.kind == .emptyBrackets ||
        current.kind == .emptyBracketsAssign ||
        current.kind == .leftBrace) {
      openCollection(
        start: first.start,
        hasConstKeyword: hasConst,
        typeArguments: arguments,
      );
    } else {
      error(
        'unsupported_syntax',
        'Only a collection literal is supported after this prefix.',
        first,
      );
    }
  }

  void openCollection({
    int? start,
    bool hasConstKeyword = false,
    TypeArgumentList? typeArguments,
  }) {
    final token = current;
    if (token.kind == .emptyBrackets || token.kind == .emptyBracketsAssign) {
      values.add(
        CollectionExpression(
          source: source,
          start: start ?? token.start,
          end: token.start + 2,
          kind: .list,
          hasConstKeyword: hasConstKeyword,
          typeArguments: typeArguments,
          elements: const [],
        ),
      );
      consumeEmptyBrackets();
      expectsOperand = false;
      return;
    }
    delimiters.add(
      _Collection(
        token,
        values.length,
        operators.length,
        start: start ?? token.start,
        hasConstKeyword: hasConstKeyword,
        typeArguments: typeArguments,
      ),
    );
    advance();
    expectsOperand = true;
  }

  void consumeEmptyBrackets() {
    final token = current;
    if (token.kind == .emptyBracketsAssign) {
      current = Token(.assign, source, token.start + 2, token.end);
    } else {
      advance();
    }
  }

  bool parseElementPrefix(_Collection frame) {
    if (frame.prefix != null ||
        values.length != frame.valueBase ||
        operators.length != frame.operatorBase) {
      return false;
    }
    final token = current;
    if (token.kind == .question || token.kind == .nullAwareAccess) {
      frame.prefix = token;
      if (token.kind == .nullAwareAccess) {
        current = Token(.dot, source, token.start + 1, token.end);
      } else {
        advance();
      }
      return true;
    }
    if (frame.key != null) return false;
    switch (token.kind) {
      case .spread || .nullAwareSpread:
        frame.prefix = token;
        advance();
        return true;
      case .keywordIf:
        final control = _IfElement(token);
        frame.controls.add(control);
        advance();
        final opening = current;
        if (opening.kind == .leftParen) {
          advance();
        } else {
          error('expected_opener', "Expected '(' after 'if'.", opening);
        }
        delimiters.add(
          _IfHeader(opening, values.length, operators.length, control),
        );
        return true;
      case .keywordFor || .keywordAwait:
        if (token.kind == .keywordAwait &&
            tokens[cursor + 1].kind != .keywordFor) {
          return false;
        }
        openForElement(frame);
        return true;
      default:
        return false;
    }
  }

  void parseMapKey(_Collection frame) {
    if (frame.key != null) {
      unexpected();
      return;
    }
    if (frame.opening.kind != .leftBrace) {
      error('map_entry_in_list', 'A list cannot contain a map entry.', current);
    }
    if (frame.prefix?.kind == .spread ||
        frame.prefix?.kind == .nullAwareSpread) {
      error('spread_map_key', 'A spread cannot be a map key.', frame.prefix!);
    }
    frame.key = finishExpression(frame.valueBase, frame.operatorBase);
    frame.keyPrefix = frame.prefix;
    frame.prefix = null;
    advance();
    expectsOperand = true;
  }

  // Returns true when an else token was consumed and its body is still pending.
  bool finishCollectionElement(_Collection frame) {
    final expression = finishExpression(frame.valueBase, frame.operatorBase);
    final prefix = frame.prefix;
    final key = frame.key;
    CollectionElement element;
    if (key != null) {
      element = MapEntryElement(
        source: source,
        start: frame.keyPrefix?.start ?? key.start,
        end: expression.end,
        key: key,
        value: expression,
        isNullAwareKey:
            frame.keyPrefix?.kind == .question ||
            frame.keyPrefix?.kind == .nullAwareAccess,
        isNullAwareValue: prefix != null,
      );
    } else if (prefix != null) {
      element = prefix.kind == .spread || prefix.kind == .nullAwareSpread
          ? SpreadElement(
              source: source,
              start: prefix.start,
              end: expression.end,
              expression: expression,
              isNullAware: prefix.kind == .nullAwareSpread,
            )
          : NullAwareElement(
              source: source,
              start: prefix.start,
              end: expression.end,
              expression: expression,
            );
    } else {
      element = expression;
    }
    frame.prefix = null;
    frame.key = null;
    frame.keyPrefix = null;
    expectsOperand = true;
    while (frame.controls.isNotEmpty) {
      final control = frame.controls.last;
      switch (control) {
        case _IfElement():
          if (control.thenElement == null && current.kind == .keywordElse) {
            control.thenElement = element;
            advance();
            return true;
          }
          element = IfElement(
            source: source,
            start: control.token.start,
            end: element.end,
            condition: control.condition,
            thenElement: control.thenElement ?? element,
            elseElement: control.thenElement == null ? null : element,
          );
        case _ForElement():
          element = ForElement(
            source: source,
            start: control.token.start,
            end: element.end,
            isAwait: control.isAwait,
            parts: control.parts,
            body: element,
          );
      }
      frame.controls.removeLast();
    }
    frame.elements.add(element);
    return false;
  }

  CollectionExpression closeCollection(_Collection frame, int end) {
    if (trialStart != null &&
        frame.opening == tokens[trialStart!] &&
        current.kind == .rightBracket) {
      final following = tokens[cursor + 1].kind;
      initialOperatorBoundary =
          following.precedence != 0 &&
          following != .less &&
          (following != .question ||
              tokens[cursor + 2].kind != .leftBracket &&
                  tokens[cursor + 2].kind != .emptyBrackets &&
                  tokens[cursor + 2].kind != .emptyBracketsAssign);
    }
    if (values.length > frame.valueBase ||
        operators.length > frame.operatorBase ||
        frame.prefix != null ||
        frame.key != null ||
        frame.controls.isNotEmpty) {
      finishCollectionElement(frame);
    }
    return CollectionExpression(
      source: source,
      start: frame.start,
      end: end,
      kind: frame.opening.kind == .leftBrace ? .setOrMap : .list,
      hasConstKeyword: frame.hasConstKeyword,
      typeArguments: frame.typeArguments,
      elements: frame.elements,
    );
  }
}
