import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

void main() {
  test('libraries have acyclic imports and the IR owns its model', () {
    final lib = Directory('lib').absolute.uri;
    final ir = lib.resolve('ir.dart');
    final lowering = lib.resolve('lowering.dart');
    final irSources = lib.resolve('src/ir/').toString();
    final loweringSources = lib.resolve('src/lowering/').toString();
    bool ownsIr(Uri file) =>
        file == ir || file.toString().startsWith(irSources);
    bool ownsLowering(Uri file) =>
        file == lowering || file.toString().startsWith(loweringSources);
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
          if (ownsIr(source)) {
            expect(ownsIr(target), isTrue, reason: '$source -> $target');
          } else if (source == lowering && d is ExportDirective) {
            expect(ownsLowering(target), isTrue, reason: '$source -> $target');
          } else if (ownsLowering(source) && ownsIr(target)) {
            expect(d, isA<ImportDirective>(), reason: file.path);
            expect(uri.toString(), 'package:dartc/ir.dart', reason: file.path);
          }
          if (target.toString().startsWith(lib.toString())) links.add(target);
        }
      }
    }
    expect(edges.keys, containsAll([ir, lowering]));
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
