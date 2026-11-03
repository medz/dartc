import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

void main() {
  test('libraries have acyclic imports and the IR owns its model', () {
    final lib = Directory('lib').absolute.uri;
    final ir = lib.resolve('src/_internal/ir/').toString();
    final edges = <Uri, Set<Uri>>{};
    for (final file in Directory.fromUri(
      lib,
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.uri;
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;
      final links = edges[source] = {};
      for (final d in unit.directives) {
        expect(
          d is PartDirective || d is PartOfDirective,
          isFalse,
          reason: file.path,
        );
        if (d is! NamespaceDirective) continue;
        for (final literal in [
          d.uri,
          for (final c in d.configurations) c.uri,
        ]) {
          final uri = Uri.parse(literal.stringValue!);
          if (uri.scheme == 'dart') continue;
          final target =
              uri.scheme == 'package' && uri.pathSegments.first == 'dartc'
              ? lib.resolve(uri.pathSegments.skip(1).join('/'))
              : source.resolveUri(uri);
          if (source.toString().startsWith(ir)) {
            expect(target.toString(), startsWith(ir), reason: file.path);
          }
          if (target.toString().startsWith(lib.toString())) links.add(target);
        }
      }
    }
    expect(edges.keys.any((f) => f.toString().startsWith(ir)), isTrue);
    final done = <Uri>{}, visiting = <Uri>{};
    void visit(Uri source) {
      if (done.contains(source)) return;
      expect(
        visiting.add(source),
        isTrue,
        reason: [...visiting, source].join(' -> '),
      );
      for (final target in edges[source]!) {
        visit(target);
      }
      visiting.remove(source);
      done.add(source);
    }

    edges.keys.forEach(visit);
  });
}
