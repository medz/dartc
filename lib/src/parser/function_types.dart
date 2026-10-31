part of 'parser.dart';

final class _FunctionTypes(
  final Token function,
  final TypeAnnotation? returnType,
) extends _TypeFrame {
  TypeParameterList? typeParameters;
  Token? opening;
  final List<FunctionTypeParameter> parameters = [];
  FunctionTypeParameterKind kind = .requiredPositional;
  TokenKind? optionalClose;
  int groupStart = 0;
  int parameterStart = 0;
  bool requiredKeyword = false;
  bool covariantKeyword = false;
  bool groupClosed = false;
}

final class _TypeVariables(final Token opening) extends _TypeFrame {
  final List<TypeParameter> parameters = [];
  Identifier? name;
  Token? boundStart;
}

extension on _TypeReader {
  TypeAnnotation? beginFunction(TypeAnnotation? returnType) {
    final frame = _FunctionTypes(current, returnType);
    frames.add(frame);
    parser.advance();
    if (current.kind == .less) {
      final variables = _TypeVariables(current);
      frames.add(variables);
      parser.advance();
      return prepareVariable(variables);
    }
    return beginParameters(frame);
  }

  TypeAnnotation? prepareVariable(_TypeVariables frame) {
    while (failure == null) {
      if (!current.kind.isTypeParameterName) {
        fail(
          current.kind == .at ? 'unsupported_syntax' : 'expected_identifier',
          current.kind == .at
              ? 'Type metadata parsing is not yet supported.'
              : 'Expected a type parameter name.',
        );
        return null;
      }
      final name = frame.name = parser.identifier(current);
      parser.advance();
      if (current.kind == .keywordExtends) {
        parser.advance();
        frame.boundStart = current;
        return null;
      }
      frame.parameters.add(
        TypeParameter(
          source: source,
          start: name.start,
          end: name.end,
          name: name,
        ),
      );
      if (current.kind == .comma) {
        parser.advance();
        continue;
      }
      return finishVariables(frame);
    }
    return null;
  }

  TypeAnnotation? continueVariables(_TypeVariables frame) {
    if (current.kind == .comma) {
      parser.advance();
      return prepareVariable(frame);
    }
    return finishVariables(frame);
  }

  TypeAnnotation? finishVariables(_TypeVariables frame) {
    final end = closeAngle();
    if (failure != null) return null;
    frames.removeLast();
    final parameters = TypeParameterList(
      source: source,
      start: frame.opening.start,
      end: end,
      parameters: frame.parameters,
    );
    if (frames.isEmpty) {
      completedParameters = parameters;
      return null;
    }
    final function = frames.last as _FunctionTypes;
    function.typeParameters = parameters;
    return beginParameters(function);
  }

  TypeAnnotation? beginParameters(_FunctionTypes frame) {
    if (current.kind != .leftParen) {
      fail(
        'expected_opener',
        "Expected '(' after Function and its type parameters.",
      );
      return null;
    }
    frame.opening = current;
    parser.advance();
    return prepareParameter(frame);
  }

  TypeAnnotation? prepareParameter(_FunctionTypes frame) {
    if (current.kind == .rightParen) return finishFunction(frame);
    if (current.kind == .leftBracket || current.kind == .leftBrace) {
      if (frame.optionalClose != null) {
        fail(
          'unexpected_token',
          'Only one optional parameter group is allowed.',
        );
        return null;
      }
      frame.kind = current.kind == .leftBracket
          ? .optionalPositional
          : .optionalNamed;
      frame.optionalClose = current.kind == .leftBracket
          ? .rightBracket
          : .rightBrace;
      frame.groupStart = frame.parameters.length;
      parser.advance();
    }
    if (current.kind == frame.optionalClose) {
      if (frame.parameters.length == frame.groupStart) {
        fail('expected_type', 'Expected a parameter in the optional group.');
        return null;
      }
      parser.advance();
      frame.groupClosed = true;
      return finishFunction(frame);
    }
    frame.parameterStart = current.start;
    frame.requiredKeyword = current.kind == .keywordRequired;
    if (frame.requiredKeyword) {
      if (frame.kind != .optionalNamed) {
        fail('invalid_modifier', 'Only named parameters can be required.');
        return null;
      }
      parser.advance();
    }
    frame.covariantKeyword = current.kind == .keywordCovariant;
    if (frame.covariantKeyword) parser.advance();
    return null;
  }

  TypeAnnotation? continueParameters(_FunctionTypes frame) {
    if (current.kind == .comma) {
      parser.advance();
      return prepareParameter(frame);
    }
    if (current.kind == frame.optionalClose) {
      parser.advance();
      frame.groupClosed = true;
      return finishFunction(frame);
    }
    return finishFunction(frame);
  }

  TypeAnnotation? finishFunction(_FunctionTypes frame) {
    if (frame.optionalClose != null && !frame.groupClosed) {
      fail(
        'expected_closer',
        "Expected '${frame.optionalClose!.spelling}' after optional parameters.",
      );
      return null;
    }
    if (current.kind != .rightParen) {
      fail(
        'expected_closer',
        "Expected ')' after the function type parameters.",
      );
      return null;
    }
    final end = current.end;
    parser.advance();
    frames.removeLast();
    final question = nullableOffset();
    return FunctionTypeAnnotation(
      source: source,
      start: frame.returnType?.start ?? frame.function.start,
      end: question == null ? end : question + 1,
      questionOffset: question,
      returnType: frame.returnType,
      typeParameters: frame.typeParameters,
      parameters: FunctionTypeParameterList(
        source: source,
        start: frame.opening!.start,
        end: end,
        parameters: frame.parameters,
      ),
    );
  }
}
