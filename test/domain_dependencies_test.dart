@TestOn('vm')
library;

import 'dart:io';

import 'package:dartc/ast.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';
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
          final unit = parseCompilationUnit(
            scan(
              SourceFile(file.uri, file.readAsStringSync()),
              comments: .leading,
            ),
          );
          for (final directive in unit.node.members.whereType<Directive>()) {
            for (final literal in _uris(directive)) {
              final spelling = literal.text;
              final match = _path.firstMatch(spelling);
              expect(
                match,
                isNotNull,
                reason:
                    'Use a literal dependency URI in ${file.path}: $spelling',
              );
              final uri = Uri.parse(match![2]!);
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
}

final _path = RegExp(r'''^r?(['"])([a-zA-Z0-9_./:%-]+)\1$''');

Iterable<StringExpression> _uris(Directive directive) => switch (directive) {
  ImportDirective(:final uri, :final configurations) ||
  ExportDirective(
    :final uri,
    :final configurations,
  ) => [uri, for (final c in configurations) c.uri],
  PartDirective(:final uri) => [uri],
  PartOfDirective(target: final StringExpression uri) => [uri],
  _ => const [],
};
