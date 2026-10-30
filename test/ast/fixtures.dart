import 'package:dartc/ast.dart';
import 'package:dartc/source.dart';

final class SyntaxFixture(String text) {
  final SourceFile source = SourceFile(Uri.parse('memory:syntax.dart'), text);

  int at(String text, [int from = 0]) {
    final offset = source.text.indexOf(text, from);
    if (offset < 0) throw StateError('Missing fixture text: $text');
    return offset;
  }

  Identifier id(String name, [int from = 0]) {
    final start = at(name, from);
    return Identifier(source: source, start: start, end: start + name.length);
  }

  NamedTypeAnnotation type(String name, {int from = 0, bool nullable = false}) {
    final identifier = id(name, from);
    return NamedTypeAnnotation(
      source: source,
      start: identifier.start,
      end: identifier.end + (nullable ? 1 : 0),
      name: identifier,
      questionOffset: nullable ? identifier.end : null,
    );
  }

  IdentifierExpression reference(String name, [int from = 0]) {
    final identifier = id(name, from);
    return IdentifierExpression(
      source: source,
      start: identifier.start,
      end: identifier.end,
      identifier: identifier,
    );
  }

  LiteralExpression literal(
    String text, {
    LiteralKind kind = .integer,
    int from = 0,
  }) {
    final start = at(text, from);
    return LiteralExpression(
      source: source,
      start: start,
      end: start + text.length,
      kind: kind,
    );
  }

  Annotation annotation(String name) => Annotation(
    source: source,
    start: at('@$name'),
    end: at('@$name') + name.length + 1,
    name: [id(name)],
  );

  BinaryExpression binary(
    Expression left,
    BinaryOperator op,
    Expression right,
  ) => BinaryExpression(
    source: source,
    start: left.start,
    end: right.end,
    left: left,
    op: op,
    right: right,
  );
}

FunctionTypeAnnotation functionTypeFixture() {
  final f = SyntaxFixture(
    'T Function<@tag T extends p.Box<int?>>(T value, {required String name})?',
  );
  final parameterStart = f.at('(T');
  final box = NamedTypeAnnotation(
    source: f.source,
    start: f.at('p.Box'),
    end: f.at('>>') + 1,
    prefix: f.id('p'),
    name: f.id('Box'),
    typeArguments: TypeArgumentList(
      source: f.source,
      start: f.at('<int'),
      end: f.at('>>') + 1,
      arguments: [f.type('int', nullable: true)],
    ),
  );
  return FunctionTypeAnnotation(
    source: f.source,
    start: 0,
    end: f.source.length,
    questionOffset: f.source.length - 1,
    returnType: f.type('T'),
    typeParameters: TypeParameterList(
      source: f.source,
      start: f.at('<@'),
      end: parameterStart,
      parameters: [
        TypeParameter(
          source: f.source,
          start: f.at('@'),
          end: box.end,
          metadata: [f.annotation('tag')],
          name: f.id('T', f.at('@')),
          bound: box,
        ),
      ],
    ),
    parameters: FunctionTypeParameterList(
      source: f.source,
      start: parameterStart,
      end: f.source.length - 1,
      parameters: [
        FunctionTypeParameter(
          source: f.source,
          start: parameterStart + 1,
          end: f.at(','),
          kind: .requiredPositional,
          type: f.type('T', from: parameterStart),
          name: f.id('value'),
        ),
        FunctionTypeParameter(
          source: f.source,
          start: f.at('required'),
          end: f.at('}'),
          kind: .requiredNamed,
          type: f.type('String'),
          name: f.id('name'),
        ),
      ],
    ),
  );
}
