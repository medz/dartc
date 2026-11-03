import 'dart:collection';

import 'package:dartc/ast.dart';
import 'package:dartc/source.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('memory:expression');

  test('building rejects wrong kinds and publishes an immutable tree', () {
    final source = SourceFile(uri, 'x y');
    final builder = SyntaxTreeBuilder(source);
    final x = builder.identifier(start: 0, end: 1);
    final y = builder.identifier(start: 2, end: 3);
    final other = SyntaxTreeBuilder(source);
    final foreign = other.view(other.identifier(start: 0, end: 1));
    expect(() => builder.indexOf(foreign), throwsArgumentError);
    expect(() => builder.view(99), throwsRangeError);
    expect(() => builder.argument(value: x), throwsArgumentError);
    expect(
      () => builder.blockStatement(start: 0, end: 3, statements: [x]),
      throwsArgumentError,
    );
    final names = [x, y];
    final root = builder.dottedName(start: 0, end: 3, components: names);
    names.clear();
    final tree = builder.finish(root);
    expect(tree.view<DottedName>(root).components.map((n) => n.text), [
      'x',
      'y',
    ]);
    final dynamic children = tree.view<DottedName>(root).components;
    expect(() => children.cells[0] = y, throwsNoSuchMethodError);
    expect(() => builder.identifierExpression(x), throwsStateError);
    expect(() => builder.finish(x), throwsStateError);
    expect(() => tree.childAt(root, 2), throwsRangeError);
  });

  test('reading a caller-owned list cannot publish a half-written node', () {
    final source = SourceFile(uri, 'x');
    final builder = SyntaxTreeBuilder(source);
    final id = builder.identifier(start: 0, end: 1);
    final children = _OnRead(() {
      expect(() => builder.finish(id), throwsStateError);
      expect(() => builder.identifierExpression(id), throwsStateError);
      throw FormatException('reading the list failed');
    });
    expect(
      () => builder.dottedName(start: 0, end: 1, components: children),
      throwsFormatException,
    );
    final expr = builder.identifierExpression(id);
    expect(
      builder.finish(expr).view<IdentifierExpression>(expr).identifier.text,
      'x',
    );
  });

  test(
    'copying ranges preserves absolute offsets across the 16-bit boundary',
    () {
      for (final (before, after) in [(65535, 65536), (65536, 65535)]) {
        final source = SourceFile(uri, ' ' * before);
        final builder = SyntaxTreeBuilder(source);
        final id = builder.identifier(start: 65533, end: 65535);
        final tree = builder.finish(id);
        final copy = tree.copyPrefix(
          SourceFile(uri, ' ' * after),
          through: id,
        )!;
        final result = copy.finish(id);
        expect((result.start(id), result.end(id)), (65533, 65535));
        expect((tree.start(id), tree.end(id)), (65533, 65535));
      }
    },
  );

  test(
    'a copied prefix checks all retained ranges and keeps the old snapshot',
    () {
      final builder = SyntaxTreeBuilder(SourceFile(uri, 'a b'));
      builder.identifier(start: 2, end: 3);
      final name = builder.identifier(start: 0, end: 1);
      final tree = builder.finish(name);
      expect(tree.copyPrefix(SourceFile(uri, 'a'), through: name), isNull);
      final next = SourceFile(uri, 'a c');
      final copy = tree.copyPrefix(next, through: name)!;
      final result = copy.finish(name);
      expect(result.view(0).text, 'c');
      expect(result.source, same(next));
      expect(tree.view(0).text, 'b');
    },
  );

  test(
    'prefix reuse keeps a compilation unit at the extent of its snapshot',
    () {
      final source = SourceFile(uri, '');
      final builder = SyntaxTreeBuilder(source);
      final unit = builder.compilationUnit(members: []);
      final tree = builder.finish(unit);
      expect(tree.copyPrefix(SourceFile(uri, ' '), through: unit), isNull);
      expect(tree.view<CompilationUnit>(unit).end, source.length);
    },
  );

  test('a replacement preserves references to shared children', () {
    final builder = SyntaxTreeBuilder(SourceFile(uri, 'x'));
    final name = builder.identifier(start: 0, end: 1);
    final expr = builder.identifierExpression(name);
    final root = builder.argument(value: expr);
    final tree = builder.finish(root);
    final edit = tree.editSubtree(expr, SourceFile(uri, 'y'), changeStart: 0)!;
    final nextName = edit.identifier(start: 0, end: 1);
    expect(() => edit.finish(nextName), throwsStateError);
    final nextExpr = edit.identifierExpression(nextName);
    final updated = edit.finishReplacement(nextExpr)!;
    expect(updated.view<Argument>(root).value.text, 'y');
    expect(tree.view<Argument>(root).value.text, 'x');

    final invalid = tree.editSubtree(
      expr,
      SourceFile(uri, 'y'),
      changeStart: 0,
    )!;
    final leaf = invalid.emptyStatement(start: 0, end: 1);
    final block = invalid.blockStatement(start: 0, end: 1, statements: [leaf]);
    expect(invalid.finishReplacement(block), isNull);
    expect(() => invalid.finish(root), throwsStateError);
  });
}

final class _OnRead(this.read) extends ListBase<int> {
  final int Function() read;
  @override
  int get length => 1;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  int operator [](int index) => read();
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('read only');
}
