@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

void main() {
  test(
    'public domains use their own entry points and have no dependency cycles',
    () {
      final lib = Directory('lib').absolute.uri;
      final domains =
          {
            for (final file in Directory.fromUri(
              lib,
            ).listSync().whereType<File>())
              if (file.path.endsWith('.dart'))
                file.uri.pathSegments.last.split('.').first,
          }..removeWhere(
            (name) =>
                !Directory.fromUri(lib.resolve('src/$name/')).existsSync(),
          );
      final edges = {for (final name in domains) name: <String>{}};
      for (final owner in domains) {
        final entry = File.fromUri(lib.resolve('$owner.dart'));
        final files = Directory.fromUri(lib.resolve('src/$owner/'))
            .listSync(recursive: true)
            .whereType<File>();
        for (final file in [
          entry,
          ...files.where((f) => f.path.endsWith('.dart')),
        ]) {
          final parsed = parseString(
            content: file.readAsStringSync(),
            path: file.path,
          );
          for (final directive in parsed.unit.directives) {
            for (final uri in _uris(directive)) {
              final target =
                  uri.scheme == 'package' &&
                      uri.pathSegments.firstOrNull == 'dartc'
                  ? lib.resolve(uri.pathSegments.skip(1).join('/'))
                  : file.uri.resolveUri(uri);
              if (!target.toString().startsWith(lib.toString())) continue;
              final path = target.path.substring(lib.path.length).split('/');
              final domain = path.length == 1
                  ? path.first.split('.').first
                  : path.first == 'src'
                  ? path[1]
                  : null;
              if (!domains.contains(domain)) continue;
              if (domain == owner) {
                if (directive is ImportDirective ||
                    directive is ExportDirective) {
                  expect(target, isNot(entry.uri), reason: file.path);
                }
              } else {
                expect(directive, isA<ImportDirective>(), reason: file.path);
                expect(
                  uri.toString(),
                  'package:dartc/$domain.dart',
                  reason: file.path,
                );
                edges[owner]!.add(domain!);
              }
            }
          }
        }
      }
      void visit(String name, List<String> path) {
        expect(
          path,
          isNot(contains(name)),
          reason: [...path, name].join(' -> '),
        );
        for (final dependency in edges[name]!) {
          visit(dependency, [...path, name]);
        }
      }

      for (final name in domains) {
        visit(name, const []);
      }
    },
  );

  test('dependency URIs use the decoded values of Dart literals', () {
    final library = parseString(
      content: r"""
import 'local\u002Edart' if (dart.library.io) 'package:dartc/\x61st.dart';
export r'package:dartc/src/' '\u{73}canner/scanner.dart';
part '''unit.dart''';
""",
    );
    final part = parseString(content: r"part of 'entry\u002Edart';");
    expect(
      [...library.unit.directives, ...part.unit.directives].expand(_uris),
      [
        'local.dart',
        'package:dartc/ast.dart',
        'package:dartc/src/scanner/scanner.dart',
        'unit.dart',
        'entry.dart',
      ].map(Uri.parse),
    );
  });
}

Iterable<Uri> _uris(Directive directive) sync* {
  final List<StringLiteral> literals = switch (directive) {
    NamespaceDirective(:final uri, :final configurations) => [
      uri,
      for (final c in configurations) c.uri,
    ],
    PartDirective(:final uri) => [uri],
    PartOfDirective(uri: final uri?) => [uri],
    _ => const [],
  };
  for (final literal in literals) {
    final value = literal.stringValue;
    if (value == null) {
      throw FormatException(
        'Expected a non-interpolated directive URI.',
        literal.toSource(),
      );
    }
    yield Uri.parse(value);
  }
}
