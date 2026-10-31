import 'package:dartc/ast.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

DottedName dotted(SyntaxFixture f, String text, [int from = 0]) {
  final start = f.at(text, from);
  var offset = start;
  final components = <Identifier>[];
  for (final name in text.split('.')) {
    components.add(f.id(name, offset));
    offset += name.length + 1;
  }
  return DottedName(
    source: f.source,
    start: start,
    end: start + text.length,
    components: components,
  );
}

void main() {
  group('Directives', () {
    test(
      'retains conditional URIs, metadata, prefix, and repeated combinators',
      () {
        final f = SyntaxFixture(
          "@tag import r'../a.dart' if (dart.library.io) 'native.dart' "
          "if (custom.mode == 'fast') 'fast.dart' deferred as p show A, B hide B show C, C;",
        );
        final metadata = [f.annotation('tag')];
        final configurations = [
          ConditionalUri(
            source: f.source,
            start: f.at('if ('),
            end: f.at("'native.dart'") + 13,
            name: dotted(f, 'dart.library.io'),
            uri: f.string("'native.dart'"),
          ),
          ConditionalUri(
            source: f.source,
            start: f.at('if (custom'),
            end: f.at("'fast.dart'") + 11,
            name: dotted(f, 'custom.mode'),
            value: f.string("'fast'"),
            uri: f.string("'fast.dart'"),
          ),
        ];
        final finalShow = f.at('show C');
        final combinators = [
          NamespaceCombinator(
            source: f.source,
            start: f.at('show A'),
            end: f.at(' hide'),
            kind: .show,
            names: [f.id('A'), f.id('B')],
          ),
          NamespaceCombinator(
            source: f.source,
            start: f.at('hide'),
            end: finalShow - 1,
            kind: .hide,
            names: [f.id('B', f.at('hide'))],
          ),
          NamespaceCombinator(
            source: f.source,
            start: finalShow,
            end: f.at(';'),
            kind: .show,
            names: [f.id('C'), f.id('C', f.at('C') + 1)],
          ),
        ];
        final node = ImportDirective(
          source: f.source,
          start: 0,
          end: f.source.length,
          metadata: metadata,
          uri: f.string("r'../a.dart'"),
          configurations: configurations,
          isDeferred: true,
          prefix: f.id('p', f.at(' as ')),
          combinators: combinators,
        );
        metadata.clear();
        configurations.clear();
        combinators.clear();
        checkTree(node);
        expect(node.uri.text, "r'../a.dart'");
        expect(node.configurations.first.value, isNull);
        expect(node.configurations.last.value!.text, "'fast'");
        expect(node.prefix!.text, 'p');
        expect(node.isDeferred, isTrue);
        expect(node.combinators.map((c) => c.kind), [
          NamespaceCombinatorKind.show,
          NamespaceCombinatorKind.hide,
          NamespaceCombinatorKind.show,
        ]);
        expect(node.combinators.last.names.map((n) => n.text), ['C', 'C']);
        expect(() => node.metadata.clear(), throwsUnsupportedError);
        expect(() => node.configurations.clear(), throwsUnsupportedError);
        expect(() => node.combinators.clear(), throwsUnsupportedError);
        expect(
          () => node.combinators.last.names.clear(),
          throwsUnsupportedError,
        );
        expect(
          [for (var i = 0; i < node.childCount; i++) node.childAt(i).text],
          [
            '@tag',
            "r'../a.dart'",
            "if (dart.library.io) 'native.dart'",
            "if (custom.mode == 'fast') 'fast.dart'",
            'p',
            'show A, B',
            'hide B',
            'show C, C',
          ],
        );
      },
    );

    test('exports keep URI alternatives and combinator order', () {
      final f = SyntaxFixture(
        "@tag export 'a.dart' if (dart.library.io) 'b.dart' hide Hidden show Visible;",
      );
      final condition = ConditionalUri(
        source: f.source,
        start: f.at('if ('),
        end: f.at("'b.dart'") + 8,
        name: dotted(f, 'dart.library.io'),
        uri: f.string("'b.dart'"),
      );
      final node = ExportDirective(
        source: f.source,
        start: 0,
        end: f.source.length,
        metadata: [f.annotation('tag')],
        uri: f.string("'a.dart'"),
        configurations: [condition],
        combinators: [
          NamespaceCombinator(
            source: f.source,
            start: f.at('hide'),
            end: f.at(' show'),
            kind: .hide,
            names: [f.id('Hidden')],
          ),
          NamespaceCombinator(
            source: f.source,
            start: f.at('show'),
            end: f.at(';'),
            kind: .show,
            names: [f.id('Visible')],
          ),
        ],
      );
      checkTree(node);
      expect(node.childAt(2), same(condition));
      expect(node.combinators.map((c) => c.text), [
        'hide Hidden',
        'show Visible',
      ]);
      expect(() => node.configurations.clear(), throwsUnsupportedError);
      expect(() => node.combinators.clear(), throwsUnsupportedError);
    });

    test(
      'supports absent prefixes and optional URI clauses without placeholders',
      () {
        final f = SyntaxFixture("import 'a.dart'; export 'b.dart';");
        final importNode = ImportDirective(
          source: f.source,
          start: 0,
          end: f.at(';') + 1,
          uri: f.string("'a.dart'"),
        );
        final exportNode = ExportDirective(
          source: f.source,
          start: f.at('export'),
          end: f.source.length,
          uri: f.string("'b.dart'"),
        );
        checkTree(importNode);
        checkTree(exportNode);
        expect(importNode.prefix, isNull);
        expect(importNode.isDeferred, isFalse);
        expect(importNode.configurations, isEmpty);
        expect(importNode.combinators, isEmpty);
        expect(importNode.childCount, 1);
        expect(exportNode.childCount, 1);
      },
    );

    test(
      'represents named and unnamed libraries and both part-of target forms',
      () {
        final f = SyntaxFixture(
          "@tag library sample.tools; library; part 'piece.dart'; part of sample.tools; part of 'root.dart';",
        );
        final library = LibraryDirective(
          source: f.source,
          start: 0,
          end: f.at(';') + 1,
          metadata: [f.annotation('tag')],
          name: dotted(f, 'sample.tools'),
        );
        final unnamed = LibraryDirective(
          source: f.source,
          start: f.at('library;'),
          end: f.at('library;') + 8,
        );
        final part = PartDirective(
          source: f.source,
          start: f.at("part '"),
          end: f.at(';', f.at("part '")) + 1,
          uri: f.string("'piece.dart'"),
        );
        final named = PartOfDirective(
          source: f.source,
          start: f.at('part of sample'),
          end: f.at(';', f.at('part of sample')) + 1,
          target: dotted(f, 'sample.tools', f.at('part of sample')),
        );
        final uri = f.string("'root.dart'");
        final byUri = PartOfDirective(
          source: f.source,
          start: f.at("part of '"),
          end: f.source.length,
          target: uri,
        );
        for (final node in [library, unnamed, part, named, byUri]) {
          checkTree(node);
        }
        expect(library.name!.components.map((c) => c.text), [
          'sample',
          'tools',
        ]);
        expect(unnamed.name, isNull);
        expect(unnamed.childCount, 0);
        expect(named.target, isA<DottedName>());
        expect(byUri.childAt(0), same(uri));
        expect(() => library.name!.components.clear(), throwsUnsupportedError);
      },
    );

    test(
      'preserves adjacent strings and diagnostic interpolation structure',
      () {
        final f = SyntaxFixture("import 'a' '.dart'; part of 'a' '.dart';");
        StringExpression adjacent(int from) {
          final first = f.string("'a'", from);
          final second = f.string("'.dart'", from);
          return AdjacentStringsExpression(
            source: f.source,
            start: first.start,
            end: second.end,
            strings: [first, second],
          );
        }

        final importNode = ImportDirective(
          source: f.source,
          start: 0,
          end: f.at(';') + 1,
          uri: adjacent(0),
        );
        final part = PartOfDirective(
          source: f.source,
          start: f.at('part'),
          end: f.source.length,
          target: adjacent(f.at('part')),
        );
        checkTree(importNode);
        checkTree(part);
        expect(importNode.uri.text, "'a' '.dart'");
        expect(walk(part).whereType<StringLiteralExpression>().length, 2);
        final g = SyntaxFixture(r"import '$value';");
        final opening = g.at("'");
        final interpolation = InterpolatedStringExpression(
          source: g.source,
          start: opening,
          end: g.at(';'),
          parts: [
            StringText(source: g.source, start: opening, end: opening + 1),
            StringInterpolation(
              source: g.source,
              start: opening + 1,
              end: g.at(';') - 1,
              expression: g.reference('value'),
              isBraced: false,
            ),
            StringText(source: g.source, start: g.at(';') - 1, end: g.at(';')),
          ],
        );
        final erroneous = ImportDirective(
          source: g.source,
          start: 0,
          end: g.source.length,
          uri: interpolation,
        );
        checkTree(erroneous);
        expect(
          walk(erroneous)
              .whereType<StringInterpolation>()
              .single
              .expression
              .text,
          'value',
        );
      },
    );

    test(
      'rejects stale URIs, reversed alternatives, misplaced prefixes and names',
      () {
        final f = SyntaxFixture(
          "import 'a.dart' if (mode) 'b.dart' as p show A, B;",
        );
        final old = SyntaxFixture(f.source.text);
        final configuration = ConditionalUri(
          source: f.source,
          start: f.at('if ('),
          end: f.at("'b.dart'") + 8,
          name: dotted(f, 'mode'),
          uri: f.string("'b.dart'"),
        );
        expect(
          () => ImportDirective(
            source: f.source,
            start: 0,
            end: f.source.length,
            uri: old.string("'a.dart'"),
          ),
          throwsArgumentError,
        );
        expect(
          () => ImportDirective(
            source: f.source,
            start: 0,
            end: f.source.length,
            uri: f.string("'b.dart'"),
            configurations: [configuration],
          ),
          throwsArgumentError,
        );
        expect(
          () => ImportDirective(
            source: f.source,
            start: 0,
            end: f.source.length,
            uri: f.string("'a.dart'"),
            prefix: f.id('import'),
          ),
          throwsArgumentError,
        );
        expect(
          () => NamespaceCombinator(
            source: f.source,
            start: f.at('show'),
            end: f.at(';'),
            kind: .show,
            names: [f.id('B'), f.id('A')],
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
