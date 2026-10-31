import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Formal parameters', () {
    test(
      'preserves annotations, covariance, named requiredness, and defaults',
      () {
        final f = SyntaxFixture(
          '(@tag covariant num value, {required String name, int count = 2})',
        );
        final metadata = [f.annotation('tag')];
        final parameters = [
          FormalParameter(
            source: f.source,
            start: 1,
            end: f.at(','),
            metadata: metadata,
            kind: .requiredPositional,
            isCovariant: true,
            type: f.type('num'),
            name: f.id('value'),
          ),
          FormalParameter(
            source: f.source,
            start: f.at('required'),
            end: f.at(', int'),
            kind: .requiredNamed,
            type: f.type('String'),
            name: f.id('name'),
          ),
          FormalParameter(
            source: f.source,
            start: f.at('int count'),
            end: f.at('}'),
            kind: .optionalNamed,
            type: f.type('int'),
            name: f.id('count'),
            defaultClause: ParameterDefault(
              source: f.source,
              start: f.at('='),
              end: f.at('}'),
              value: f.literal('2'),
            ),
          ),
        ];
        final list = FormalParameterList(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: parameters,
        );
        metadata.clear();
        parameters.clear();
        checkTree(list);
        expect(list.parameters.map((p) => p.kind), [
          FormalParameterKind.requiredPositional,
          FormalParameterKind.requiredNamed,
          FormalParameterKind.optionalNamed,
        ]);
        expect(list.parameters.first.metadata.single.text, '@tag');
        expect(list.parameters.first.isCovariant, isTrue);
        expect(list.parameters.last.defaultClause!.value.text, '2');
        expect(() => list.parameters.clear(), throwsUnsupportedError);
        expect(
          () => list.parameters.first.metadata.clear(),
          throwsUnsupportedError,
        );
        expect(walk(list).whereType<Identifier>().map((i) => i.text), [
          'tag',
          'num',
          'value',
          'String',
          'name',
          'int',
          'count',
        ]);
      },
    );

    test(
      'retains generic nullable function-form suffixes and nested parameters',
      () {
        final f = SyntaxFixture(
          '(int apply<T extends num>(T value)?, [int fallback(int x) = defaultFn])',
        );
        FunctionParameterSuffix suffix(
          String function,
          String param,
          String type,
        ) {
          final from = f.at(function) + function.length;
          final generic = f.source.text[from] == '<';
          final start = f.at('(', from);
          final end = f.at(')', start) + 1;
          return FunctionParameterSuffix(
            source: f.source,
            start: from,
            end: end + (generic ? 1 : 0),
            typeParameters: generic
                ? TypeParameterList(
                    source: f.source,
                    start: from,
                    end: start,
                    parameters: [
                      TypeParameter(
                        source: f.source,
                        start: from + 1,
                        end: start - 1,
                        name: f.id('T', from),
                        bound: f.type('num'),
                      ),
                    ],
                  )
                : null,
            parameters: FormalParameterList(
              source: f.source,
              start: start,
              end: end,
              parameters: [f.parameter(param, type: f.type(type, from: start))],
            ),
            questionOffset: generic ? end : null,
          );
        }

        final applySuffix = suffix('apply', 'value', 'T');
        final fallbackSuffix = suffix('fallback', 'x', 'int');
        final node = FormalParameterList(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: [
            FormalParameter(
              source: f.source,
              start: 1,
              end: f.at(','),
              kind: .requiredPositional,
              type: f.type('int'),
              name: f.id('apply'),
              functionSuffix: applySuffix,
            ),
            FormalParameter(
              source: f.source,
              start: f.at('[int') + 1,
              end: f.at(']'),
              kind: .optionalPositional,
              type: f.type('int', from: f.at('[')),
              name: f.id('fallback'),
              functionSuffix: fallbackSuffix,
              defaultClause: ParameterDefault(
                source: f.source,
                start: f.at('='),
                end: f.at(']'),
                value: f.reference('defaultFn'),
              ),
            ),
          ],
        );
        checkTree(node);
        expect(applySuffix.questionOffset, f.at('?'));
        expect(fallbackSuffix.typeParameters, isNull);
        expect(fallbackSuffix.questionOffset, isNull);
        expect(node.parameters.last.childAt(2), same(fallbackSuffix));
        expect(
          node.parameters.last.childAt(3),
          same(node.parameters.last.defaultClause),
        );
        expect(
          walk(node).whereType<FormalParameter>().map((p) => p.name.text),
          ['apply', 'value', 'fallback', 'x'],
        );
      },
    );

    test(
      'retains field and super prefixes without resolving their targets',
      () {
        final f = SyntaxFixture(
          '(int this.value, {super.flag, void this.callback(int item)})',
        );
        final callStart = f.at('(int item');
        final parameters = FormalParameterList(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: [
            FormalParameter(
              source: f.source,
              start: 1,
              end: f.at(','),
              kind: .requiredPositional,
              prefix: .thisKeyword,
              type: f.type('int'),
              name: f.id('value'),
            ),
            FormalParameter(
              source: f.source,
              start: f.at('super'),
              end: f.at(', void'),
              kind: .optionalNamed,
              prefix: .superKeyword,
              name: f.id('flag'),
            ),
            FormalParameter(
              source: f.source,
              start: f.at('void'),
              end: f.at('}'),
              kind: .optionalNamed,
              prefix: .thisKeyword,
              type: f.type('void'),
              name: f.id('callback'),
              functionSuffix: FunctionParameterSuffix(
                source: f.source,
                start: callStart,
                end: f.at('}'),
                parameters: FormalParameterList(
                  source: f.source,
                  start: callStart,
                  end: f.at('}'),
                  parameters: [
                    f.parameter('item', type: f.type('int', from: callStart)),
                  ],
                ),
              ),
            ),
          ],
        );
        checkTree(parameters);
        expect(parameters.parameters.map((p) => p.prefix), [
          ParameterPrefix.thisKeyword,
          ParameterPrefix.superKeyword,
          ParameterPrefix.thisKeyword,
        ]);
        expect(parameters.parameters[1].type, isNull);
      },
    );

    test(
      'preserves modifier and legacy default spelling for version checks',
      () {
        final f = SyntaxFixture(
          '(final int value, var other, {int legacy: 1})',
        );
        final node = FormalParameterList(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: [
            FormalParameter(
              source: f.source,
              start: 1,
              end: f.at(','),
              kind: .requiredPositional,
              keyword: .finalKeyword,
              type: f.type('int'),
              name: f.id('value'),
            ),
            FormalParameter(
              source: f.source,
              start: f.at('var'),
              end: f.at(', {'),
              kind: .requiredPositional,
              keyword: .varKeyword,
              name: f.id('other'),
            ),
            FormalParameter(
              source: f.source,
              start: f.at('{') + 1,
              end: f.at('}'),
              kind: .optionalNamed,
              type: f.type('int', from: f.at('{')),
              name: f.id('legacy'),
              defaultClause: ParameterDefault(
                source: f.source,
                start: f.at(':'),
                end: f.at('}'),
                separator: .colon,
                value: f.literal('1'),
              ),
            ),
          ],
        );
        checkTree(node);
        expect(node.parameters.first.keyword, VariableKeyword.finalKeyword);
        expect(node.parameters[1].keyword, VariableKeyword.varKeyword);
        expect(
          node.parameters.last.defaultClause!.separator,
          ParameterDefaultSeparator.colon,
        );
      },
    );

    test('checks optional child order, snapshot ownership, and nullable marker position', () {
      final f = SyntaxFixture('(x) = value');
      final old = SyntaxFixture('(x) = value');
      expect(
        () => FormalParameter(
          source: f.source,
          start: 0,
          end: f.source.length,
          kind: .requiredPositional,
          name: old.id('x'),
        ),
        throwsArgumentError,
      );
      expect(
        () => FormalParameter(
          source: f.source,
          start: 0,
          end: f.source.length,
          kind: .requiredPositional,
          name: f.id('value'),
          defaultClause: ParameterDefault(
            source: f.source,
            start: 0,
            end: 3,
            value: f.reference('x'),
          ),
        ),
        throwsArgumentError,
      );
      final parameters = FormalParameterList(
        source: f.source,
        start: 0,
        end: 3,
        parameters: [f.parameter('x')],
      );
      for (final offset in [-1, 1, f.source.length]) {
        expect(
          () => FunctionParameterSuffix(
            source: f.source,
            start: 0,
            end: f.source.length,
            parameters: parameters,
            questionOffset: offset,
          ),
          throwsRangeError,
        );
      }
      expect(
        () => FormalParameterList(
          source: f.source,
          start: 0,
          end: f.source.length,
          parameters: [f.parameter('value'), f.parameter('x')],
        ),
        throwsArgumentError,
      );
    });
  });
}
