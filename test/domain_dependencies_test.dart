import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

void main() {
  test('domains use public entries and have acyclic dependencies', () {
    const dependencies = <String, Set<String>>{
      'ir': {},
      'target': {},
      'sdk': {},
      'export': {},
      'arm64': {},
      'x64': {},
      'analyzer': {'sdk'},
      'lowering': {'analyzer', 'ir', 'interop'},
      'abi': {'arm64', 'x64', 'target'},
      'artifact': {'target'},
      'formats': {'artifact', 'target'},
      'interop': {},
      'codegen': {'abi', 'arm64', 'x64', 'artifact', 'ir', 'interop', 'target'},
      'linker': {'artifact', 'formats', 'target'},
      'compiler': {
        'abi',
        'ir',
        'analyzer',
        'codegen',
        'interop',
        'lowering',
        'sdk',
        'target',
        'artifact',
        'formats',
        'linker',
      },
      'cli': {'artifact', 'compiler', 'sdk', 'target'},
    };
    final lib = Directory('lib').absolute.uri;
    String domain(Uri uri) {
      final segments = uri.pathSegments
          .skip(lib.pathSegments.length - 1)
          .toList();
      return segments.first == 'src'
          ? segments[1]
          : segments.single.split('.').first;
    }

    final edges = <Uri, Set<Uri>>{};
    for (final file in Directory.fromUri(
      lib,
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.uri, owner = domain(file.uri);
      expect(dependencies, contains(owner));
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;
      final links = edges[source] = {};
      for (final directive in unit.directives) {
        expect(
          directive is PartDirective || directive is PartOfDirective,
          isFalse,
          reason: file.path,
        );
        if (directive is! NamespaceDirective) continue;
        for (final literal in [
          directive.uri,
          for (final c in directive.configurations) c.uri,
        ]) {
          final uri = Uri.parse(literal.stringValue!);
          if (uri.scheme == 'dart') continue;
          if (uri.scheme == 'package' && uri.pathSegments.first != 'dartc') {
            expect(
              const {
                'analyzer': {'analyzer', 'lowering'},
                'crypto': {'formats'},
              }[uri.pathSegments.first],
              contains(owner),
              reason: file.path,
            );
            continue;
          }
          final target = uri.scheme == 'package'
              ? lib.resolve(uri.pathSegments.skip(1).join('/'))
              : source.resolveUri(uri);
          expect(
            target.toString().startsWith(lib.toString()),
            isTrue,
            reason: file.path,
          );
          links.add(target);
          final dependency = domain(target);
          if (dependency != owner) {
            expect(directive, isA<ImportDirective>(), reason: file.path);
            expect(
              dependencies[owner],
              contains(dependency),
              reason: '$owner -> $dependency',
            );
            expect(
              uri.toString(),
              'package:dartc/$dependency.dart',
              reason: file.path,
            );
          }
        }
      }
    }
    void checkCycles<T>(Map<T, Set<T>> graph) {
      final done = <T>{}, visiting = <T>{};
      void visit(T source) {
        if (done.contains(source)) return;
        expect(
          visiting.add(source),
          isTrue,
          reason: [...visiting, source].join(' -> '),
        );
        for (final target in graph[source]!) {
          visit(target);
        }
        visiting.remove(source);
        done.add(source);
      }

      graph.keys.forEach(visit);
    }

    checkCycles(edges);
    checkCycles(dependencies);
  });
}
